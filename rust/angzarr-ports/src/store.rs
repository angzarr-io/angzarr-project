//! The ports, with `Send` futures: what a server's backends implement.
//!
//! Every method returns `impl Future + Send`; a backend writes it as a plain
//! `async fn`, and the compiler checks its future is `Send`. Stores are
//! `Send + Sync` and take `&self`, so one handle is shared (`Arc`, core's
//! wiring) and a store does its own locking; a [`Unit`] takes `&mut self`,
//! because a transaction is exclusive and `&self` would force interior
//! locking on every call.
//!
//! The same ports with futures that need not be `Send` are in
//! [`local`](crate::local); every port here is also its local twin.

use std::future::Future;
use std::sync::Arc;

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::{Cover, CreateEditionRequest, Edition, EventPage, EventRef, Snapshot};
use prost_types::Timestamp;

use crate::error::StoreError;
use crate::stream::{Head, PositionKey, Slice, StreamRef};

/// Where streams are kept: one append-only log of opaque pages per stream.
///
/// **Opaque.** A store keeps each [`EventPage`] as written (payload `Any`,
/// `EventMeta`, sequence) and copies what it indexes into columns. It never
/// decodes a payload, never assigns or rewrites a sequence, and nothing is
/// rewritten: upcasting is the reader's, on every read.
pub trait EventStore: Send + Sync {
    /// Append `pages` to `stream` as one autocommitted write, creating the
    /// stream when `expected` is 0 and it holds nothing. Refused, appending
    /// nothing: a stream not at `expected` ([`StoreError::Conflict`]); pages
    /// whose sequences do not run on from `expected`
    /// ([`StoreError::Discontinuous`]). No pages checks `expected` and
    /// writes nothing. Returns the stream's new length.
    ///
    /// Core, whose pages arrive stamped, passes `pages[0].sequence`: its
    /// "the first page must be the head" rule, stated as the argument.
    fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> impl Future<Output = Result<u64, StoreError>> + Send;

    /// The pages with `from <= sequence < to` (`to` `None`: to the end), in
    /// sequence order, with the stream's head as read. An absent stream is
    /// an empty slice at 0; a range past the end is empty but knows the end.
    fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + Send;

    /// The stream's head. By default a read past the end; a backend with a
    /// cheaper query overrides it, and the suite holds both to one answer.
    fn head(&self, stream: StreamRef<'_>) -> impl Future<Output = Result<Head, StoreError>> + Send {
        async move { Ok(self.read(stream, u64::MAX, None).await?.head()) }
    }

    /// The pages of `stream` whose `EventMeta.causation` is the command
    /// `command_id`, in sequence order: the dedup lookup, over a non-unique
    /// index on (stream, command id). Empty when the command never applied
    /// there, or applied and produced nothing.
    fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + Send;

    /// The pages of `stream` whose `EventMeta.causation` is the triggering
    /// event `trigger`, in sequence order: a process manager's dedup lookup
    /// (spec 13.2), over an index on (stream, trigger). Required of every
    /// backend: a default "none found" would be a silent dedup hole.
    fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + Send;

    /// Every stream of `domain` holding at least one page, in every edition,
    /// in [`StreamRef`]'s order: main first, then each edition by name, each
    /// by root. What a projector enumerates to catch a domain up.
    fn covers(&self, domain: &str) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + Send;

    /// The store's commit position now: one for the whole store (every
    /// stream, every handle on its database) and monotonic. It rises with
    /// every commit that appends an event, through any handle, and never
    /// falls, a purge included. Commit order, not `recorded_at`. What an
    /// edition's create records as its divergence (EA-3).
    fn commit_position(&self) -> impl Future<Output = Result<u64, StoreError>> + Send;
}

/// The newest snapshot per stream: a framework cache, never business data.
/// The store keeps whatever was written last; whether it may be USED (its
/// state type, its `rules_version`) is the caller's to judge (RV-3), never
/// the store's.
pub trait SnapshotStore: Send + Sync {
    /// The snapshot last written for `stream`, if any.
    fn read_snapshot(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + Send;

    /// Keep `snapshot` as `stream`'s newest, replacing the one before.
    fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;
}

/// Where each handler is on each stream it consumes: the sequence of the
/// next event it has yet to handle, so 0 until it has handled one.
pub trait PositionStore: Send + Sync {
    /// The handler's next sequence on the stream: 0 if never put.
    fn position(
        &self,
        key: PositionKey<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + Send;

    /// Set the handler's next sequence on the stream, whatever it was: a
    /// reset for recovery may lower it. Keeping it monotonic in normal
    /// running is the dispatcher's job.
    fn put_position(
        &self,
        key: PositionKey<'_>,
        next: u64,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;
}

/// A store that opens units of work: transactions over several streams and
/// positions, landing together at [`Unit::commit`] or not at all.
pub trait UnitOfWork: Send + Sync {
    /// The store's transaction. It may borrow the store (a connection held
    /// for its life).
    type Unit<'s>: Unit + 's
    where
        Self: 's;

    /// Begin a unit. A failure to begin is answered here, not deferred to
    /// the unit's first operation.
    fn begin(&self) -> impl Future<Output = Result<Self::Unit<'_>, StoreError>> + Send;
}

/// One open unit of work. Its reads see its own writes; nothing it writes is
/// seen outside it before [`commit`](Unit::commit). Dropped uncommitted, or
/// [`abort`](Unit::abort)ed, nothing it wrote lands.
pub trait Unit: Send {
    /// As [`EventStore::append`], landing at commit. Checked against the
    /// stream as this unit sees it, its own pending appends included.
    fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> impl Future<Output = Result<u64, StoreError>> + Send;

    /// As [`EventStore::read`], seeing this unit's appends.
    fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + Send;

    /// As [`EventStore::head`], seeing this unit's appends.
    fn head(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Head, StoreError>> + Send {
        async move { Ok(self.read(stream, u64::MAX, None).await?.head()) }
    }

    /// As [`EventStore::find_command`], seeing this unit's appends.
    fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + Send;

    /// As [`EventStore::find_triggered`], seeing this unit's appends.
    fn find_triggered(
        &mut self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + Send;

    /// As [`EventStore::covers`], with this unit's new streams.
    fn covers(
        &mut self,
        domain: &str,
    ) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + Send;

    /// As [`SnapshotStore::read_snapshot`]. Snapshots are written outside
    /// units: a cache, never part of what commits.
    fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + Send;

    /// As [`PositionStore::position`], seeing this unit's puts.
    fn position(
        &mut self,
        key: PositionKey<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + Send;

    /// As [`PositionStore::put_position`], landing at commit with the
    /// unit's appends: spec 5.6's checkpoint, atomic with the output.
    fn put_position(
        &mut self,
        key: PositionKey<'_>,
        next: u64,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;

    /// Land everything at once. A conflict found only now (another handle
    /// appended first) is [`StoreError::Conflict`], and nothing lands.
    fn commit(self) -> impl Future<Output = Result<(), StoreError>> + Send
    where
        Self: Sized;

    /// Land nothing, and say so: dropping does the same, silently.
    fn abort(self) -> impl Future<Output = Result<(), StoreError>> + Send
    where
        Self: Sized;
}

/// A store that can delete a stream: opt-in, so one that does not stays
/// append-only by type. A purge is the one deletion; it undoes dedup for the
/// stream (a command redelivered after is decided again).
pub trait Purge: Send + Sync {
    /// Delete `stream`'s events, its snapshot, its command ids and every
    /// handler's position on it, all at once or none. Afterwards the stream
    /// does not exist: it reads empty at 0, is in no `covers`, and an append
    /// starts again from 0. Returns how many events it deleted.
    fn purge(&self, stream: StreamRef<'_>) -> impl Future<Output = Result<u64, StoreError>> + Send;
}

/// [`Purge`] inside a unit: it lands at commit; the unit's reads see it at
/// once, and the unit may append to the stream again after.
pub trait UnitPurge: Unit {
    /// As [`Purge::purge`], including what this unit appended before.
    fn purge(
        &mut self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + Send;
}

/// The store an edition created with none named is placed in.
pub const DEFAULT_EDITION_STORE: &str = "default";

/// The edition registry (EA-1): opt-in. Administrative: no command, no
/// event, never replayed. Main is unnamed, always exists, and is neither
/// created nor deleted.
pub trait Editions: Send + Sync {
    /// Create the edition `request` names, at `now` (the caller's sampled
    /// instant): its divergence point `request.diverge_at`, or `now` when
    /// unset; its store [`DEFAULT_EDITION_STORE`] when none is named.
    /// Refused: an empty name, a divergence point after `now`, a name
    /// already created, a store not configured.
    fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> impl Future<Output = Result<Edition, StoreError>> + Send;

    /// Delete edition `name`: its record, and every event, snapshot and
    /// position under it in every domain. Main is never touched. Refused: an
    /// empty name, a name never created or already deleted.
    fn delete_edition(&self, name: &str) -> impl Future<Output = Result<(), StoreError>> + Send;

    /// The record of edition `name`, if created.
    fn edition(
        &self,
        name: &str,
    ) -> impl Future<Output = Result<Option<Edition>, StoreError>> + Send;
}

/// Every base port at once: what an application holds, and what the base
/// section of the suite runs against.
pub trait Store: EventStore + SnapshotStore + PositionStore + UnitOfWork {}

impl<T: EventStore + SnapshotStore + PositionStore + UnitOfWork + ?Sized> Store for T {}

// ------------------------------------------------- shared handles: Arc<T>
//
// A store behind an `Arc` is the store: core's wiring shares one handle,
// and `Arc<dyn DynStore>` is how the dyn adapter becomes a port again.

impl<T: EventStore + ?Sized> EventStore for Arc<T> {
    fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> impl Future<Output = Result<u64, StoreError>> + Send {
        (**self).append(stream, expected, pages)
    }

    fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> impl Future<Output = Result<Slice, StoreError>> + Send {
        (**self).read(stream, from, to)
    }

    fn head(&self, stream: StreamRef<'_>) -> impl Future<Output = Result<Head, StoreError>> + Send {
        (**self).head(stream)
    }

    fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + Send {
        (**self).find_command(stream, command_id)
    }

    fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> impl Future<Output = Result<Vec<EventPage>, StoreError>> + Send {
        (**self).find_triggered(stream, trigger)
    }

    fn covers(&self, domain: &str) -> impl Future<Output = Result<Vec<Cover>, StoreError>> + Send {
        (**self).covers(domain)
    }

    fn commit_position(&self) -> impl Future<Output = Result<u64, StoreError>> + Send {
        (**self).commit_position()
    }
}

impl<T: SnapshotStore + ?Sized> SnapshotStore for Arc<T> {
    fn read_snapshot(
        &self,
        stream: StreamRef<'_>,
    ) -> impl Future<Output = Result<Option<Snapshot>, StoreError>> + Send {
        (**self).read_snapshot(stream)
    }

    fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> impl Future<Output = Result<(), StoreError>> + Send {
        (**self).write_snapshot(stream, snapshot)
    }
}

impl<T: PositionStore + ?Sized> PositionStore for Arc<T> {
    fn position(
        &self,
        key: PositionKey<'_>,
    ) -> impl Future<Output = Result<u64, StoreError>> + Send {
        (**self).position(key)
    }

    fn put_position(
        &self,
        key: PositionKey<'_>,
        next: u64,
    ) -> impl Future<Output = Result<(), StoreError>> + Send {
        (**self).put_position(key, next)
    }
}

impl<T: UnitOfWork + ?Sized> UnitOfWork for Arc<T> {
    type Unit<'s>
        = T::Unit<'s>
    where
        Self: 's;

    fn begin(&self) -> impl Future<Output = Result<Self::Unit<'_>, StoreError>> + Send {
        (**self).begin()
    }
}

impl<T: Purge + ?Sized> Purge for Arc<T> {
    fn purge(&self, stream: StreamRef<'_>) -> impl Future<Output = Result<u64, StoreError>> + Send {
        (**self).purge(stream)
    }
}

impl<T: Editions + ?Sized> Editions for Arc<T> {
    fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> impl Future<Output = Result<Edition, StoreError>> + Send {
        (**self).create_edition(request, now)
    }

    fn delete_edition(&self, name: &str) -> impl Future<Output = Result<(), StoreError>> + Send {
        (**self).delete_edition(name)
    }

    fn edition(
        &self,
        name: &str,
    ) -> impl Future<Output = Result<Option<Edition>, StoreError>> + Send {
        (**self).edition(name)
    }
}
