//! On `wasm32` the ports ask no `Send` (RULED(12)): a browser backend whose
//! handles are not `Send` (IndexedDB's) implements the same one trait set
//! and runs the same suite.
//!
//! `RcStore` stands for such a backend: it holds an `Rc`, so neither it nor
//! its futures are `Send`; it delegates to `MemoryStore`. This file is
//! compiled only for `wasm32` (`just wasm` builds it); running it needs
//! `wasm-bindgen-test-runner` (OPEN(H)). Red, when run, because
//! `MemoryStore` is stubbed.

#![cfg(target_arch = "wasm32")]

use std::rc::Rc;

use angzarr_ports::angzarr_proto::v1::{Cover, EventPage, Snapshot};
use angzarr_ports::memory::{MemoryStore, MemoryUnit};
use angzarr_ports::{
    EventStore, PositionKey, PositionStore, Slice, SnapshotStore, StoreError, StreamRef, Unit,
    UnitOfWork, Uuid,
};
use wasm_bindgen_test::wasm_bindgen_test;

/// A store that is not `Send`, by its `Rc`.
struct RcStore(Rc<MemoryStore>);

/// Its unit, not `Send` either.
struct RcUnit(MemoryUnit, #[allow(dead_code)] Rc<()>);

impl EventStore for RcStore {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        self.0.append(stream, expected, pages).await
    }
    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        self.0.read(stream, from, to).await
    }
    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        self.0.find_command(stream, command_id).await
    }
    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        self.0.covers(domain).await
    }
    async fn commit_position(&self) -> Result<u64, StoreError> {
        self.0.commit_position().await
    }
}

impl SnapshotStore for RcStore {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        self.0.read_snapshot(stream).await
    }
    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        self.0.write_snapshot(stream, snapshot).await
    }
}

impl PositionStore for RcStore {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        self.0.position(key).await
    }
    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        self.0.put_position(key, next).await
    }
}

impl UnitOfWork for RcStore {
    type Unit<'s> = RcUnit;
    async fn begin(&self) -> Result<RcUnit, StoreError> {
        Ok(RcUnit(self.0.begin().await?, Rc::new(())))
    }
}

impl Unit for RcUnit {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        self.0.append(stream, expected, pages).await
    }
    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        self.0.read(stream, from, to).await
    }
    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        self.0.find_command(stream, command_id).await
    }
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        self.0.covers(domain).await
    }
    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        self.0.read_snapshot(stream).await
    }
    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        self.0.position(key).await
    }
    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        self.0.put_position(key, next).await
    }
    async fn commit(self) -> Result<(), StoreError> {
        self.0.commit().await
    }
    async fn abort(self) -> Result<(), StoreError> {
        self.0.abort().await
    }
}

/// The base section on a store that is not `Send`.
mod base_on_a_store_that_is_not_send {
    use super::*;
    angzarr_ports::store_contract!(
        #[wasm_bindgen_test],
        RcStore(Rc::new(MemoryStore::new()))
    );
}
