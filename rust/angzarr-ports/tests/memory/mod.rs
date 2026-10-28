//! The reference backend the suite is written against: streams in memory.
//!
//! **Stubbed.** Every operation is `todo!()`, so each contract test is red
//! because the reference backend does not yet do what the check asks, and
//! for no other reason. Once the signatures are approved this becomes a
//! real store (a candidate for the crate itself, behind a `memory` feature:
//! OPEN(13) in `contract.rs`).
//!
//! `MemoryStore` is a handle: clones share one store, which is how the
//! `pair` section gets two handles on it.

#![allow(dead_code)]

use std::sync::{Arc, Mutex};

use angzarr_ports::angzarr_proto::v1::{
    Cover, CreateEditionRequest, Edition, EventPage, EventRef, Snapshot,
};
use angzarr_ports::{
    Editions, EventStore, PositionKey, PositionStore, Purge, Slice, SnapshotStore, StoreError,
    StreamRef, Unit, UnitOfWork, UnitPurge, Uuid,
};
use prost_types::Timestamp;

/// What every handle shares. Empty until the store is written.
#[derive(Default)]
struct State {}

#[derive(Clone, Default)]
pub struct MemoryStore {
    state: Arc<Mutex<State>>,
}

impl MemoryStore {
    pub fn new() -> MemoryStore {
        MemoryStore::default()
    }

    /// Two handles on one fresh store.
    pub fn pair() -> (MemoryStore, MemoryStore) {
        let a = MemoryStore::new();
        (a.clone(), a)
    }
}

/// A unit of work: its pending writes, applied at commit. Owns a handle, so
/// it borrows nothing.
pub struct MemoryUnit {
    store: MemoryStore,
}

const STUB: &str = "the reference MemoryStore is stubbed until the signatures are approved";

impl EventStore for MemoryStore {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        let _ = (stream, expected, pages);
        todo!("{STUB}")
    }

    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        let _ = (stream, from, to);
        todo!("{STUB}")
    }

    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        let _ = (stream, command_id);
        todo!("{STUB}")
    }

    async fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        let _ = (stream, trigger);
        todo!("{STUB}")
    }

    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        let _ = domain;
        todo!("{STUB}")
    }

    async fn commit_position(&self) -> Result<u64, StoreError> {
        todo!("{STUB}")
    }
}

impl SnapshotStore for MemoryStore {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        let _ = stream;
        todo!("{STUB}")
    }

    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        let _ = (stream, snapshot);
        todo!("{STUB}")
    }
}

impl PositionStore for MemoryStore {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        let _ = key;
        todo!("{STUB}")
    }

    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        let _ = (key, next);
        todo!("{STUB}")
    }
}

impl UnitOfWork for MemoryStore {
    type Unit<'s> = MemoryUnit;

    async fn begin(&self) -> Result<MemoryUnit, StoreError> {
        todo!("{STUB}")
    }
}

impl Unit for MemoryUnit {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        let _ = (stream, expected, pages);
        todo!("{STUB}")
    }

    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        let _ = (stream, from, to);
        todo!("{STUB}")
    }

    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        let _ = (stream, command_id);
        todo!("{STUB}")
    }

    async fn find_triggered(
        &mut self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        let _ = (stream, trigger);
        todo!("{STUB}")
    }

    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        let _ = domain;
        todo!("{STUB}")
    }

    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        let _ = stream;
        todo!("{STUB}")
    }

    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        let _ = key;
        todo!("{STUB}")
    }

    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        let _ = (key, next);
        todo!("{STUB}")
    }

    async fn commit(self) -> Result<(), StoreError> {
        todo!("{STUB}")
    }

    async fn abort(self) -> Result<(), StoreError> {
        todo!("{STUB}")
    }
}

impl Purge for MemoryStore {
    async fn purge(&self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        let _ = stream;
        todo!("{STUB}")
    }
}

impl UnitPurge for MemoryUnit {
    async fn purge(&mut self, stream: StreamRef<'_>) -> Result<u64, StoreError> {
        let _ = stream;
        todo!("{STUB}")
    }
}

impl Editions for MemoryStore {
    async fn create_edition(
        &self,
        request: &CreateEditionRequest,
        now: Timestamp,
    ) -> Result<Edition, StoreError> {
        let _ = (request, now);
        todo!("{STUB}")
    }

    async fn delete_edition(&self, name: &str) -> Result<(), StoreError> {
        let _ = name;
        todo!("{STUB}")
    }

    async fn edition(&self, name: &str) -> Result<Option<Edition>, StoreError> {
        let _ = name;
        todo!("{STUB}")
    }
}
