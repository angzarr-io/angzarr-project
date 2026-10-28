//! A real backend in memory: every port and every opt-in capability, held
//! to the conformance suite (ruling 13). Not a test toy: tests, games and
//! anything else that needs no durability use it as their store. It keeps
//! nothing past the process.
//!
//! `MemoryStore` is a handle: clones share one store (so two handles are
//! two clones), and every operation is atomic under one lock, held only
//! for the operation itself (never across an `.await`).
//!
//! - **Units of work** are optimistic: a unit holds its writes, reads the
//!   store with its own writes laid over it, and checks at its append and
//!   again at its commit that no other writer moved the streams it wrote.
//!   It serves any number of units at once, so it never answers
//!   [`StoreError::UnitBusy`].
//! - **Read units** read one moment: the store's data is copy-on-write
//!   behind an `Arc`, so a read unit keeps the moment it began, and a
//!   writer copies the data only while a read unit still holds it.
//! - **Editions** (the [`Editions`] registry and its fall-through) are
//!   PROVISIONAL, pending the per-stream editions spec (owner ruling
//!   2026-10-28): `Editions` is not implemented here yet, so the store has
//!   created no edition. Its streams in any edition are plain streams of
//!   their own, and its read units refuse every edition (EA-2: a store
//!   with no registry has created none).

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, MutexGuard};

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::event_meta::Causation;
use angzarr_proto::v1::{Cover, CreateEditionRequest, Edition, EventBook, EventPage, Snapshot};
use prost_types::Timestamp;

use crate::error::StoreError;
use crate::store::{
    ChangeToken, Editions, EventStore, ListStreams, Outbox, OutboxEntry, PositionStore, Purge,
    ReadByCorrelation, ReadStore, ReadUnit, ReadUntilTime, SnapshotStore, Unit, UnitOfWork,
    UnitOutbox, UnitPurge, Watch,
};
use crate::stream::{PositionKey, Slice, StreamRef};

const EDITIONS_PENDING: &str =
    "MemoryStore's Editions are pending the per-stream editions spec (owner ruling 2026-10-28)";

/// A stream's place: its fields, ordered as [`StreamRef`] orders them
/// (domain, then main before each edition by name, then root as bytes).
type Key = (String, Option<String>, Uuid);

fn key(stream: StreamRef<'_>) -> Key {
    (
        stream.domain.to_string(),
        stream.edition.map(str::to_string),
        stream.root,
    )
}

fn cover(key: &Key) -> Cover {
    StreamRef {
        domain: &key.0,
        edition: key.1.as_deref(),
        root: key.2,
    }
    .to_cover()
}

/// A position's place: the stream, then the handler.
type PositionPlace = (Key, String);

fn place(position: PositionKey<'_>) -> PositionPlace {
    (key(position.stream), position.handler.to_string())
}

/// The store's data: copied on write only while a read unit holds it.
#[derive(Clone, Default)]
struct Data {
    streams: BTreeMap<Key, Vec<EventPage>>,
    snapshots: BTreeMap<Key, Snapshot>,
    positions: BTreeMap<PositionPlace, u64>,
    /// Pending outbox entries, oldest commit first.
    outbox: Vec<OutboxEntry>,
    /// Commits that appended an event: the commit position.
    commit_position: u64,
    /// Commits of anything: the change token.
    commits: u64,
}

impl Data {
    fn pages(&self, k: &Key) -> &[EventPage] {
        self.streams.get(k).map_or(&[], Vec::as_slice)
    }

    fn purge(&mut self, k: &Key) -> u64 {
        self.snapshots.remove(k);
        self.positions.retain(|(stream, _), _| stream != k);
        self.streams.remove(k).map_or(0, |pages| pages.len() as u64)
    }

    fn put_outbox(&mut self, entries: &[OutboxEntry]) {
        for entry in entries {
            if !self.outbox.iter().any(|kept| kept.id == entry.id) {
                self.outbox.push(entry.clone());
            }
        }
    }
}

// `StoreError` is the ports' reviewed error, returned by every port
// method; boxing its fields would change that public shape, so its size is
// accepted here as it is on the trait methods (which clippy does not flag).
#[allow(clippy::result_large_err)]
/// Refuse an append to a stream of `length` that does not expect that
/// length, or whose pages do not run on from it.
fn check_append(
    stream: StreamRef<'_>,
    length: u64,
    expected: u64,
    pages: &[EventPage],
) -> Result<(), StoreError> {
    if expected != length {
        return Err(StoreError::Conflict {
            stream: stream.to_cover(),
            expected,
            actual: length,
        });
    }
    for (due, page) in (expected..).zip(pages) {
        if page.sequence != due {
            return Err(StoreError::Discontinuous {
                stream: stream.to_cover(),
                expected: due,
                found: page.sequence,
            });
        }
    }
    Ok(())
}

/// `pages`, the whole of a stream, as a slice of `from <= sequence < to`.
fn slice(pages: &[EventPage], from: u64, to: Option<u64>) -> Slice {
    let len = pages.len() as u64;
    let start = from.min(len) as usize;
    let end = to.unwrap_or(len).clamp(from.min(len), len) as usize;
    Slice {
        next_sequence: len,
        last_recorded_at: last_recorded_at(pages),
        pages: pages[start..end].to_vec(),
    }
}

fn last_recorded_at(pages: &[EventPage]) -> Option<Timestamp> {
    pages
        .last()
        .and_then(|p| p.meta.as_ref())
        .and_then(|m| m.recorded_at)
}

/// Whether `page` was caused by `command_id` (a command's or a fact's).
fn caused_by(page: &EventPage, command_id: Uuid) -> bool {
    matches!(
        page.meta.as_ref().and_then(|m| m.causation.as_ref()),
        Some(Causation::CommandId(id)) if Uuid::try_from(id).ok() == Some(command_id)
    )
}

fn covers_of(streams: &BTreeMap<Key, Vec<EventPage>>, domain: &str) -> Vec<Cover> {
    streams
        .iter()
        .filter(|(k, pages)| k.0 == domain && !pages.is_empty())
        .map(|(k, _)| cover(k))
        .collect()
}

/// The in-memory store. See the module.
#[derive(Clone, Default)]
pub struct MemoryStore {
    state: Arc<Mutex<Arc<Data>>>,
}

impl MemoryStore {
    /// A new, empty store.
    pub fn new() -> MemoryStore {
        MemoryStore::default()
    }

    fn lock(&self) -> MutexGuard<'_, Arc<Data>> {
        // A panic under the lock leaves no half-written data (every write
        // is checked before it changes anything), so a poisoned lock is
        // still sound.
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// The data now, for reading.
    fn data(&self) -> Arc<Data> {
        Arc::clone(&self.lock())
    }
}

impl EventStore for MemoryStore {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        let k = key(stream);
        let mut guard = self.lock();
        let length = guard.pages(&k).len() as u64;
        check_append(stream, length, expected, pages)?;
        if pages.is_empty() {
            return Ok(length);
        }
        let data = Arc::make_mut(&mut guard);
        data.streams.entry(k).or_default().extend_from_slice(pages);
        data.commit_position += 1;
        data.commits += 1;
        Ok(length + pages.len() as u64)
    }

    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        Ok(slice(self.data().pages(&key(stream)), from, to))
    }

    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        Ok(self
            .data()
            .pages(&key(stream))
            .iter()
            .filter(|p| caused_by(p, command_id))
            .cloned()
            .collect())
    }

    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        Ok(covers_of(&self.data().streams, domain))
    }

    async fn commit_position(&self) -> Result<u64, StoreError> {
        Ok(self.data().commit_position)
    }
}

impl SnapshotStore for MemoryStore {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        Ok(self.data().snapshots.get(&key(stream)).cloned())
    }

    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        let mut guard = self.lock();
        let data = Arc::make_mut(&mut guard);
        data.snapshots.insert(key(stream), snapshot.clone());
        data.commits += 1;
        Ok(())
    }
}

impl PositionStore for MemoryStore {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        Ok(self.data().positions.get(&place(key)).copied().unwrap_or(0))
    }

    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        let mut guard = self.lock();
        let data = Arc::make_mut(&mut guard);
        data.positions.insert(place(key), next);
        data.commits += 1;
        Ok(())
    }
}

/// What a unit has written to one stream.
#[derive(Default)]
struct Pending {
    /// The stream's length in the store when the unit first wrote it (0
    /// after the unit purged it): what the store must still hold at commit.
    base: u64,
    /// Whether the unit purged the stream (before any `pages`).
    purged: bool,
    pages: Vec<EventPage>,
}

/// A unit of work on a [`MemoryStore`]: its pending writes, checked and
/// applied at commit. Owns a handle, so it borrows nothing.
pub struct MemoryUnit {
    store: MemoryStore,
    streams: BTreeMap<Key, Pending>,
    positions: BTreeMap<PositionPlace, u64>,
    outbox: Vec<OutboxEntry>,
}

impl MemoryUnit {
    /// The stream as this unit sees it: the store's (unless it purged it),
    /// then its own pending pages.
    fn view(&self, data: &Data, k: &Key) -> Vec<EventPage> {
        match self.streams.get(k) {
            Some(p) => {
                let mut pages = if p.purged {
                    Vec::new()
                } else {
                    data.pages(k).to_vec()
                };
                pages.extend_from_slice(&p.pages);
                pages
            }
            None => data.pages(k).to_vec(),
        }
    }

    fn purged(&self, k: &Key) -> bool {
        self.streams.get(k).is_some_and(|p| p.purged)
    }

    /// Whether the unit wrote anything at all.
    fn writes(&self) -> bool {
        !self.positions.is_empty()
            || !self.outbox.is_empty()
            || self
                .streams
                .values()
                .any(|p| p.purged || !p.pages.is_empty())
    }
}

impl UnitOfWork for MemoryStore {
    type Unit<'s> = MemoryUnit;

    async fn begin(&self) -> Result<MemoryUnit, StoreError> {
        Ok(MemoryUnit {
            store: self.clone(),
            streams: BTreeMap::new(),
            positions: BTreeMap::new(),
            outbox: Vec::new(),
        })
    }
}

impl Unit for MemoryUnit {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        let k = key(stream);
        let data = self.store.data();
        let length = self.view(&data, &k).len() as u64;
        check_append(stream, length, expected, pages)?;
        if !pages.is_empty() {
            let stored = data.pages(&k).len() as u64;
            let pending = self.streams.entry(k).or_insert_with(|| Pending {
                base: stored,
                ..Pending::default()
            });
            pending.pages.extend_from_slice(pages);
        }
        Ok(length + pages.len() as u64)
    }

    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        let data = self.store.data();
        Ok(slice(&self.view(&data, &key(stream)), from, to))
    }

    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        let data = self.store.data();
        let mut pages = self.view(&data, &key(stream));
        pages.retain(|p| caused_by(p, command_id));
        Ok(pages)
    }

    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        let data = self.store.data();
        let mut keys: Vec<&Key> = data
            .streams
            .keys()
            .chain(self.streams.keys())
            .filter(|k| k.0 == domain)
            .collect();
        keys.sort();
        keys.dedup();
        Ok(keys
            .into_iter()
            .filter(|k| !self.view(&data, k).is_empty())
            .map(cover)
            .collect())
    }

    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        let k = key(stream);
        if self.purged(&k) {
            return Ok(None);
        }
        Ok(self.store.data().snapshots.get(&k).cloned())
    }

    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        let p = place(key);
        if let Some(next) = self.positions.get(&p) {
            return Ok(*next);
        }
        if self.purged(&p.0) {
            return Ok(0);
        }
        Ok(self.store.data().positions.get(&p).copied().unwrap_or(0))
    }

    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        self.positions.insert(place(key), next);
        Ok(())
    }

    async fn commit(self) -> Result<(), StoreError> {
        if !self.writes() {
            return Ok(());
        }
        let mut guard = self.store.lock();
        // Check every stream first: a conflict lands nothing.
        for (k, pending) in &self.streams {
            if pending.purged || pending.pages.is_empty() {
                continue;
            }
            let actual = guard.pages(k).len() as u64;
            if actual != pending.base {
                return Err(StoreError::Conflict {
                    stream: cover(k),
                    expected: pending.base,
                    actual,
                });
            }
        }
        let data = Arc::make_mut(&mut guard);
        let mut appended = false;
        for (k, pending) in self.streams {
            if pending.purged {
                data.purge(&k);
            }
            if !pending.pages.is_empty() {
                appended = true;
                data.streams.entry(k).or_default().extend(pending.pages);
            }
        }
        data.positions.extend(self.positions);
        data.put_outbox(&self.outbox);
        if appended {
            data.commit_position += 1;
        }
        data.commits += 1;
        Ok(())
    }

    async fn abort(self) -> Result<(), StoreError> {
        Ok(())
    }
}

impl Purge for MemoryStore {
    async fn purge(&self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        let mut guard = self.lock();
        let data = Arc::make_mut(&mut guard);
        let deleted = data.purge(&key(stream));
        data.commits += 1;
        Ok(deleted)
    }
}

impl UnitPurge for MemoryUnit {
    async fn purge(&mut self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        let k = key(stream);
        let data = self.store.data();
        let deleted = self.view(&data, &k).len() as u64;
        self.positions.retain(|(s, _), _| *s != k);
        self.streams.insert(
            k,
            Pending {
                base: 0,
                purged: true,
                pages: Vec::new(),
            },
        );
        Ok(deleted)
    }
}

impl Editions for MemoryStore {
    async fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> Result<Edition, StoreError> {
        let _ = (request, now);
        todo!("{EDITIONS_PENDING}")
    }

    async fn delete_edition(&self, name: &str) -> Result<(), StoreError> {
        let _ = name;
        todo!("{EDITIONS_PENDING}")
    }

    async fn edition(&self, name: &str) -> Result<Option<Edition>, StoreError> {
        let _ = name;
        todo!("{EDITIONS_PENDING}")
    }
}

/// A read-only unit on a [`MemoryStore`]: the store's data as it stood at
/// begin, held, so nothing written after is seen through it.
pub struct MemoryRead {
    data: Arc<Data>,
}

impl ReadStore for MemoryStore {
    type Reads<'s> = MemoryRead;

    async fn begin_read(&self) -> Result<MemoryRead, StoreError> {
        Ok(MemoryRead { data: self.data() })
    }
}

// `StoreError` is the ports' reviewed error, returned by every port
// method; boxing its fields would change that public shape, so its size is
// accepted here as it is on the trait methods (which clippy does not flag).
#[allow(clippy::result_large_err)]
/// The store has created no edition (its registry is pending), so a read
/// unit refuses every edition's stream.
fn main_only(stream: StreamRef<'_>) -> Result<Key, StoreError> {
    match stream.edition {
        Some(_) => Err(StoreError::UnknownEdition {
            stream: stream.to_cover(),
        }),
        None => Ok(key(stream)),
    }
}

impl ReadUnit for MemoryRead {
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        let mut covers = covers_of(&self.data.streams, domain);
        covers.retain(|c| c.edition.is_none());
        Ok(covers)
    }

    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        Ok(slice(self.data.pages(&main_only(stream)?), from, to))
    }

    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        Ok(self.data.snapshots.get(&main_only(stream)?).cloned())
    }
}

impl Watch for MemoryStore {
    /// How many commits of anything: equal between two reads only if
    /// nothing was committed between.
    async fn change_token(&self) -> Result<ChangeToken, StoreError> {
        Ok(ChangeToken::new([self.data().commits, 0]))
    }
}

impl ReadUntilTime for MemoryStore {
    async fn read_until_time(
        &self,
        stream: StreamRef<'_>,
        until: &Timestamp,
    ) -> Result<Slice, StoreError> {
        let data = self.data();
        let pages = data.pages(&key(stream));
        let by = |p: &EventPage| {
            p.meta
                .as_ref()
                .and_then(|m| m.recorded_at)
                .is_some_and(|at| (at.seconds, at.nanos) <= (until.seconds, until.nanos))
        };
        Ok(Slice {
            next_sequence: pages.len() as u64,
            last_recorded_at: last_recorded_at(pages),
            pages: pages.iter().take_while(|p| by(p)).cloned().collect(),
        })
    }
}

impl ReadByCorrelation for MemoryStore {
    async fn read_by_correlation(
        &self,
        domain: Option<&str>,
        edition: Option<&str>,
        correlation_id: Uuid,
    ) -> Result<Vec<EventBook>, StoreError> {
        let data = self.data();
        let of = |p: &EventPage| {
            p.meta
                .as_ref()
                .and_then(|m| m.correlation_id.as_ref())
                .is_some_and(|c| Uuid::try_from(c).ok() == Some(correlation_id))
        };
        Ok(data
            .streams
            .iter()
            .filter(|(k, _)| domain.is_none_or(|d| k.0 == d) && k.1.as_deref() == edition)
            .filter_map(|(k, pages)| {
                let mine: Vec<EventPage> = pages.iter().filter(|p| of(p)).cloned().collect();
                (!mine.is_empty()).then(|| EventBook {
                    cover: Some(cover(k)),
                    pages: mine,
                    next_sequence: pages.len() as u64,
                    ..EventBook::default()
                })
            })
            .collect())
    }
}

impl ListStreams for MemoryStore {
    async fn list_streams(&self) -> Result<Vec<Cover>, StoreError> {
        Ok(self
            .data()
            .streams
            .iter()
            .filter(|(_, pages)| !pages.is_empty())
            .map(|(k, _)| cover(k))
            .collect())
    }
}

impl Outbox for MemoryStore {
    async fn pending(&self, limit: usize) -> Result<Vec<OutboxEntry>, StoreError> {
        Ok(self.data().outbox.iter().take(limit).cloned().collect())
    }

    async fn clear(&self, ids: &[Uuid]) -> Result<u64, StoreError> {
        let mut guard = self.lock();
        let before = guard.outbox.len();
        if !guard.outbox.iter().any(|e| ids.contains(&e.id)) {
            return Ok(0);
        }
        let data = Arc::make_mut(&mut guard);
        data.outbox.retain(|e| !ids.contains(&e.id));
        data.commits += 1;
        Ok((before - data.outbox.len()) as u64)
    }
}

impl UnitOutbox for MemoryUnit {
    async fn put_outbox(&mut self, entries: &[OutboxEntry]) -> Result<(), StoreError> {
        self.outbox.extend_from_slice(entries);
        Ok(())
    }
}
