//! The same ports, with futures that need not be `Send`: for a backend on
//! one thread (a browser's IndexedDB under `wasm32-unknown-unknown`), and
//! for code that must run on either kind (the conformance suite).
//!
//! Each `Local*` port has exactly its `Send` twin's methods and contract.
//! Every `Send` port implements its local twin by a blanket impl here, and
//! that impl delegating method for method is what keeps the two from
//! drifting: a signature changed on one side and not the other stops this
//! module compiling.
//!
//! A backend implements one set, never both: a `Send` backend the root
//! ports (and gets these free), a single-threaded one these. Generic code
//! that needs `Send` futures (a server spawning a handler) is written over
//! the root ports; code that never spawns is written over these and runs on
//! both.
//!
//! When return-type notation (`S::append(..): Send`) is stable, the two sets
//! collapse into one, with `Send` asked for by the code that needs it.

// The point of this module: futures with no `Send` bound.
#![allow(async_fn_in_trait)]

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::{Cover, CreateEditionRequest, Edition, EventPage, EventRef, Snapshot};
use prost_types::Timestamp;

use crate::error::StoreError;
use crate::store::{
    Editions, EventStore, PositionStore, Purge, SnapshotStore, Unit, UnitOfWork, UnitPurge,
};
use crate::stream::{Head, PositionKey, Slice, StreamRef};

/// [`EventStore`], futures not `Send`.
pub trait LocalEventStore {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError>;
    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError>;
    async fn head(&self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        Ok(self.read(stream, u64::MAX, None).await?.head())
    }
    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError>;
    async fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError>;
    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError>;
    async fn commit_position(&self) -> Result<u64, StoreError>;
}

/// [`SnapshotStore`], futures not `Send`.
pub trait LocalSnapshotStore {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError>;
    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError>;
}

/// [`PositionStore`], futures not `Send`.
pub trait LocalPositionStore {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError>;
    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError>;
}

/// [`UnitOfWork`], futures not `Send`.
pub trait LocalUnitOfWork {
    type Unit<'s>: LocalUnit + 's
    where
        Self: 's;
    async fn begin(&self) -> Result<Self::Unit<'_>, StoreError>;
}

/// [`Unit`], futures not `Send`.
pub trait LocalUnit {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError>;
    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError>;
    async fn head(&mut self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        Ok(self.read(stream, u64::MAX, None).await?.head())
    }
    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError>;
    async fn find_triggered(
        &mut self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError>;
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError>;
    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError>;
    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError>;
    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError>;
    async fn commit(self) -> Result<(), StoreError>
    where
        Self: Sized;
    async fn abort(self) -> Result<(), StoreError>
    where
        Self: Sized;
}

/// [`Purge`], futures not `Send`.
pub trait LocalPurge {
    async fn purge(&self, stream: StreamRef<'_>) -> Result<u64, StoreError>;
}

/// [`UnitPurge`], futures not `Send`.
pub trait LocalUnitPurge: LocalUnit {
    async fn purge(&mut self, stream: StreamRef<'_>) -> Result<u64, StoreError>;
}

/// [`Editions`], futures not `Send`.
pub trait LocalEditions {
    async fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> Result<Edition, StoreError>;
    async fn delete_edition(&self, name: &str) -> Result<(), StoreError>;
    async fn edition(&self, name: &str) -> Result<Option<Edition>, StoreError>;
}

/// [`Store`](crate::Store), futures not `Send`: what the suite's base
/// section runs against.
pub trait LocalStore:
    LocalEventStore + LocalSnapshotStore + LocalPositionStore + LocalUnitOfWork
{
}

impl<T: LocalEventStore + LocalSnapshotStore + LocalPositionStore + LocalUnitOfWork + ?Sized>
    LocalStore for T
{
}

// --------------------------------------- every Send port is its local twin

impl<T: EventStore + ?Sized> LocalEventStore for T {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        EventStore::append(self, stream, expected, pages).await
    }
    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        EventStore::read(self, stream, from, to).await
    }
    async fn head(&self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        EventStore::head(self, stream).await
    }
    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        EventStore::find_command(self, stream, command_id).await
    }
    async fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        EventStore::find_triggered(self, stream, trigger).await
    }
    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        EventStore::covers(self, domain).await
    }
    async fn commit_position(&self) -> Result<u64, StoreError> {
        EventStore::commit_position(self).await
    }
}

impl<T: SnapshotStore + ?Sized> LocalSnapshotStore for T {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        SnapshotStore::read_snapshot(self, stream).await
    }
    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        SnapshotStore::write_snapshot(self, stream, snapshot).await
    }
}

impl<T: PositionStore + ?Sized> LocalPositionStore for T {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        PositionStore::position(self, key).await
    }
    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        PositionStore::put_position(self, key, next).await
    }
}

impl<T: UnitOfWork + ?Sized> LocalUnitOfWork for T {
    type Unit<'s>
        = T::Unit<'s>
    where
        Self: 's;
    async fn begin(&self) -> Result<Self::Unit<'_>, StoreError> {
        UnitOfWork::begin(self).await
    }
}

impl<U: Unit> LocalUnit for U {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        Unit::append(self, stream, expected, pages).await
    }
    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        Unit::read(self, stream, from, to).await
    }
    async fn head(&mut self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        Unit::head(self, stream).await
    }
    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        Unit::find_command(self, stream, command_id).await
    }
    async fn find_triggered(
        &mut self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        Unit::find_triggered(self, stream, trigger).await
    }
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        Unit::covers(self, domain).await
    }
    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        Unit::read_snapshot(self, stream).await
    }
    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        Unit::position(self, key).await
    }
    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        Unit::put_position(self, key, next).await
    }
    async fn commit(self) -> Result<(), StoreError> {
        Unit::commit(self).await
    }
    async fn abort(self) -> Result<(), StoreError> {
        Unit::abort(self).await
    }
}

impl<T: Purge + ?Sized> LocalPurge for T {
    async fn purge(&self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        Purge::purge(self, stream).await
    }
}

impl<U: UnitPurge> LocalUnitPurge for U {
    async fn purge(&mut self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        UnitPurge::purge(self, stream).await
    }
}

impl<T: Editions + ?Sized> LocalEditions for T {
    async fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> Result<Edition, StoreError> {
        Editions::create_edition(self, request, now).await
    }
    async fn delete_edition(&self, name: &str) -> Result<(), StoreError> {
        Editions::delete_edition(self, name).await
    }
    async fn edition(&self, name: &str) -> Result<Option<Edition>, StoreError> {
        Editions::edition(self, name).await
    }
}
