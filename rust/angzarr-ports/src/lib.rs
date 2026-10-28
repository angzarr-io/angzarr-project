//! angzarr's shared storage contract: ONE set of store ports, used by both
//! angzarr core and annals, and ONE conformance suite every backend runs.
//!
//! **A proposal (red).** The signatures here are for review; every body is
//! `todo!()` until they are approved. The tests under `tests/` pin them,
//! and mark each open design choice `OPEN(n)` with a proposed answer.
//!
//! # The ports
//!
//! | Port | What it keeps | Receiver |
//! |---|---|---|
//! | [`EventStore`] | one append-only log of opaque [`EventPage`]s per stream, the dedup lookups, the global commit position | `&self` |
//! | [`SnapshotStore`] | the newest [`Snapshot`] per stream; the CALLER judges whether it is usable | `&self` |
//! | [`PositionStore`] | a handler's next sequence per stream | `&self` |
//! | [`UnitOfWork`] | opens a [`Unit`]: several writes across streams, positions included, committed or aborted together | `&self` (begin), `&mut self` (the unit) |
//! | [`Purge`], [`UnitPurge`] | opt-in: delete a stream (annals) | `&self` / `&mut self` |
//! | [`Editions`] | opt-in: the edition registry (EA-1) | `&self` |
//!
//! A plain [`EventStore::append`] is an autocommitted unit of one stream:
//! core's 5.6 checkpoint-plus-outbox and annals' multi-stream chain are the
//! same [`UnitOfWork`] at two widths.
//!
//! # Async, Send, local, dyn
//!
//! - **Native async.** Each port method returns `impl Future + Send`; a
//!   backend writes it as a plain `async fn`. No runtime is assumed.
//! - **Browser wasm.** [`local`] holds the same ports with futures that need
//!   not be `Send` (an IndexedDB adapter's). Every `Send` port is also its
//!   local twin by a blanket impl, so code written over the local ports (the
//!   conformance suite is) runs on either.
//! - **dyn.** Native async traits are not object-safe, so [`dyn_store`]
//!   boxes them: `Arc<dyn DynStore>` for core's wiring. annals stays
//!   generic and pays no box.
//!
//! # The suite
//!
//! Behind the `contract` feature: [`contract`] holds one `async fn` per
//! check, generic over the local ports, and [`store_contract!`] stamps one
//! test per check for a backend. See the module.
//!
//! [`EventPage`]: angzarr_proto::v1::EventPage
//! [`Snapshot`]: angzarr_proto::v1::Snapshot

mod error;
mod store;
mod stream;

pub mod dyn_store;
pub mod local;

#[cfg(feature = "contract")]
pub mod contract;

pub use dyn_store::{
    BoxFuture, DynEditions, DynEventStore, DynPositionStore, DynSnapshotStore, DynStore, DynUnit,
    DynUnitOfWork,
};
pub use error::{Arg, Cause, Recovery, StoreError};
pub use store::{
    Editions, EventStore, PositionStore, Purge, SnapshotStore, Store, Unit, UnitOfWork, UnitPurge,
    DEFAULT_EDITION_STORE,
};
pub use stream::{Head, PositionKey, Slice, StreamRef};

/// The wire types and `uuid`, as the ports use them.
pub use angzarr_proto;
pub use angzarr_proto::uuid::Uuid;
