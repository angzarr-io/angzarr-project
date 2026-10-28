//! A real backend in memory: every port and every opt-in capability, held
//! to every section of the conformance suite (ruling 13). Not a test toy:
//! tests, games and anything else that needs no durability use it as their
//! store. It keeps nothing past the process.
//!
//! `MemoryStore` is a handle: clones share one store (so two handles are
//! two clones), and every operation is atomic under one lock. It serves any
//! number of units at once: a unit holds its writes and checks them at
//! commit, so a race is refused there.
//!
//! **A proposal.** Every operation is `todo!()` until the ports are
//! approved; the suite run against it (`tests/contract.rs`) is what it must
//! then pass.

use std::sync::{Arc, Mutex};

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::{Cover, CreateEditionRequest, Edition, EventBook, EventPage, Snapshot};
use prost_types::Timestamp;

use crate::error::StoreError;
use crate::store::{
    ChangeToken, Editions, EventStore, ListStreams, Outbox, OutboxEntry, PositionStore, Purge,
    ReadByCorrelation, ReadStore, ReadUnit, ReadUntilTime, SnapshotStore, Unit, UnitOfWork,
    UnitOutbox, UnitPurge, Watch,
};
use crate::stream::{PositionKey, Slice, StreamRef};

const STUB: &str = "MemoryStore is a proposal: implemented once the ports are approved";

/// Everything every handle shares. Empty until implemented.
#[derive(Default)]
struct State {}

/// The in-memory store. See the module.
#[derive(Clone, Default)]
pub struct MemoryStore {
    #[allow(dead_code)] // read once implemented
    state: Arc<Mutex<State>>,
}

impl MemoryStore {
    /// A new, empty store.
    pub fn new() -> MemoryStore {
        MemoryStore::default()
    }
}

/// A unit of work on a [`MemoryStore`]: its pending writes, checked and
/// applied at commit. Owns a handle, so it borrows nothing.
pub struct MemoryUnit {
    #[allow(dead_code)] // read once implemented
    store: MemoryStore,
}

/// A read-only unit on a [`MemoryStore`]: the store as it stood at begin.
pub struct MemoryRead {
    #[allow(dead_code)] // read once implemented
    store: MemoryStore,
}

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

impl ReadStore for MemoryStore {
    type Reads<'s> = MemoryRead;
    async fn begin_read(&self) -> Result<MemoryRead, StoreError> {
        todo!("{STUB}")
    }
}

impl ReadUnit for MemoryRead {
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        let _ = domain;
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
}

impl Watch for MemoryStore {
    async fn change_token(&self) -> Result<ChangeToken, StoreError> {
        todo!("{STUB}")
    }
}

impl ReadUntilTime for MemoryStore {
    async fn read_until_time(
        &self,
        stream: StreamRef<'_>,
        until: &Timestamp,
    ) -> Result<Slice, StoreError> {
        let _ = (stream, until);
        todo!("{STUB}")
    }
}

impl ReadByCorrelation for MemoryStore {
    async fn read_by_correlation(
        &self,
        domain: Option<&str>,
        edition: Option<&str>,
        correlation_id: Uuid,
    ) -> Result<Vec<EventBook>, StoreError> {
        let _ = (domain, edition, correlation_id);
        todo!("{STUB}")
    }
}

impl ListStreams for MemoryStore {
    async fn list_streams(&self) -> Result<Vec<Cover>, StoreError> {
        todo!("{STUB}")
    }
}

impl Outbox for MemoryStore {
    async fn pending(&self, limit: usize) -> Result<Vec<OutboxEntry>, StoreError> {
        let _ = limit;
        todo!("{STUB}")
    }
    async fn clear(&self, ids: &[Uuid]) -> Result<u64, StoreError> {
        let _ = ids;
        todo!("{STUB}")
    }
}

impl UnitOutbox for MemoryUnit {
    async fn put_outbox(&mut self, entries: &[OutboxEntry]) -> Result<(), StoreError> {
        let _ = entries;
        todo!("{STUB}")
    }
}
