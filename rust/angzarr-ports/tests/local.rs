//! The local ports: a single-threaded backend, whose futures are not
//! `Send` (a browser's IndexedDB), runs the same suite (OPEN(12) in
//! contract.rs).
//!
//! `LocalOnly` stands for such a backend: it holds an `Rc`, so it is not
//! `Send` and cannot implement the root ports, and implements the local
//! ones by delegating to the reference store. Red because the reference
//! store is stubbed.

#[cfg(not(feature = "contract"))]
compile_error!("the suite is behind the `contract` feature: run `just test`");

mod memory;

use std::rc::Rc;

use angzarr_ports::angzarr_proto::v1::{Cover, EventPage, EventRef, Snapshot};
use angzarr_ports::local::{
    LocalEventStore, LocalPositionStore, LocalSnapshotStore, LocalUnit, LocalUnitOfWork,
};
use angzarr_ports::{
    EventStore, PositionKey, PositionStore, Slice, SnapshotStore, StoreError, StreamRef, Unit,
    UnitOfWork, Uuid,
};
use memory::{MemoryStore, MemoryUnit};

/// A single-threaded store: not `Send`, by the `Rc`.
struct LocalOnly {
    inner: Rc<MemoryStore>,
}

/// Its unit, not `Send` either.
struct LocalOnlyUnit {
    inner: MemoryUnit,
    _not_send: Rc<()>,
}

impl LocalOnly {
    fn new() -> LocalOnly {
        LocalOnly {
            inner: Rc::new(MemoryStore::new()),
        }
    }
}

impl LocalEventStore for LocalOnly {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        EventStore::append(&*self.inner, stream, expected, pages).await
    }
    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        EventStore::read(&*self.inner, stream, from, to).await
    }
    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        EventStore::find_command(&*self.inner, stream, command_id).await
    }
    async fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        EventStore::find_triggered(&*self.inner, stream, trigger).await
    }
    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        EventStore::covers(&*self.inner, domain).await
    }
    async fn commit_position(&self) -> Result<u64, StoreError> {
        EventStore::commit_position(&*self.inner).await
    }
}

impl LocalSnapshotStore for LocalOnly {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        SnapshotStore::read_snapshot(&*self.inner, stream).await
    }
    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        SnapshotStore::write_snapshot(&*self.inner, stream, snapshot).await
    }
}

impl LocalPositionStore for LocalOnly {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        PositionStore::position(&*self.inner, key).await
    }
    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        PositionStore::put_position(&*self.inner, key, next).await
    }
}

impl LocalUnitOfWork for LocalOnly {
    type Unit<'s> = LocalOnlyUnit;
    async fn begin(&self) -> Result<LocalOnlyUnit, StoreError> {
        Ok(LocalOnlyUnit {
            inner: UnitOfWork::begin(&*self.inner).await?,
            _not_send: Rc::new(()),
        })
    }
}

impl LocalUnit for LocalOnlyUnit {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        Unit::append(&mut self.inner, stream, expected, pages).await
    }
    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        Unit::read(&mut self.inner, stream, from, to).await
    }
    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        Unit::find_command(&mut self.inner, stream, command_id).await
    }
    async fn find_triggered(
        &mut self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        Unit::find_triggered(&mut self.inner, stream, trigger).await
    }
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        Unit::covers(&mut self.inner, domain).await
    }
    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        Unit::read_snapshot(&mut self.inner, stream).await
    }
    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        Unit::position(&mut self.inner, key).await
    }
    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        Unit::put_position(&mut self.inner, key, next).await
    }
    async fn commit(self) -> Result<(), StoreError> {
        Unit::commit(self.inner).await
    }
    async fn abort(self) -> Result<(), StoreError> {
        Unit::abort(self.inner).await
    }
}

/// The base section on a store that is not `Send`, under a current-thread
/// test runtime, which never asks for `Send`.
mod base_on_a_local_store {
    use super::*;
    angzarr_ports::store_contract!(#[tokio::test], LocalOnly::new());
}
