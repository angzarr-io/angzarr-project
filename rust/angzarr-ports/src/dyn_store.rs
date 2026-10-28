//! The dyn adapter: the ports as object-safe traits whose futures are
//! boxed, for core's `Arc<dyn …>` wiring (ruling 15).
//!
//! Native async traits are not object-safe, so each port core holds has a
//! `Dyn` twin returning [`BoxFuture`], implemented for every backend by a
//! blanket impl here. [`DynStore`] gathers the base ports, and
//! `dyn DynStore` implements them again, so `Arc<dyn DynStore>` is a
//! [`Store`](crate::Store) and generic code (the suite included) runs on it
//! unchanged. A unit that writes the outbox is opened through
//! [`DynOutboxStore`]. The cost is one allocation and one indirect call per
//! operation; annals stays generic and pays nothing.
//!
//! **A proposal.** The boxing bodies are `todo!()`.

use std::future::Future;
use std::pin::Pin;

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::{Cover, CreateEditionRequest, EventBook, EventPage, EventRef, Snapshot};
use prost_types::Timestamp;

use crate::error::StoreError;
use crate::send::{MaybeSend, MaybeSync};
use crate::store::{
    EditionRecord, Editions, EventStore, ListStreams, Outbox, OutboxEntry, PositionStore,
    ReadByCorrelation, ReadUntilTime, SnapshotStore, Unit, UnitOfWork, UnitOutbox,
};
use crate::stream::{Head, PositionKey, Slice, StreamRef};

const DYN: &str = "the dyn adapter is a proposal";

/// A boxed future: `Send` on every target but `wasm32`.
#[cfg(not(target_arch = "wasm32"))]
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;
/// A boxed future: `Send` on every target but `wasm32`.
#[cfg(target_arch = "wasm32")]
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + 'a>>;

/// [`EventStore`], object-safe.
pub trait DynEventStore: MaybeSend + MaybeSync {
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
    fn commit_position<'a>(&'a self) -> BoxFuture<'a, Result<u64, StoreError>>;
}

/// [`SnapshotStore`], object-safe.
pub trait DynSnapshotStore: MaybeSend + MaybeSync {
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
pub trait DynPositionStore: MaybeSend + MaybeSync {
    fn position<'a>(&'a self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>>;
    fn put_position<'a>(
        &'a self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>>;
}

/// [`Editions`], object-safe: core's edition admin.
pub trait DynEditions: MaybeSend + MaybeSync {
    fn create_edition<'a>(
        &'a self,
        request: &'a CreateEditionRequest,
        now: Timestamp,
    ) -> BoxFuture<'a, Result<EditionRecord, StoreError>>;
    fn delete_edition<'a>(&'a self, name: &'a str) -> BoxFuture<'a, Result<(), StoreError>>;
    fn edition<'a>(
        &'a self,
        name: &'a str,
    ) -> BoxFuture<'a, Result<Option<EditionRecord>, StoreError>>;
}

/// [`ReadUntilTime`], object-safe.
pub trait DynReadUntilTime: MaybeSend + MaybeSync {
    fn read_until_time<'a>(
        &'a self,
        stream: StreamRef<'a>,
        until: &'a Timestamp,
    ) -> BoxFuture<'a, Result<Slice, StoreError>>;
}

/// [`ReadByCorrelation`], object-safe.
pub trait DynReadByCorrelation: MaybeSend + MaybeSync {
    fn read_by_correlation<'a>(
        &'a self,
        domain: Option<&'a str>,
        edition: Option<&'a str>,
        correlation_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventBook>, StoreError>>;
}

/// [`ListStreams`], object-safe.
pub trait DynListStreams: MaybeSend + MaybeSync {
    fn list_streams<'a>(&'a self) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>>;
}

/// [`Outbox`], object-safe: core's relay.
pub trait DynOutbox: MaybeSend + MaybeSync {
    fn pending<'a>(&'a self, limit: usize) -> BoxFuture<'a, Result<Vec<OutboxEntry>, StoreError>>;
    fn clear<'a>(&'a self, ids: &'a [Uuid]) -> BoxFuture<'a, Result<u64, StoreError>>;
}

/// [`UnitOfWork`], object-safe: the unit comes back boxed.
pub trait DynUnitOfWork: MaybeSend + MaybeSync {
    #[allow(clippy::type_complexity)]
    fn begin(&self) -> BoxFuture<'_, Result<Box<dyn DynUnit<'_> + '_>, StoreError>>;
}

/// [`Unit`], object-safe. `'s` is how long the unit may borrow its store.
pub trait DynUnit<'s>: MaybeSend + 's {
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

/// [`UnitOutbox`], object-safe: a dyn unit that also writes the outbox.
pub trait DynOutboxUnit<'s>: DynUnit<'s> {
    fn put_outbox<'a>(
        &'a mut self,
        entries: &'a [OutboxEntry],
    ) -> BoxFuture<'a, Result<(), StoreError>>;
}

/// A store whose units write the outbox, opened as dyn units: core's saga
/// coordinator, through `Arc<dyn DynStore>` beside it.
pub trait DynOutboxStore: MaybeSend + MaybeSync {
    #[allow(clippy::type_complexity)]
    fn begin_outbox(&self) -> BoxFuture<'_, Result<Box<dyn DynOutboxUnit<'_> + '_>, StoreError>>;
}

/// Every base port, object-safe: what core holds as `Arc<dyn DynStore>`.
pub trait DynStore: DynEventStore + DynSnapshotStore + DynPositionStore + DynUnitOfWork {}

impl<T: DynEventStore + DynSnapshotStore + DynPositionStore + DynUnitOfWork + ?Sized> DynStore
    for T
{
}

// ------------------------------------------- every backend boxes itself

impl<T: EventStore> DynEventStore for T {
    fn append<'a>(
        &'a self,
        stream: StreamRef<'a>,
        expected: u64,
        pages: &'a [EventPage],
    ) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = (stream, expected, pages);
        todo!("{DYN}")
    }
    fn read<'a>(
        &'a self,
        stream: StreamRef<'a>,
        from: u64,
        to: Option<u64>,
    ) -> BoxFuture<'a, Result<Slice, StoreError>> {
        let _ = (stream, from, to);
        todo!("{DYN}")
    }
    fn head<'a>(&'a self, stream: StreamRef<'a>) -> BoxFuture<'a, Result<Head, StoreError>> {
        let _ = stream;
        todo!("{DYN}")
    }
    fn find_command<'a>(
        &'a self,
        stream: StreamRef<'a>,
        command_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, command_id);
        todo!("{DYN}")
    }
    fn find_triggered<'a>(
        &'a self,
        stream: StreamRef<'a>,
        trigger: &'a EventRef,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, trigger);
        todo!("{DYN}")
    }
    fn covers<'a>(&'a self, domain: &'a str) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>> {
        let _ = domain;
        todo!("{DYN}")
    }
    fn commit_position<'a>(&'a self) -> BoxFuture<'a, Result<u64, StoreError>> {
        todo!("{DYN}")
    }
}

impl<T: SnapshotStore> DynSnapshotStore for T {
    fn read_snapshot<'a>(
        &'a self,
        stream: StreamRef<'a>,
    ) -> BoxFuture<'a, Result<Option<Snapshot>, StoreError>> {
        let _ = stream;
        todo!("{DYN}")
    }
    fn write_snapshot<'a>(
        &'a self,
        stream: StreamRef<'a>,
        snapshot: &'a Snapshot,
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = (stream, snapshot);
        todo!("{DYN}")
    }
}

impl<T: PositionStore> DynPositionStore for T {
    fn position<'a>(&'a self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = key;
        todo!("{DYN}")
    }
    fn put_position<'a>(
        &'a self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = (key, next);
        todo!("{DYN}")
    }
}

impl<T: Editions> DynEditions for T {
    fn create_edition<'a>(
        &'a self,
        request: &'a CreateEditionRequest,
        now: Timestamp,
    ) -> BoxFuture<'a, Result<EditionRecord, StoreError>> {
        let _ = (request, now);
        todo!("{DYN}")
    }
    fn delete_edition<'a>(&'a self, name: &'a str) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = name;
        todo!("{DYN}")
    }
    fn edition<'a>(
        &'a self,
        name: &'a str,
    ) -> BoxFuture<'a, Result<Option<EditionRecord>, StoreError>> {
        let _ = name;
        todo!("{DYN}")
    }
}

impl<T: ReadUntilTime> DynReadUntilTime for T {
    fn read_until_time<'a>(
        &'a self,
        stream: StreamRef<'a>,
        until: &'a Timestamp,
    ) -> BoxFuture<'a, Result<Slice, StoreError>> {
        let _ = (stream, until);
        todo!("{DYN}")
    }
}

impl<T: ReadByCorrelation> DynReadByCorrelation for T {
    fn read_by_correlation<'a>(
        &'a self,
        domain: Option<&'a str>,
        edition: Option<&'a str>,
        correlation_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventBook>, StoreError>> {
        let _ = (domain, edition, correlation_id);
        todo!("{DYN}")
    }
}

impl<T: ListStreams> DynListStreams for T {
    fn list_streams<'a>(&'a self) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>> {
        todo!("{DYN}")
    }
}

impl<T: Outbox> DynOutbox for T {
    fn pending<'a>(&'a self, limit: usize) -> BoxFuture<'a, Result<Vec<OutboxEntry>, StoreError>> {
        let _ = limit;
        todo!("{DYN}")
    }
    fn clear<'a>(&'a self, ids: &'a [Uuid]) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = ids;
        todo!("{DYN}")
    }
}

impl<T: UnitOfWork> DynUnitOfWork for T {
    fn begin(&self) -> BoxFuture<'_, Result<Box<dyn DynUnit<'_> + '_>, StoreError>> {
        todo!("{DYN}")
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
        todo!("{DYN}")
    }
    fn read<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        from: u64,
        to: Option<u64>,
    ) -> BoxFuture<'a, Result<Slice, StoreError>> {
        let _ = (stream, from, to);
        todo!("{DYN}")
    }
    fn head<'a>(&'a mut self, stream: StreamRef<'a>) -> BoxFuture<'a, Result<Head, StoreError>> {
        let _ = stream;
        todo!("{DYN}")
    }
    fn find_command<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        command_id: Uuid,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, command_id);
        todo!("{DYN}")
    }
    fn find_triggered<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
        trigger: &'a EventRef,
    ) -> BoxFuture<'a, Result<Vec<EventPage>, StoreError>> {
        let _ = (stream, trigger);
        todo!("{DYN}")
    }
    fn covers<'a>(&'a mut self, domain: &'a str) -> BoxFuture<'a, Result<Vec<Cover>, StoreError>> {
        let _ = domain;
        todo!("{DYN}")
    }
    fn read_snapshot<'a>(
        &'a mut self,
        stream: StreamRef<'a>,
    ) -> BoxFuture<'a, Result<Option<Snapshot>, StoreError>> {
        let _ = stream;
        todo!("{DYN}")
    }
    fn position<'a>(&'a mut self, key: PositionKey<'a>) -> BoxFuture<'a, Result<u64, StoreError>> {
        let _ = key;
        todo!("{DYN}")
    }
    fn put_position<'a>(
        &'a mut self,
        key: PositionKey<'a>,
        next: u64,
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = (key, next);
        todo!("{DYN}")
    }
    fn commit(self: Box<Self>) -> BoxFuture<'s, Result<(), StoreError>> {
        todo!("{DYN}")
    }
    fn abort(self: Box<Self>) -> BoxFuture<'s, Result<(), StoreError>> {
        todo!("{DYN}")
    }
}

impl<'s, U: UnitOutbox + 's> DynOutboxUnit<'s> for U {
    fn put_outbox<'a>(
        &'a mut self,
        entries: &'a [OutboxEntry],
    ) -> BoxFuture<'a, Result<(), StoreError>> {
        let _ = entries;
        todo!("{DYN}")
    }
}

impl<T> DynOutboxStore for T
where
    T: UnitOfWork,
    for<'s> T::Unit<'s>: UnitOutbox,
{
    fn begin_outbox(&self) -> BoxFuture<'_, Result<Box<dyn DynOutboxUnit<'_> + '_>, StoreError>> {
        todo!("{DYN}")
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
