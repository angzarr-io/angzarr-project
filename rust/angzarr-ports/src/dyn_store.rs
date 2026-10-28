//! The dyn adapter: the ports as object-safe traits whose futures are
//! boxed, for core's `Arc<dyn …>` wiring.
//!
//! Native async traits are not object-safe, so each port has a `Dyn` twin
//! returning [`BoxFuture`]. Every `Send` backend implements its `Dyn` twins
//! by blanket impls here, and `dyn DynStore` implements the ports again, so
//! `Arc<dyn DynStore>` is a [`Store`](crate::Store) and generic code (the
//! suite included) runs on it unchanged. The cost is one allocation and one
//! indirect call per operation (about 7 ns, against a 2 µs SQLite read);
//! annals stays generic and pays nothing.
//!
//! `Send` backends only: core is a server. A single-threaded backend has no
//! dyn adapter.

use std::future::Future;
use std::pin::Pin;

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::{Cover, CreateEditionRequest, Edition, EventPage, EventRef, Snapshot};
use prost_types::Timestamp;

use crate::error::StoreError;
use crate::store::{Editions, EventStore, PositionStore, SnapshotStore, Unit, UnitOfWork};
use crate::stream::{Head, PositionKey, Slice, StreamRef};

/// A boxed `Send` future: what every `Dyn` method returns.
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// [`EventStore`], object-safe.
pub trait DynEventStore: Send + Sync {
    fn append<'a>(
        &'a self,
        stream: StreamRef<'a>,
        expected: u64,
        pages: &'a [EventPage],
    ) -> BoxFuture<'a, Result<u64, StoreError>>;
    fn read<'a>(
        &'a self,
        stream: StreamRef<'a>,
        from: u64,
        to: Option<u64>,
    ) -> BoxFuture<'a, Result<Slice, StoreError>>;
    fn head<'a>(&'a self, stream: StreamRef<'a>) -> BoxFuture<'a, Result<Head, StoreError>>;
    fn find_command<'a>(
        &'a self,
        stream: StreamRef<'a>,
        command_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>>;
    fn find_triggered<'a>(
        &'a self,
        stream: StreamRef<'a>,
        trigger: &'a EventRef,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>>;
    fn covers<'a>(&'a self, domain: &'a str) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>>;
    fn commit_position(&self) -> BoxFuture<'_, Result<u64, StoreError>>;
}

/// [`SnapshotStore`], object-safe.
pub trait DynSnapshotStore: Send + Sync {
    fn read_snapshot<'a>(
        &'a self,
        stream: StreamRef<'a>,
    ) -> BoxFuture<'a, Result<Option<Snapshot>, StoreError>>;
    fn write_snapshot<'a>(
        &'a self,
        stream: StreamRef<'a>,
        snapshot: &'a Snapshot,
    ) -> BoxFuture<'a, Result<(), StoreError>>;
}

/// [`PositionStore`], object-safe.
pub trait DynPositionStore: Send + Sync {
    fn position<'a>(&'a self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>>;
    fn put_position<'a>(
        &'a self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>>;
}

/// [`UnitOfWork`], object-safe: the unit comes back boxed.
pub trait DynUnitOfWork: Send + Sync {
    #[allow(clippy::type_complexity)]
    fn begin(&self) -> BoxFuture<'_, Result<Box<dyn DynUnit<'_> + '_>, StoreError>>;
}

/// [`Unit`], object-safe. `'s` is how long the unit may borrow its store.
pub trait DynUnit<'s>: Send + 's {
    fn append<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        expected: u64,
        pages: &'a [EventPage],
    ) -> BoxFuture<'a, Result<u64, StoreError>>;
    fn read<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        from: u64,
        to: Option<u64>,
    ) -> BoxFuture<'a, Result<Slice, StoreError>>;
    fn head<'a>(&'a mut self, stream: StreamRef<'a>) -> BoxFuture<'a, Result<Head, StoreError>>;
    fn find_command<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        command_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>>;
    fn find_triggered<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        trigger: &'a EventRef,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>>;
    fn covers<'a>(&'a mut self, domain: &'a str) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>>;
    fn read_snapshot<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
    ) -> BoxFuture<'a, Result<Option<Snapshot>, StoreError>>;
    fn position<'a>(&'a mut self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>>;
    fn put_position<'a>(
        &'a mut self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>>;
    fn commit(self: Box<Self>) -> BoxFuture<'s, Result<(), StoreError>>;
    fn abort(self: Box<Self>) -> BoxFuture<'s, Result<(), StoreError>>;
}

/// [`Editions`], object-safe.
pub trait DynEditions: Send + Sync {
    fn create_edition<'a>(
        &'a self,
        request: &'a CreateEditionRequest,
        now: Timestamp,
    ) -> BoxFuture<'a, Result<Edition, StoreError>>;
    fn delete_edition<'a>(&'a self, name: &'a str) -> BoxFuture<'a, Result<(), StoreError>>;
    fn edition<'a>(&'a self, name: &'a str) -> BoxFuture<'a, Result<Option<Edition>, StoreError>>;
}

/// Every base port, object-safe: what core holds as `Arc<dyn DynStore>`.
pub trait DynStore: DynEventStore + DynSnapshotStore + DynPositionStore + DynUnitOfWork {}

impl<T: DynEventStore + DynSnapshotStore + DynPositionStore + DynUnitOfWork + ?Sized> DynStore
    for T
{
}

// ------------------------------------------- every Send port boxes itself

impl<T: EventStore> DynEventStore for T {
    fn append<'a>(
        &'a self,
        stream: StreamRef<'a>,
        expected: u64,
        pages: &'a [EventPage],
    ) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = (stream, expected, pages);
        todo!("the dyn adapter is a proposal")
    }
    fn read<'a>(
        &'a self,
        stream: StreamRef<'a>,
        from: u64,
        to: Option<u64>,
    ) -> BoxFuture<'a, Result<Slice, StoreError>> {
        let _ = (stream, from, to);
        todo!("the dyn adapter is a proposal")
    }
    fn head<'a>(&'a self, stream: StreamRef<'a>) -> BoxFuture<'a, Result<Head, StoreError>> {
        let _ = stream;
        todo!("the dyn adapter is a proposal")
    }
    fn find_command<'a>(
        &'a self,
        stream: StreamRef<'a>,
        command_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, command_id);
        todo!("the dyn adapter is a proposal")
    }
    fn find_triggered<'a>(
        &'a self,
        stream: StreamRef<'a>,
        trigger: &'a EventRef,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, trigger);
        todo!("the dyn adapter is a proposal")
    }
    fn covers<'a>(&'a self, domain: &'a str) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>> {
        let _ = domain;
        todo!("the dyn adapter is a proposal")
    }
    fn commit_position(&self) -> BoxFuture<'_, Result<u64, StoreError>> {
        todo!("the dyn adapter is a proposal")
    }
}

impl<T: SnapshotStore> DynSnapshotStore for T {
    fn read_snapshot<'a>(
        &'a self,
        stream: StreamRef<'a>,
    ) -> BoxFuture<'a, Result<Option<Snapshot>, StoreError>> {
        let _ = stream;
        todo!("the dyn adapter is a proposal")
    }
    fn write_snapshot<'a>(
        &'a self,
        stream: StreamRef<'a>,
        snapshot: &'a Snapshot,
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = (stream, snapshot);
        todo!("the dyn adapter is a proposal")
    }
}

impl<T: PositionStore> DynPositionStore for T {
    fn position<'a>(&'a self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = key;
        todo!("the dyn adapter is a proposal")
    }
    fn put_position<'a>(
        &'a self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = (key, next);
        todo!("the dyn adapter is a proposal")
    }
}

impl<T: UnitOfWork> DynUnitOfWork for T {
    fn begin(&self) -> BoxFuture<'_, Result<Box<dyn DynUnit<'_> + '_>, StoreError>> {
        todo!("the dyn adapter is a proposal")
    }
}

impl<'s, U: Unit + 's> DynUnit<'s> for U {
    fn append<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        expected: u64,
        pages: &'a [EventPage],
    ) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = (stream, expected, pages);
        todo!("the dyn adapter is a proposal")
    }
    fn read<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        from: u64,
        to: Option<u64>,
    ) -> BoxFuture<'a, Result<Slice, StoreError>> {
        let _ = (stream, from, to);
        todo!("the dyn adapter is a proposal")
    }
    fn head<'a>(&'a mut self, stream: StreamRef<'a>) -> BoxFuture<'a, Result<Head, StoreError>> {
        let _ = stream;
        todo!("the dyn adapter is a proposal")
    }
    fn find_command<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        command_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, command_id);
        todo!("the dyn adapter is a proposal")
    }
    fn find_triggered<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        trigger: &'a EventRef,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, trigger);
        todo!("the dyn adapter is a proposal")
    }
    fn covers<'a>(&'a mut self, domain: &'a str) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>> {
        let _ = domain;
        todo!("the dyn adapter is a proposal")
    }
    fn read_snapshot<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
    ) -> BoxFuture<'a, Result<Option<Snapshot>, StoreError>> {
        let _ = stream;
        todo!("the dyn adapter is a proposal")
    }
    fn position<'a>(&'a mut self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = key;
        todo!("the dyn adapter is a proposal")
    }
    fn put_position<'a>(
        &'a mut self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = (key, next);
        todo!("the dyn adapter is a proposal")
    }
    fn commit(self: Box<Self>) -> BoxFuture<'s, Result<(), StoreError>> {
        todo!("the dyn adapter is a proposal")
    }
    fn abort(self: Box<Self>) -> BoxFuture<'s, Result<(), StoreError>> {
        todo!("the dyn adapter is a proposal")
    }
}

impl<T: Editions> DynEditions for T {
    fn create_edition<'a>(
        &'a self,
        request: &'a CreateEditionRequest,
        now: Timestamp,
    ) -> BoxFuture<'a, Result<Edition, StoreError>> {
        let _ = (request, now);
        todo!("the dyn adapter is a proposal")
    }
    fn delete_edition<'a>(&'a self, name: &'a str) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = name;
        todo!("the dyn adapter is a proposal")
    }
    fn edition<'a>(&'a self, name: &'a str) -> BoxFuture<'a, Result<Option<Edition>, StoreError>> {
        let _ = name;
        todo!("the dyn adapter is a proposal")
    }
}

// ------------------------------------- and dyn DynStore is a port again

impl EventStore for dyn DynStore + '_ {
    async fn append(
        &self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        DynEventStore::append(self, stream, expected, pages).await
    }
    async fn read(
        &self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        DynEventStore::read(self, stream, from, to).await
    }
    async fn head(&self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        DynEventStore::head(self, stream).await
    }
    async fn find_command(
        &self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        DynEventStore::find_command(self, stream, command_id).await
    }
    async fn find_triggered(
        &self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        DynEventStore::find_triggered(self, stream, trigger).await
    }
    async fn covers(&self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        DynEventStore::covers(self, domain).await
    }
    async fn commit_position(&self) -> Result<u64, StoreError> {
        DynEventStore::commit_position(self).await
    }
}

impl SnapshotStore for dyn DynStore + '_ {
    async fn read_snapshot(&self, stream: StreamRef<'_>) -> Result<Option<Snapshot>, StoreError> {
        DynSnapshotStore::read_snapshot(self, stream).await
    }
    async fn write_snapshot(
        &self,
        stream: StreamRef<'_>,
        snapshot: &Snapshot,
    ) -> Result<(), StoreError> {
        DynSnapshotStore::write_snapshot(self, stream, snapshot).await
    }
}

impl PositionStore for dyn DynStore + '_ {
    async fn position(&self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        DynPositionStore::position(self, key).await
    }
    async fn put_position(&self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        DynPositionStore::put_position(self, key, next).await
    }
}

impl<'d> UnitOfWork for dyn DynStore + 'd {
    type Unit<'s>
        = Box<dyn DynUnit<'s> + 's>
    where
        Self: 's;
    async fn begin(&self) -> Result<Self::Unit<'_>, StoreError> {
        DynUnitOfWork::begin(self).await
    }
}

impl<'s> Unit for Box<dyn DynUnit<'s> + 's> {
    async fn append(
        &mut self,
        stream: StreamRef<'_>,
        expected: u64,
        pages: &[EventPage],
    ) -> Result<u64, StoreError> {
        (**self).append(stream, expected, pages).await
    }
    async fn read(
        &mut self,
        stream: StreamRef<'_>,
        from: u64,
        to: Option<u64>,
    ) -> Result<Slice, StoreError> {
        (**self).read(stream, from, to).await
    }
    async fn head(&mut self, stream: StreamRef<'_>) -> Result<Head, StoreError> {
        (**self).head(stream).await
    }
    async fn find_command(
        &mut self,
        stream: StreamRef<'_>,
        command_id: Uuid,
    ) -> Result<Vec<EventPage>, StoreError> {
        (**self).find_command(stream, command_id).await
    }
    async fn find_triggered(
        &mut self,
        stream: StreamRef<'_>,
        trigger: &EventRef,
    ) -> Result<Vec<EventPage>, StoreError> {
        (**self).find_triggered(stream, trigger).await
    }
    async fn covers(&mut self, domain: &str) -> Result<Vec<Cover>, StoreError> {
        (**self).covers(domain).await
    }
    async fn read_snapshot(
        &mut self,
        stream: StreamRef<'_>,
    ) -> Result<Option<Snapshot>, StoreError> {
        (**self).read_snapshot(stream).await
    }
    async fn position(&mut self, key: PositionKey<'_>) -> Result<u64, StoreError> {
        (**self).position(key).await
    }
    async fn put_position(&mut self, key: PositionKey<'_>, next: u64) -> Result<(), StoreError> {
        (**self).put_position(key, next).await
    }
    async fn commit(self) -> Result<(), StoreError> {
        DynUnit::commit(self).await
    }
    async fn abort(self) -> Result<(), StoreError> {
        DynUnit::abort(self).await
    }
}
