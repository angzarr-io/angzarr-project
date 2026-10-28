//! The ports: one trait set for every backend.
//!
//! Every method returns `impl Future + MaybeSend`: `Send` on every target
//! but `wasm32` ([`crate::send`]). A backend writes each as a plain
//! `async fn`. Stores take `&self`, so one handle is shared (`Arc`) and a
//! store does its own locking; a [`Unit`] takes `&mut self`, because a
//! transaction is exclusive.
//!
//! The base ports ([`Store`]) are every backend's. The rest are opt-in, one
//! trait per capability, so a store that lacks one is honest by type.

use std::future::Future;
use std::sync::Arc;

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::{Cover, CreateEditionRequest, Edition, EventBook, EventPage, Snapshot};
use prost_types::{Any, Timestamp};

use crate::error::StoreError;
use crate::send::{MaybeSend, MaybeSync};
use crate::stream::{Head, PositionKey, Slice, StreamRef};

// =================================================================== base

/// Where streams are kept: one append-only log of opaque pages per stream.
///
/// **Opaque.** A store keeps each [`EventPage`] as written and copies what
/// it indexes into columns. It never decodes a payload, never assigns or
/// rewrites a sequence; upcasting is the reader's, on every read.
///
/// **Editions (EA-3).** In a store that keeps the edition registry
/// ([`Editions`]), a created edition's stream reads main's events committed
/// below the edition's divergence commit position, then its own, numbered
/// on from them. Every read, lookup and append here sees that history. A
/// stream in an edition never created is a plain stream of its own.
pub trait EventStore: MaybeSend + MaybeSync {
    /// Append `pages` to `stream` as one autocommitted write, creating the
    /// stream when `expected` is its length and it holds nothing. Refused,
    /// appending nothing: a stream not at `expected`
    /// ([`StoreError::Conflict`]); pages whose sequences do not run on from
    /// `expected` ([`StoreError::Discontinuous`]). No pages checks
    /// `expected` and writes nothing. Returns the stream's new length.
    fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;

    /// The pages with `from <= sequence < to` (`to` `None`: to the end), in
    /// sequence order, with the stream's head as read. An absent stream is
    /// an empty slice at 0; a range past the end is empty but knows the end.
    fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + MaybeSend;

    /// The stream's head: by default a read past the end.
    fn head(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Head, StoreError>> + MaybeSend {
        async move { Ok(self.read(stream, u64::MAX, None).await?.head()) }
    }

    /// The pages of `stream` caused by the command `command_id`, in
    /// sequence order: the dedup lookup, for commands and facts alike. A
    /// fact's events carry its derived command id
    /// (`fact_command_id(external_id)`) as their cause, so a process
    /// manager, which takes facts only, deduplicates here by the fact's id.
    fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + MaybeSend;

    /// Every stream of `domain` holding at least one page of its own, in
    /// every edition, in [`StreamRef`]'s order.
    fn covers(
        &self,
        domain: &str,
    ) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + MaybeSend;

    /// The store's commit position now: global, monotonic, rising with
    /// every commit that appends an event, through any handle, never
    /// falling. An edition diverges at the commit position of its create.
    fn commit_position(&self) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;
}

/// The newest snapshot per stream: whatever was written last. Whether it
/// may be used is the caller's to judge, never the store's.
pub trait SnapshotStore: MaybeSend + MaybeSync {
    fn read_snapshot(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + MaybeSend;

    fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend;
}

/// Where each handler is on each stream: the next sequence it has yet to
/// handle, 0 until put. A plain upsert, which may lower it.
pub trait PositionStore: MaybeSend + MaybeSync {
    fn position(
        &self,
        key: PositionKey<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;

    fn put_position(
        &self,
        key: PositionKey<'_>,
        next: u64,
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend;
}

/// A store that opens units of work.
///
/// Two units may be open on one handle. A backend that cannot serve a
/// second at once (one SQLite connection) refuses the second begin with
/// [`StoreError::UnitBusy`] and never waits for it: a begin either serves
/// or refuses.
pub trait UnitOfWork: MaybeSend + MaybeSync {
    type Unit<'s>: Unit + 's
    where
        Self: 's;

    fn begin(&self) -> impl Future<Output = Result<Self::Unit<'_>, StoreError>> + MaybeSend;
}

/// One open unit of work: its reads see its writes; nothing is seen
/// outside before [`commit`](Unit::commit); dropped or aborted, nothing
/// lands. A race lost to another handle is [`StoreError::Conflict`], at the
/// unit's append or at its commit.
pub trait Unit: MaybeSend {
    fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;

    fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + MaybeSend;

    fn head(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Head, StoreError>> + MaybeSend {
        async move { Ok(self.read(stream, u64::MAX, None).await?.head()) }
    }

    fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + MaybeSend;

    fn covers(
        &mut self,
        domain: &str,
    ) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + MaybeSend;

    /// Snapshots are read in a unit, never written: a cache is no part of
    /// a commit.
    fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + MaybeSend;

    fn position(
        &mut self,
        key: PositionKey<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;

    /// Lands at commit with the unit's appends: 5.6's checkpoint.
    fn put_position(
        &mut self,
        key: PositionKey<'_>,
        next: u64,
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend;

    fn commit(self) -> impl Future<Output = Result<(), StoreError>> + MaybeSend
    where
        Self: Sized;

    fn abort(self) -> impl Future<Output = Result<(), StoreError>> + MaybeSend
    where
        Self: Sized;
}

/// Every base port at once.
pub trait Store: EventStore + SnapshotStore + PositionStore + UnitOfWork {}

impl<T: EventStore + SnapshotStore + PositionStore + UnitOfWork + ?Sized> Store for T {}

// ================================================================== purge

/// Opt-in: delete a stream, its snapshot, its command ids and every
/// handler's position on it. It restarts at 0.
pub trait Purge: MaybeSend + MaybeSync {
    fn purge(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;
}

/// [`Purge`] in a unit: lands at commit, seen by the unit at once.
pub trait UnitPurge: Unit {
    fn purge(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;
}

// =============================================================== editions

/// The store an edition created with none named is placed in.
pub const DEFAULT_EDITION_STORE: &str = "default";

/// Opt-in: the edition registry (EA-1), and with it EA-3's fall-through
/// on every read of [`EventStore`].
pub trait Editions: MaybeSend + MaybeSync {
    /// Create the edition `request` names at `now`. It diverges at the
    /// store's commit position at the create: main's events committed
    /// before it are its history. HOW that position is recorded is pending
    /// the human (edition creation is to be the edition's first event;
    /// where that event lives is OPEN(C)). Refused: an empty name, a
    /// `diverge_at` after `now`, a name already created, an unknown store.
    fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> impl Future<Output = Result<Edition, StoreError>> + MaybeSend;

    /// Delete the edition, its record and everything stored under it in
    /// every domain. Main is never touched.
    fn delete_edition(
        &self,
        name: &str,
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend;

    fn edition(
        &self,
        name: &str,
    ) -> impl Future<Output = Result<Option<Edition>, StoreError>> + MaybeSend;
}

// ========================================================== one-moment reads

/// Opt-in: read-only units whose reads all see one moment (annals'
/// `ReadStore`). A read unit refuses a stream in an edition never created
/// ([`StoreError::UnknownEdition`], EA-2) and lists none.
pub trait ReadStore: MaybeSend + MaybeSync {
    type Reads<'s>: ReadUnit + 's
    where
        Self: 's;

    fn begin_read(&self) -> impl Future<Output = Result<Self::Reads<'_>, StoreError>> + MaybeSend;
}

/// A read-only unit: the store as it stood when it began. Ends when dropped.
/// Every read through it respects editions as the store does: a created
/// edition's stream falls through to main below its divergence (EA-3),
/// except its snapshot, which never does (ruling B); an edition never
/// created is refused ([`StoreError::UnknownEdition`]).
pub trait ReadUnit: MaybeSend {
    fn covers(
        &mut self,
        domain: &str,
    ) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + MaybeSend;

    fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + MaybeSend;

    /// The stream's head at the unit's moment: by default a read past the
    /// end.
    fn head(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Head, StoreError>> + MaybeSend {
        async move { Ok(self.read(stream, u64::MAX, None).await?.head()) }
    }

    /// The stream's own snapshot at the unit's moment, never main's.
    fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + MaybeSend;
}

// ================================================================== watch

/// What [`Watch::change_token`] answers: equal tokens from one handle mean
/// nothing was committed between. Opaque; compared only for equality.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct ChangeToken([u64; 2]);

impl ChangeToken {
    pub const fn new(parts: [u64; 2]) -> ChangeToken {
        ChangeToken(parts)
    }
}

/// Opt-in: a cheap "anything committed?", through any handle.
pub trait Watch: MaybeSend + MaybeSync {
    fn change_token(&self) -> impl Future<Output = Result<ChangeToken, StoreError>> + MaybeSend;
}

// ============================================================ core's reads

/// Opt-in: a stream as of a time.
pub trait ReadUntilTime: MaybeSend + MaybeSync {
    /// The pages recorded at or before `until` (a prefix: `recorded_at`
    /// never falls along a stream), with the stream's head as read.
    fn read_until_time(
        &self,
        stream: StreamRef<'_>,
        until: &Timestamp,
    ) -> impl Future<Output = Result<Slice, StoreError>> + MaybeSend;
}

/// Opt-in: everything one correlation wrote.
pub trait ReadByCorrelation: MaybeSend + MaybeSync {
    /// One book per stream holding pages of `correlation_id`, those pages
    /// only, in [`StreamRef`] order; limited to `domain` when given. The
    /// timeline is `edition` (`None`: main), read as [`EventStore::read`]
    /// reads it.
    fn read_by_correlation(
        &self,
        domain: Option<&str>,
        edition: Option<&str>,
        correlation_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventBook>, StoreError>> + MaybeSend;
}

/// Opt-in: every stream of every domain. REQUIRED of any backend serving
/// angzarr's `QueryService`, whose `GetAggregateRoots` lists every stream
/// across all domains. Not folded into [`EventStore::covers`]: that needs a
/// domain, and the base contract has no list of domains. It answers exactly
/// `covers(d)` over every domain `d` holding a stream, in domain order.
pub trait ListStreams: MaybeSend + MaybeSync {
    fn list_streams(&self) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + MaybeSend;
}

// ================================================================= outbox

/// One message a component sends beyond its own stream (a saga's command,
/// today), kept until the relay has delivered it. Kind-agnostic: the store
/// never decodes `message`, and `origin` is just the writer's name.
#[derive(Clone, PartialEq, Debug)]
pub struct OutboxEntry {
    /// The receiver's dedup key (a command's id): delivery is at least
    /// once, so the receiver drops what it has seen.
    pub id: Uuid,
    /// The handler that wrote it (as in its [`PositionKey`]).
    pub origin: String,
    /// The message, opaque: a `CommandBook` today.
    pub message: Any,
}

/// Opt-in: the transactional outbox (5.6, OB-1, 14.31), the relay's side.
/// Entries are written only through a unit ([`UnitOutbox`]), atomically
/// with its appends and positions; the relay reads what is pending,
/// delivers it, then clears it.
pub trait Outbox: MaybeSend + MaybeSync {
    /// Up to `limit` pending entries, oldest commit first. Reading clears
    /// nothing: an entry is pending until cleared.
    fn pending(
        &self,
        limit: usize,
    ) -> impl Future<Output = Result<Vec<OutboxEntry>, StoreError>> + MaybeSend;

    /// Clear delivered entries by id. An id not pending is no error (a
    /// relay may clear twice). Returns how many were cleared.
    fn clear(&self, ids: &[Uuid]) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend;
}

/// [`Outbox`] in a unit: the writer's side.
pub trait UnitOutbox: Unit {
    /// Keep `entries`, landing at commit. An id already pending keeps its
    /// first message, verbatim.
    fn put_outbox(
        &mut self,
        entries: &[OutboxEntry],
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend;
}

// ========================================== shared handles: Arc<T> (base)

impl<T: EventStore + ?Sized> EventStore for Arc<T> {
    fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend {
        (**self).append(stream, expected, pages)
    }
    fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + MaybeSend {
        (**self).read(stream, from, to)
    }
    fn head(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Head, StoreError>> + MaybeSend {
        (**self).head(stream)
    }
    fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + MaybeSend {
        (**self).find_command(stream, command_id)
    }
    fn covers(
        &self,
        domain: &str,
    ) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + MaybeSend {
        (**self).covers(domain)
    }
    fn commit_position(&self) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend {
        (**self).commit_position()
    }
}

impl<T: SnapshotStore + ?Sized> SnapshotStore for Arc<T> {
    fn read_snapshot(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + MaybeSend {
        (**self).read_snapshot(stream)
    }
    fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend {
        (**self).write_snapshot(stream, snapshot)
    }
}

impl<T: PositionStore + ?Sized> PositionStore for Arc<T> {
    fn position(
        &self,
        key: PositionKey<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + MaybeSend {
        (**self).position(key)
    }
    fn put_position(
        &self,
        key: PositionKey<'_>,
        next: u64,
    ) -> impl Future<Output = Result<(), StoreError>> + MaybeSend {
        (**self).put_position(key, next)
    }
}

impl<T: UnitOfWork + ?Sized> UnitOfWork for Arc<T> {
    type Unit<'s>
        = T::Unit<'s>
    where
        Self: 's;
    fn begin(&self) -> impl Future<Output = Result<Self::Unit<'_>, StoreError>> + MaybeSend {
        (**self).begin()
    }
}
