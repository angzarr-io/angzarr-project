//! Every check of the suite, run against a store broken on purpose: each
//! check must fail a store with the bug it exists to catch, so no check is
//! green by accident (annals' `contract.test.rs`, carried over and widened
//! to every section).
//!
//! `Broken` wraps the shipped `MemoryStore` and gets exactly one thing
//! wrong, its [`Bug`]. A check "catches" a bug when it panics on that store
//! with anything but `todo!()`'s "not yet implemented": a stub's panic is no
//! catch. So, while `MemoryStore` is stubbed, every test here is red for
//! that reason, and turns green only when the check really catches the bug
//! on a working store. With no bug (`Honest`), `Broken` must pass every
//! check, so a check that fails it fails it for its bug.

#![cfg(not(target_arch = "wasm32"))]

#[cfg(not(all(feature = "contract", feature = "memory")))]
compile_error!("the meta-tests need the `contract` and `memory` features: run `just test`");

use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use angzarr_ports::angzarr_proto::ids::fact_command_id;
use angzarr_ports::angzarr_proto::v1::event_meta::Causation;
use angzarr_ports::angzarr_proto::v1::{
    Cover, CreateEditionRequest, Edition, EventBook, EventPage, Snapshot,
};
use angzarr_ports::contract;
use angzarr_ports::memory::{MemoryRead, MemoryStore, MemoryUnit};
use angzarr_ports::{
    ChangeToken, Editions, EventStore, Head, ListStreams, Outbox, OutboxEntry, PositionKey,
    PositionStore, Purge, ReadByCorrelation, ReadStore, ReadUnit, ReadUntilTime, Slice,
    SnapshotStore, StoreError, StreamRef, Unit, UnitOfWork, UnitOutbox, UnitPurge, Uuid, Watch,
};
use prost_types::Timestamp;

/// What a [`Broken`] store gets wrong: one bug each.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Bug {
    /// None: every check passes it.
    Honest,
    // ---- appends
    /// It numbers the pages itself, so a gap is accepted.
    AcceptsAGap,
    /// It appends at the stream's length, whatever was expected.
    IgnoresExpected,
    /// An empty append checks no expected length.
    EmptyAppendUnchecked,
    /// An empty append creates the stream.
    EmptyAppendCreates,
    /// An empty append raises the commit position.
    EmptyAppendCommits,
    // ---- reads
    /// A read ignores its `to`.
    IgnoresTo,
    /// A missing stream reads at 1.
    AbsentAtOne,
    /// A read past the end gives where it began as the end.
    ForgetsTheEnd,
    /// Its head's instant is the stream's first event's.
    HeadFirstInstant,
    /// It keys a stream by domain and root, so an edition's is main's.
    IgnoresTheEdition,
    /// It lists a domain's streams by root first.
    ListsByRoot,
    // ---- dedup
    /// It finds a command's events on every stream of the domain.
    FindsAcrossStreams,
    /// It indexes a command's events but not a fact's.
    FactsUnindexed,
    /// It keys a fact's events by the derivation from its external id,
    /// not by their cause: a refusal fact's id is no derivation.
    FactKeyDerived,
    // ---- snapshots and positions
    /// It keeps the snapshot of the highest sequence, not the last written.
    KeepsHighestSnapshot,
    /// Its units read no snapshot.
    UnitSeesNoSnapshot,
    /// A position never falls.
    PositionNeverLowers,
    /// A position is keyed by stream alone.
    PositionIgnoresHandler,
    // ---- commit position
    /// Its commit position never moves.
    PositionStandsStill,
    /// A snapshot write raises its commit position.
    SnapshotIsAnEvent,
    /// Its commit position counts this handle's commits only.
    PositionPerHandle,
    // ---- units
    /// Its units append straight to the store.
    UnitWritesThrough,
    /// Its units' commit lands nothing.
    CommitLandsNothing,
    /// Its units' abort commits.
    AbortCommits,
    /// Its units read the store alone, blind to their own writes.
    UnitIsBlind,
    /// Its units put positions straight to the store.
    UnitPositionWritesThrough,
    /// A second begin on a busy handle waits for the first unit to end.
    BeginWaits,
    /// A second begin on a busy handle is refused, but not as `UnitBusy`.
    BusyAsUnavailable,
    /// A busy handle refuses the second begin, then serves the third.
    RefusesOnlyOnce,
    /// A unit that lost a race still lands its other writes.
    LandsAroundAConflict,
    // ---- purge
    /// A purge keeps the snapshot.
    PurgeKeepsSnapshot,
    /// A purge keeps the stream's positions.
    PurgeKeepsPositions,
    /// A purge deletes nothing, and says it did.
    PurgeIsANoOp,
    /// A unit's purge deletes at once, not at commit.
    UnitPurgeWritesThrough,
    /// A unit's purge counts the stored events, not its pending ones.
    UnitPurgeMissesPending,
    /// A purge lowers the commit position.
    PurgeLowersPosition,
    // ---- editions
    /// A second create of one name answers the first.
    EditionCreatedTwice,
    /// A create with no name succeeds.
    EditionNameless,
    /// An edition's stream reads its own events alone.
    EditionNoFallThrough,
    /// An edition's stream reads main's events past the divergence too.
    EditionFallsThroughPastDivergence,
    /// Deleting an edition deletes main's streams too.
    EditionDeleteTakesMain,
    /// Deleting an unknown edition succeeds.
    EditionDeleteUnknownOk,
    // ---- read units
    /// Its read units read the live store.
    ReadUnitIsLive,
    /// Its read units read any edition.
    ReadUnitAnyEdition,
    /// Its read units read an edition's own events alone.
    ReadUnitNoFallThrough,
    /// Its read units' head is the live store's.
    ReadUnitHeadIsLive,
    /// Its read units' snapshot is the live store's, escaping the moment.
    ReadUnitSnapshotIsLive,
    /// Its read units head any edition, created or not.
    ReadUnitHeadAnyEdition,
    /// Its read units read any edition's snapshot, created or not.
    ReadUnitSnapshotAnyEdition,
    /// Its read units' head counts an edition's own events alone.
    ReadUnitHeadNoFallThrough,
    /// Its read units give an edition main's snapshot when it has none.
    ReadUnitSnapshotFallsThrough,
    // ---- watch
    /// Its token never changes.
    TokenStandsStill,
    /// Its token changes on every read of it.
    TokenChangesOnRead,
    /// Its token counts this handle's commits only.
    TokenPerHandle,
    // ---- core's reads
    /// `read_until_time` excludes events recorded at `until`.
    UntilTimeExclusive,
    /// `read_by_correlation` ignores its domain.
    CorrelationIgnoresDomain,
    /// `read_by_correlation` ignores its edition.
    CorrelationIgnoresEdition,
    /// `list_streams` orders by root first.
    ListStreamsByRoot,
    // ---- outbox
    /// A unit's outbox entries land at once.
    OutboxWritesThrough,
    /// `pending` answers the newest first.
    OutboxNewestFirst,
    /// Reading `pending` clears it.
    PendingClears,
    /// An entry put again replaces the first.
    OutboxKeepsLast,
    /// An id once cleared is never accepted again.
    ClearedIdsRemembered,
    /// Its change token counts events only, not outbox writes.
    OutboxUnwatched,
}

/// One handle's own bookkeeping (a pair's two handles have one each).
#[derive(Default)]
struct Local {
    /// Commits through this handle.
    commits: AtomicU64,
    /// Units open on this handle.
    open: AtomicU64,
    /// Reads of the change token.
    token_reads: AtomicU64,
    /// Begins refused as busy.
    refusals: AtomicU64,
}

/// What every handle on one broken store shares.
#[derive(Default)]
struct Shared {
    /// Added to the commit position.
    offset: AtomicI64,
    /// Streams an empty append created.
    created: Mutex<Vec<Owned>>,
    /// Every position ever put: (handler, stream).
    positions: Mutex<Vec<(String, Owned)>>,
    /// Every outbox id ever cleared.
    cleared: Mutex<Vec<Uuid>>,
}

/// A stream key that owns its strings.
#[derive(Clone, PartialEq, Debug)]
struct Owned(String, Option<String>, Uuid);

impl Owned {
    fn of(s: StreamRef<'_>) -> Owned {
        Owned(s.domain.to_string(), s.edition.map(str::to_string), s.root)
    }
    fn get(&self) -> StreamRef<'_> {
        StreamRef {
            domain: &self.0,
            edition: self.1.as_deref(),
            root: self.2,
        }
    }
}

#[derive(Clone)]
struct Broken {
    inner: MemoryStore,
    bug: Bug,
    local: Arc<Local>,
    shared: Arc<Shared>,
}

fn broken(bug: Bug) -> Broken {
    Broken {
        inner: MemoryStore::new(),
        bug,
        local: Arc::default(),
        shared: Arc::default(),
    }
}

fn broken_pair(bug: Bug) -> (Broken, Broken) {
    let a = broken(bug);
    let b = Broken {
        local: Arc::default(),
        ..a.clone()
    };
    (a, b)
}

fn main_of(s: StreamRef<'_>) -> StreamRef<'_> {
    StreamRef { edition: None, ..s }
}

impl Broken {
    fn is(&self, bug: Bug) -> bool {
        self.bug == bug
    }

    fn keyed<'a>(&self, s: StreamRef<'a>) -> StreamRef<'a> {
        if self.is(Bug::IgnoresTheEdition) {
            main_of(s)
        } else {
            s
        }
    }

    async fn created_edition(&self, s: StreamRef<'_>) -> bool {
        match s.edition {
            Some(name) => matches!(Editions::edition(&self.inner, name).await, Ok(Some(_))),
            None => false,
        }
    }

    /// `slice` of an edition stream without main's history.
    async fn strip_history(&self, s: StreamRef<'_>, mut slice: Slice) -> Slice {
        let main = EventStore::read(&self.inner, main_of(s), 0, None)
            .await
            .unwrap();
        let mut n = 0;
        slice.pages.retain(|p| {
            let history = main.pages.get(n) == Some(p);
            n += 1;
            !history
        });
        slice
    }
}

impl EventStore for Broken {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        let stream = self.keyed(stream);
        if pages.is_empty() {
            match self.bug {
                Bug::EmptyAppendUnchecked => return Ok(expected),
                Bug::EmptyAppendCreates => {
                    self.shared.created.lock().unwrap().push(Owned::of(stream))
                }
                Bug::EmptyAppendCommits => {
                    self.shared.offset.fetch_add(1, Ordering::SeqCst);
                }
                _ => {}
            }
        }
        let mut expected = expected;
        if self.is(Bug::IgnoresExpected) {
            expected = self.inner.head(stream).await?.next_sequence;
        }
        let mut pages = pages.to_vec();
        if self.is(Bug::AcceptsAGap) {
            for (due, page) in (expected..).zip(&mut pages) {
                page.sequence = due;
            }
        }
        let length = self.inner.append(stream, expected, &pages).await?;
        if !pages.is_empty() {
            self.local.commits.fetch_add(1, Ordering::SeqCst);
        }
        Ok(length)
    }

    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        let stream = self.keyed(stream);
        let to = if self.is(Bug::IgnoresTo) { None } else { to };
        let mut slice = self.inner.read(stream, from, to).await?;
        if self.is(Bug::AbsentAtOne) && slice.next_sequence == 0 {
            slice.next_sequence = 1;
        }
        if self.is(Bug::ForgetsTheEnd) && slice.pages.is_empty() {
            slice.next_sequence = from;
        }
        if self.created_edition(stream).await {
            if self.is(Bug::EditionNoFallThrough) {
                slice = self.strip_history(stream, slice).await;
            }
            if self.is(Bug::EditionFallsThroughPastDivergence) {
                let main = self.inner.read(main_of(stream), from, to).await?;
                let mut pages = main.pages;
                let end = pages.len() as u64 + from;
                pages.extend(slice.pages.into_iter().filter(|p| p.sequence >= end));
                slice.pages = pages;
            }
        }
        Ok(slice)
    }

    async fn head(&self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        let mut head = self.read(stream, u64::MAX, None).await?.head();
        if self.is(Bug::HeadFirstInstant) {
            let all = self.read(stream, 0, None).await?;
            head.last_recorded_at = all
                .pages
                .first()
                .and_then(|p| p.meta.as_ref())
                .and_then(|m| m.recorded_at);
        }
        Ok(head)
    }

    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        let stream = self.keyed(stream);
        if self.is(Bug::FindsAcrossStreams) {
            let mut found = Vec::new();
            for cover in self.inner.covers(stream.domain).await? {
                let other = StreamRef::try_from(&cover)?;
                found.extend(self.inner.find_command(other, command_id).await?);
            }
            return Ok(found);
        }
        let mut found = self.inner.find_command(stream, command_id).await?;
        if self.is(Bug::FactKeyDerived) {
            let all = self.inner.read(stream, 0, None).await?;
            return Ok(all
                .pages
                .into_iter()
                .filter(|p| match p.meta.as_ref() {
                    Some(m) => match &m.fact {
                        Some(f) => {
                            Uuid::try_from(&fact_command_id(&f.external_id)).ok() == Some(command_id)
                        }
                        None => matches!(
                            &m.causation,
                            Some(Causation::CommandId(id)) if Uuid::try_from(id).ok() == Some(command_id)
                        ),
                    },
                    None => false,
                })
                .collect());
        }
        if self.is(Bug::FactsUnindexed) {
            found.retain(|p| p.meta.as_ref().is_none_or(|m| m.fact.is_none()));
        }
        Ok(found)
    }

    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        let mut covers = self.inner.covers(domain).await?;
        if self.is(Bug::EmptyAppendCreates) {
            for s in self.shared.created.lock().unwrap().iter() {
                if s.0 == domain {
                    covers.push(s.get().to_cover());
                }
            }
        }
        if self.is(Bug::ListsByRoot) {
            covers.sort_by_key(|c| (c.root.clone().map(|r| r.value), c.edition.clone()));
        }
        Ok(covers)
    }

    async fn commit_position(&self) -> Result<u64, StoreError> {
        let inner = match self.bug {
            Bug::PositionStandsStill => 7,
            Bug::PositionPerHandle => self.local.commits.load(Ordering::SeqCst),
            _ => self.inner.commit_position().await?,
        };
        let offset = self.shared.offset.load(Ordering::SeqCst);
        Ok((inner as i64 + offset).max(0) as u64)
    }
}

impl SnapshotStore for Broken {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        self.inner.read_snapshot(stream).await
    }

    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        if self.is(Bug::KeepsHighestSnapshot) {
            if let Some(kept) = self.inner.read_snapshot(stream).await? {
                if kept.sequence > snapshot.sequence {
                    return Ok(());
                }
            }
        }
        if self.is(Bug::SnapshotIsAnEvent) {
            self.shared.offset.fetch_add(1, Ordering::SeqCst);
        }
        self.inner.write_snapshot(stream, snapshot).await
    }
}

impl PositionStore for Broken {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        let key = if self.is(Bug::PositionIgnoresHandler) {
            PositionKey { handler: "", ..key }
        } else {
            key
        };
        self.inner.position(key).await
    }

    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        let key = if self.is(Bug::PositionIgnoresHandler) {
            PositionKey { handler: "", ..key }
        } else {
            key
        };
        let mut next = next;
        if self.is(Bug::PositionNeverLowers) {
            next = next.max(self.inner.position(key).await?);
        }
        self.shared
            .positions
            .lock()
            .unwrap()
            .push((key.handler.to_string(), Owned::of(key.stream)));
        self.inner.put_position(key, next).await
    }
}

/// A unit on a [`Broken`] store.
struct BrokenUnit {
    inner: MemoryUnit,
    store: Broken,
    /// What it appended, to land around a conflict.
    appended: Vec<(Owned, u64, Vec<EventPage>)>,
    /// The positions it put.
    puts: Vec<(String, Owned, u64)>,
}

impl Drop for BrokenUnit {
    fn drop(&mut self) {
        self.store.local.open.fetch_sub(1, Ordering::SeqCst);
    }
}

impl UnitOfWork for Broken {
    type Unit<'s> = BrokenUnit;

    async fn begin(&self) -> Result<BrokenUnit, StoreError> {
        if self.local.open.load(Ordering::SeqCst) > 0 {
            match self.bug {
                Bug::BeginWaits => std::future::pending::<()>().await,
                Bug::RefusesOnlyOnce if self.local.refusals.fetch_add(1, Ordering::SeqCst) == 0 => {
                    return Err(StoreError::UnitBusy)
                }
                Bug::BusyAsUnavailable => {
                    return Err(StoreError::Unavailable(angzarr_ports::Cause::new(
                        "broken-busy",
                        "busy",
                    )))
                }
                _ => {}
            }
        }
        let inner = self.inner.begin().await?;
        self.local.open.fetch_add(1, Ordering::SeqCst);
        Ok(BrokenUnit {
            inner,
            store: self.clone(),
            appended: Vec::new(),
            puts: Vec::new(),
        })
    }
}

impl Unit for BrokenUnit {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        if self.store.is(Bug::UnitWritesThrough) {
            return self.store.append(stream, expected, pages).await;
        }
        let length = self.inner.append(stream, expected, pages).await?;
        self.appended
            .push((Owned::of(stream), expected, pages.to_vec()));
        Ok(length)
    }

    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        if self.store.is(Bug::UnitIsBlind) {
            return self.store.read(stream, from, to).await;
        }
        self.inner.read(stream, from, to).await
    }

    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        if self.store.is(Bug::UnitIsBlind) {
            return self.store.find_command(stream, command_id).await;
        }
        self.inner.find_command(stream, command_id).await
    }

    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        if self.store.is(Bug::UnitIsBlind) {
            return self.store.covers(domain).await;
        }
        self.inner.covers(domain).await
    }

    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        if self.store.is(Bug::UnitSeesNoSnapshot) {
            return Ok(None);
        }
        self.inner.read_snapshot(stream).await
    }

    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        self.inner.position(key).await
    }

    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        if self.store.is(Bug::UnitPositionWritesThrough) {
            return self.store.put_position(key, next).await;
        }
        self.puts
            .push((key.handler.to_string(), Owned::of(key.stream), next));
        self.inner.put_position(key, next).await
    }

    async fn commit(mut self) -> Result<(), StoreError> {
        let store = self.store.clone();
        let appended = std::mem::take(&mut self.appended);
        let puts = std::mem::take(&mut self.puts);
        let inner = std::mem::replace(&mut self.inner, store.inner.begin().await?);
        if store.is(Bug::CommitLandsNothing) {
            return inner.abort().await;
        }
        let landed = inner.commit().await;
        if let Err(StoreError::Conflict { stream, .. }) = &landed {
            if store.is(Bug::LandsAroundAConflict) {
                for (s, expected, pages) in &appended {
                    if s.get().to_cover() != *stream {
                        let _ = store.inner.append(s.get(), *expected, pages).await;
                    }
                }
                for (handler, s, next) in &puts {
                    let key = PositionKey {
                        handler,
                        stream: s.get(),
                    };
                    let _ = store.inner.put_position(key, *next).await;
                }
            }
        }
        if landed.is_ok() && !appended.is_empty() {
            store.local.commits.fetch_add(1, Ordering::SeqCst);
        }
        landed
    }

    async fn abort(self) -> Result<(), StoreError> {
        if self.store.is(Bug::AbortCommits) {
            return self.commit().await;
        }
        let mut this = self;
        let store = this.store.clone();
        let inner = std::mem::replace(&mut this.inner, store.inner.begin().await?);
        inner.abort().await
    }
}

impl Purge for Broken {
    async fn purge(&self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        if self.is(Bug::PurgeIsANoOp) {
            return Ok(self.inner.head(stream).await?.next_sequence);
        }
        let snapshot = self.inner.read_snapshot(stream).await?;
        let kept: Vec<(String, u64)> = if self.is(Bug::PurgeKeepsPositions) {
            let puts = self.shared.positions.lock().unwrap().clone();
            let mut kept = Vec::new();
            for (handler, s) in puts.iter().filter(|(_, s)| s.get() == stream) {
                let key = PositionKey {
                    handler,
                    stream: s.get(),
                };
                kept.push((handler.clone(), self.inner.position(key).await?));
            }
            kept
        } else {
            Vec::new()
        };
        let deleted = self.inner.purge(stream).await?;
        if let (Bug::PurgeKeepsSnapshot, Some(s)) = (self.bug, snapshot) {
            self.inner.write_snapshot(stream, &s).await?;
        }
        for (handler, next) in kept {
            let key = PositionKey {
                handler: &handler,
                stream,
            };
            self.inner.put_position(key, next).await?;
        }
        if self.is(Bug::PurgeLowersPosition) {
            self.shared.offset.fetch_sub(100, Ordering::SeqCst);
        }
        Ok(deleted)
    }
}

impl UnitPurge for BrokenUnit {
    async fn purge(&mut self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        if self.store.is(Bug::UnitPurgeWritesThrough) {
            return self.store.purge(stream).await;
        }
        let stored = self.store.inner.head(stream).await?.next_sequence;
        let deleted = self.inner.purge(stream).await?;
        if self.store.is(Bug::UnitPurgeMissesPending) {
            return Ok(stored);
        }
        Ok(deleted)
    }
}

impl Editions for Broken {
    async fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> Result<Edition, StoreError> {
        if self.is(Bug::EditionNameless) && request.name.is_empty() {
            let named = CreateEditionRequest {
                name: "nameless".to_string(),
                ..request.clone()
            };
            return self.inner.create_edition(&named, now).await;
        }
        match self.inner.create_edition(request, now).await {
            Err(StoreError::EditionExists { name }) if self.is(Bug::EditionCreatedTwice) => {
                Ok(self.inner.edition(&name).await?.expect("it exists"))
            }
            made => made,
        }
    }

    async fn delete_edition(&self, name: &str) -> Result<(), StoreError> {
        let deleted = match self.inner.delete_edition(name).await {
            Err(StoreError::EditionNotFound { .. }) if self.is(Bug::EditionDeleteUnknownOk) => {
                Ok(())
            }
            deleted => deleted,
        };
        if self.is(Bug::EditionDeleteTakesMain) {
            for cover in self.inner.list_streams().await? {
                if cover.edition.is_none() {
                    self.inner.purge(StreamRef::try_from(&cover)?).await?;
                }
            }
        }
        deleted
    }

    async fn edition(&self, name: &str) -> Result<Option<Edition>, StoreError> {
        self.inner.edition(name).await
    }
}

/// A read unit on a [`Broken`] store.
struct BrokenRead {
    inner: MemoryRead,
    store: Broken,
}

impl ReadStore for Broken {
    type Reads<'s> = BrokenRead;

    async fn begin_read(&self) -> Result<BrokenRead, StoreError> {
        Ok(BrokenRead {
            inner: self.inner.begin_read().await?,
            store: self.clone(),
        })
    }
}

impl ReadUnit for BrokenRead {
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        if self.store.is(Bug::ReadUnitIsLive) {
            return self.store.covers(domain).await;
        }
        self.inner.covers(domain).await
    }

    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        let live = self.store.is(Bug::ReadUnitIsLive)
            || (self.store.is(Bug::ReadUnitAnyEdition) && stream.edition.is_some());
        if live {
            return self.store.read(stream, from, to).await;
        }
        let slice = self.inner.read(stream, from, to).await?;
        if self.store.is(Bug::ReadUnitNoFallThrough) && self.store.created_edition(stream).await {
            return Ok(self.store.strip_history(stream, slice).await);
        }
        Ok(slice)
    }

    async fn head(&mut self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        let live = self.store.is(Bug::ReadUnitHeadIsLive)
            || (self.store.is(Bug::ReadUnitHeadAnyEdition) && stream.edition.is_some());
        if live {
            return self.store.head(stream).await;
        }
        let mut head = ReadUnit::head(&mut self.inner, stream).await?;
        if self.store.is(Bug::ReadUnitHeadNoFallThrough) && self.store.created_edition(stream).await
        {
            let all = self.inner.read(stream, 0, None).await?;
            head.next_sequence = self.store.strip_history(stream, all).await.pages.len() as u64;
        }
        Ok(head)
    }

    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        let live = self.store.is(Bug::ReadUnitSnapshotIsLive)
            || (self.store.is(Bug::ReadUnitSnapshotAnyEdition) && stream.edition.is_some());
        if live {
            return self.store.read_snapshot(stream).await;
        }
        let own = self.inner.read_snapshot(stream).await?;
        if own.is_none()
            && self.store.is(Bug::ReadUnitSnapshotFallsThrough)
            && self.store.created_edition(stream).await
        {
            return self.inner.read_snapshot(main_of(stream)).await;
        }
        Ok(own)
    }
}

impl Watch for Broken {
    async fn change_token(&self) -> Result<ChangeToken, StoreError> {
        match self.bug {
            Bug::TokenStandsStill => Ok(ChangeToken::new([0, 0])),
            Bug::TokenChangesOnRead => Ok(ChangeToken::new([
                self.local.token_reads.fetch_add(1, Ordering::SeqCst),
                0,
            ])),
            Bug::OutboxUnwatched => Ok(ChangeToken::new([
                self.local.commits.load(Ordering::SeqCst),
                0,
            ])),
            Bug::TokenPerHandle => Ok(ChangeToken::new([
                self.local.commits.load(Ordering::SeqCst),
                0,
            ])),
            _ => self.inner.change_token().await,
        }
    }
}

impl ReadUntilTime for Broken {
    async fn read_until_time(
        &self,
        stream: StreamRef<'_>,
        until: &Timestamp,
    ) -> Result<Slice, StoreError> {
        let mut until = *until;
        if self.is(Bug::UntilTimeExclusive) {
            until.nanos -= 1;
        }
        self.inner.read_until_time(stream, &until).await
    }
}

impl ReadByCorrelation for Broken {
    async fn read_by_correlation(
        &self,
        domain: Option<&str>,
        edition: Option<&str>,
        correlation_id: Uuid,
    ) -> Result<Vec<EventBook>, StoreError> {
        let domain = if self.is(Bug::CorrelationIgnoresDomain) {
            None
        } else {
            domain
        };
        let edition = if self.is(Bug::CorrelationIgnoresEdition) {
            None
        } else {
            edition
        };
        self.inner
            .read_by_correlation(domain, edition, correlation_id)
            .await
    }
}

impl ListStreams for Broken {
    async fn list_streams(&self) -> Result<Vec<Cover>, StoreError> {
        let mut all = self.inner.list_streams().await?;
        if self.is(Bug::ListStreamsByRoot) {
            all.sort_by_key(|c| c.root.clone().map(|r| r.value));
        }
        Ok(all)
    }
}

impl Outbox for Broken {
    async fn pending(&self, limit: usize) -> Result<Vec<OutboxEntry>, StoreError> {
        let mut pending = self.inner.pending(usize::MAX).await?;
        if self.is(Bug::OutboxNewestFirst) {
            pending.reverse();
        }
        pending.truncate(limit);
        if self.is(Bug::PendingClears) {
            let ids: Vec<Uuid> = pending.iter().map(|e| e.id).collect();
            self.inner.clear(&ids).await?;
        }
        Ok(pending)
    }

    async fn clear(&self, ids: &[Uuid]) -> Result<u64, StoreError> {
        self.shared.cleared.lock().unwrap().extend_from_slice(ids);
        self.inner.clear(ids).await
    }
}

impl UnitOutbox for BrokenUnit {
    async fn put_outbox(&mut self, entries: &[OutboxEntry]) -> Result<(), StoreError> {
        if self.store.is(Bug::ClearedIdsRemembered) {
            let cleared = self.store.shared.cleared.lock().unwrap().clone();
            let fresh: Vec<OutboxEntry> = entries
                .iter()
                .filter(|e| !cleared.contains(&e.id))
                .cloned()
                .collect();
            return self.inner.put_outbox(&fresh).await;
        }
        if self.store.is(Bug::OutboxWritesThrough) {
            let mut now = self.store.inner.begin().await?;
            now.put_outbox(entries).await?;
            return now.commit().await;
        }
        if self.store.is(Bug::OutboxKeepsLast) {
            let mut last: Vec<OutboxEntry> = Vec::new();
            for e in entries {
                last.retain(|kept| kept.id != e.id);
                last.push(e.clone());
            }
            let ids: Vec<Uuid> = last.iter().map(|e| e.id).collect();
            self.store.inner.clear(&ids).await?;
            return self.inner.put_outbox(&last).await;
        }
        self.inner.put_outbox(entries).await
    }
}

// ------------------------------------------------------------------ harness

/// Run `check` to its end on a fresh current-thread runtime: `Ok` if it
/// passed, else the panic's message.
fn run<F: Future>(check: F) -> Result<(), String> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    std::panic::catch_unwind(AssertUnwindSafe(|| {
        runtime.block_on(check);
    }))
    .map_err(|payload| {
        payload
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
            .unwrap_or_default()
    })
}

/// Whether `check` CAUGHT the bug: it panicked, and not on a stub.
fn caught<F: Future>(check: F) -> Result<(), String> {
    match run(check) {
        Ok(()) => Err("passed: the check does not catch this bug".to_string()),
        Err(m) if m.contains("not yet implemented") => {
            Err(format!("panicked on a stub, which is no catch: {m}"))
        }
        Err(_) => Ok(()),
    }
}

/// Require `check` to catch each bug, on a fresh store or pair.
macro_rules! catches {
    ($check:ident, $make:ident, $($bug:ident),+ $(,)?) => {
        $(
            if let Err(why) = caught(contract::$check($make(Bug::$bug))) {
                panic!("{} on a store that {:?}: {why}", stringify!($check), Bug::$bug);
            }
        )+
    };
}

/// Require `Honest` to pass each check.
macro_rules! passes {
    ($make:ident; $($check:ident),+ $(,)?) => {
        $(
            if let Err(why) = run(contract::$check($make(Bug::Honest))) {
                panic!("{} fails an honest store: {why}", stringify!($check));
            }
        )+
    };
}

// ------------------------------------------------- base: each check catches

#[test]
fn the_append_checks_catch_a_gap_and_an_unchecked_expected_length() {
    catches!(
        append_checks_the_expected_length_and_continuity,
        broken,
        AcceptsAGap
    );
    catches!(
        append_refuses_a_stale_first_sequence,
        broken,
        IgnoresExpected
    );
}

#[test]
fn the_empty_append_check_catches_one_that_checks_creates_or_commits() {
    catches!(
        an_empty_append_checks_and_creates_nothing,
        broken,
        EmptyAppendUnchecked,
        EmptyAppendCreates,
        EmptyAppendCommits,
    );
}

#[test]
fn the_read_checks_catch_a_wrong_range_start_or_end() {
    catches!(read_is_bounded_by_from_and_to, broken, IgnoresTo);
    catches!(
        a_read_of_no_such_stream_is_empty_at_zero,
        broken,
        AbsentAtOne
    );
    catches!(
        a_read_past_the_end_is_empty_but_knows_the_end,
        broken,
        ForgetsTheEnd
    );
    catches!(
        head_is_the_next_sequence_and_the_last_recorded_at,
        broken,
        HeadFirstInstant
    );
}

#[test]
fn the_stream_checks_catch_a_lost_edition_and_a_wrong_order() {
    catches!(
        a_stream_is_domain_edition_and_root,
        broken,
        IgnoresTheEdition
    );
    catches!(
        covers_orders_main_first_then_by_edition_and_root,
        broken,
        ListsByRoot
    );
}

#[test]
fn the_dedup_checks_catch_lookups_too_wide() {
    catches!(
        find_command_finds_a_commands_events_on_its_stream,
        broken,
        FindsAcrossStreams
    );
    catches!(
        find_command_finds_a_retried_facts_events_by_its_id,
        broken,
        FactsUnindexed
    );
    catches!(
        find_command_finds_a_refusal_fact_on_the_trigger_stream_by_the_refused_id,
        broken,
        FactKeyDerived
    );
}

#[test]
fn the_snapshot_and_position_checks_catch_a_store_that_judges_or_merges() {
    catches!(
        a_store_keeps_the_newest_snapshot_per_stream,
        broken,
        KeepsHighestSnapshot,
        UnitSeesNoSnapshot,
    );
    catches!(
        a_position_is_zero_until_put_then_the_last_put,
        broken,
        PositionNeverLowers
    );
    catches!(
        positions_are_per_handler_and_per_stream,
        broken,
        PositionIgnoresHandler
    );
}

#[test]
fn the_commit_position_check_catches_one_that_stands_still_or_counts_snapshots() {
    catches!(
        the_commit_position_rises_with_every_commit,
        broken,
        PositionStandsStill,
        SnapshotIsAnEvent,
    );
}

#[test]
fn the_unit_checks_catch_writes_through_lost_commits_and_blindness() {
    catches!(
        a_unit_of_work_lands_at_commit_or_not_at_all,
        broken,
        UnitWritesThrough,
        CommitLandsNothing,
    );
    catches!(an_aborted_unit_of_work_lands_nothing, broken, AbortCommits);
    catches!(
        a_unit_of_work_checks_and_reads_its_pending_appends,
        broken,
        UnitIsBlind
    );
    catches!(
        a_unit_of_work_lists_its_pending_streams,
        broken,
        UnitIsBlind
    );
    catches!(
        a_unit_of_work_finds_its_pending_commands_and_facts,
        broken,
        UnitIsBlind
    );
    catches!(
        a_unit_of_work_puts_positions_with_its_appends,
        broken,
        UnitPositionWritesThrough
    );
}

#[test]
fn the_second_begin_check_catches_a_wait_and_a_wrong_refusal() {
    catches!(
        a_second_begin_on_a_handle_serves_or_refuses_never_waits,
        broken,
        BeginWaits,
        BusyAsUnavailable,
        RefusesOnlyOnce,
    );
}

#[test]
fn the_pair_checks_catch_a_handles_own_count_and_a_partial_landing() {
    catches!(
        the_commit_position_counts_every_handles_commits,
        broken_pair,
        PositionPerHandle
    );
    catches!(
        a_unit_that_lost_a_race_lands_nothing,
        broken_pair,
        LandsAroundAConflict
    );
}

#[test]
fn the_purge_checks_catch_what_a_purge_leaves_or_lowers() {
    catches!(
        a_purge_deletes_a_streams_events_snapshot_and_command_ids,
        broken,
        PurgeKeepsSnapshot,
        PurgeIsANoOp,
    );
    catches!(
        a_purge_deletes_the_streams_positions,
        broken,
        PurgeKeepsPositions
    );
    catches!(
        a_purge_deletes_a_snapshot_with_no_events,
        broken,
        PurgeKeepsSnapshot
    );
    catches!(
        a_purged_stream_starts_again_from_nothing,
        broken,
        PurgeIsANoOp
    );
    catches!(
        a_purge_in_a_unit_of_work_lands_at_commit_or_not_at_all,
        broken,
        UnitPurgeWritesThrough
    );
    catches!(
        a_unit_of_work_purges_its_own_appends_and_appends_after,
        broken,
        UnitPurgeMissesPending
    );
    catches!(
        a_purge_never_lowers_the_commit_position,
        broken,
        PurgeLowersPosition
    );
}

#[test]
fn the_edition_checks_catch_a_lax_registry_and_a_wrong_fall_through() {
    catches!(
        an_edition_is_created_once_and_recorded,
        broken,
        EditionCreatedTwice
    );
    catches!(
        an_edition_create_refuses_a_bad_request,
        broken,
        EditionNameless
    );
    catches!(
        an_edition_reads_mains_events_below_its_divergence_then_its_own,
        broken,
        EditionNoFallThrough,
        EditionFallsThroughPastDivergence,
    );
    catches!(
        deleting_an_edition_removes_it_and_its_streams_never_mains,
        broken,
        EditionDeleteTakesMain
    );
    catches!(
        deleting_an_edition_refuses_an_empty_or_unknown_name,
        broken,
        EditionDeleteUnknownOk
    );
}

#[test]
fn the_read_unit_head_and_snapshot_checks_catch_a_live_or_lax_unit() {
    catches!(
        a_read_unit_heads_and_snapshots_as_it_began,
        broken_pair,
        ReadUnitHeadIsLive,
        ReadUnitSnapshotIsLive,
    );
    catches!(
        a_read_unit_refuses_heads_and_snapshots_in_an_edition_never_created,
        broken_pair,
        ReadUnitHeadAnyEdition,
        ReadUnitSnapshotAnyEdition,
    );
    catches!(
        a_read_unit_keeps_the_head_and_snapshot_of_a_stream_purged_after_it_began,
        broken_pair,
        ReadUnitHeadIsLive,
        ReadUnitSnapshotIsLive,
    );
    catches!(
        a_read_unit_heads_a_created_edition_through_to_main_but_not_its_snapshots,
        broken,
        ReadUnitHeadNoFallThrough,
        ReadUnitSnapshotFallsThrough,
    );
}

#[test]
fn the_read_unit_checks_catch_a_live_unit_and_a_wrong_edition() {
    catches!(
        a_read_unit_sees_the_store_as_it_began,
        broken_pair,
        ReadUnitIsLive
    );
    catches!(
        a_read_unit_refuses_an_edition_never_created,
        broken_pair,
        ReadUnitAnyEdition
    );
    catches!(
        a_read_unit_keeps_a_stream_purged_after_it_began,
        broken_pair,
        ReadUnitIsLive
    );
    catches!(
        a_read_unit_reads_a_created_edition_through_to_main,
        broken,
        ReadUnitNoFallThrough
    );
}

#[test]
fn the_watch_checks_catch_a_token_still_restless_or_per_handle() {
    catches!(
        a_change_token_changes_when_its_own_store_commits,
        broken,
        TokenStandsStill,
        TokenChangesOnRead,
    );
    catches!(
        a_change_token_changes_when_another_handle_commits,
        broken_pair,
        TokenPerHandle
    );
}

#[test]
fn the_core_read_checks_catch_a_wrong_bound_filter_or_order() {
    catches!(
        read_until_time_is_the_prefix_recorded_by_then,
        broken,
        UntilTimeExclusive
    );
    catches!(
        read_by_correlation_gives_one_book_per_stream,
        broken,
        CorrelationIgnoresDomain,
        CorrelationIgnoresEdition,
    );
    catches!(
        list_streams_is_every_domains_covers_in_order,
        broken,
        ListStreamsByRoot
    );
}

#[test]
fn the_outbox_checks_catch_early_lost_reordered_or_replaced_entries() {
    catches!(
        an_outbox_entry_lands_with_its_unit_or_not_at_all,
        broken,
        OutboxWritesThrough
    );
    catches!(
        the_outbox_drains_oldest_first_and_clears,
        broken,
        OutboxNewestFirst
    );
    catches!(
        a_pending_entry_is_redelivered_until_cleared,
        broken,
        PendingClears
    );
    catches!(
        an_entry_put_again_while_pending_keeps_its_first_message,
        broken,
        OutboxKeepsLast
    );
    catches!(
        a_cleared_id_put_again_is_a_new_pending_entry,
        broken,
        ClearedIdsRemembered
    );
    catches!(
        an_outbox_write_changes_the_change_token,
        broken,
        OutboxUnwatched
    );
}

// -------------------- and with no bug, every check passes the same wrapper

#[test]
fn an_honest_broken_store_passes_every_check() {
    passes!(broken;
        append_checks_the_expected_length_and_continuity,
        append_refuses_a_stale_first_sequence,
        an_empty_append_checks_and_creates_nothing,
        read_is_bounded_by_from_and_to,
        a_read_of_no_such_stream_is_empty_at_zero,
        a_read_past_the_end_is_empty_but_knows_the_end,
        head_is_the_next_sequence_and_the_last_recorded_at,
        a_stream_is_domain_edition_and_root,
        covers_orders_main_first_then_by_edition_and_root,
        find_command_finds_a_commands_events_on_its_stream,
        find_command_finds_a_retried_facts_events_by_its_id,
        find_command_finds_a_refusal_fact_on_the_trigger_stream_by_the_refused_id,
        a_store_keeps_the_newest_snapshot_per_stream,
        a_position_is_zero_until_put_then_the_last_put,
        positions_are_per_handler_and_per_stream,
        the_commit_position_rises_with_every_commit,
        a_unit_of_work_lands_at_commit_or_not_at_all,
        an_aborted_unit_of_work_lands_nothing,
        a_unit_of_work_checks_and_reads_its_pending_appends,
        a_unit_of_work_lists_its_pending_streams,
        a_unit_of_work_finds_its_pending_commands_and_facts,
        a_unit_of_work_puts_positions_with_its_appends,
        a_second_begin_on_a_handle_serves_or_refuses_never_waits,
        a_purge_deletes_a_streams_events_snapshot_and_command_ids,
        a_purge_deletes_the_streams_positions,
        a_purge_deletes_a_snapshot_with_no_events,
        a_purged_stream_starts_again_from_nothing,
        a_purge_in_a_unit_of_work_lands_at_commit_or_not_at_all,
        a_unit_of_work_purges_its_own_appends_and_appends_after,
        a_purge_never_lowers_the_commit_position,
        an_edition_is_created_once_and_recorded,
        an_edition_create_refuses_a_bad_request,
        an_edition_reads_mains_events_below_its_divergence_then_its_own,
        deleting_an_edition_removes_it_and_its_streams_never_mains,
        deleting_an_edition_refuses_an_empty_or_unknown_name,
        a_read_unit_reads_a_created_edition_through_to_main,
        a_read_unit_heads_a_created_edition_through_to_main_but_not_its_snapshots,
        a_change_token_changes_when_its_own_store_commits,
        read_until_time_is_the_prefix_recorded_by_then,
        read_by_correlation_gives_one_book_per_stream,
        list_streams_is_every_domains_covers_in_order,
        an_outbox_entry_lands_with_its_unit_or_not_at_all,
        the_outbox_drains_oldest_first_and_clears,
        a_pending_entry_is_redelivered_until_cleared,
        an_entry_put_again_while_pending_keeps_its_first_message,
        a_cleared_id_put_again_is_a_new_pending_entry,
        an_outbox_write_changes_the_change_token,
    );
    passes!(broken_pair;
        the_commit_position_counts_every_handles_commits,
        a_unit_that_lost_a_race_lands_nothing,
        a_read_unit_sees_the_store_as_it_began,
        a_read_unit_refuses_an_edition_never_created,
        a_read_unit_keeps_a_stream_purged_after_it_began,
        a_read_unit_heads_and_snapshots_as_it_began,
        a_read_unit_refuses_heads_and_snapshots_in_an_edition_never_created,
        a_read_unit_keeps_the_head_and_snapshot_of_a_stream_purged_after_it_began,
        a_change_token_changes_when_another_handle_commits,
    );
}
