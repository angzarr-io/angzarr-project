//! angzarr's shared storage contract: ONE set of store ports, used by both
//! angzarr core and annals, ONE conformance suite every backend runs, and
//! an in-memory backend that passes it.
//!
//! The tests under `tests/` pin every trait and method, and record each
//! design choice as RULED or OPEN (`tests/contract.rs`).
//!
//! **Editions are provisional.** [`Editions`] and the edition sections of
//! the suite pin the registry-and-divergence model, which the owner's
//! per-stream fork rule (2026-10-28) replaces; the spec is in draft. The
//! trait stays in the crate, documented as provisional, so the pending
//! checks still compile against it; no backend here implements it yet.
//!
//! # The ports
//!
//! | Port | What it keeps | |
//! |---|---|---|
//! | [`EventStore`] | one append-only log of opaque pages per stream, the dedup lookups, the commit position | base |
//! | [`SnapshotStore`] | the snapshot last written per stream; the caller judges it | base |
//! | [`PositionStore`] | a handler's next sequence per stream | base |
//! | [`UnitOfWork`] / [`Unit`] | appends and positions across streams, committed or aborted together | base |
//! | [`Purge`] / [`UnitPurge`] | delete a stream | opt-in |
//! | [`Editions`] | the edition registry (EA-1), and the store's fall-through to main (EA-3) | opt-in |
//! | [`ReadStore`] / [`ReadUnit`] | reads that all see one moment | opt-in |
//! | [`Watch`] | a cheap "anything committed?" | opt-in |
//! | [`ReadUntilTime`], [`ReadByCorrelation`], [`ListStreams`] | core's queries | opt-in |
//! | [`Outbox`] / [`UnitOutbox`] | the transactional outbox, kind-agnostic | opt-in |
//!
//! # Send, wasm, dyn
//!
//! - **One trait set, native async.** Each method returns
//!   `impl Future + MaybeSend`; a backend writes `async fn`.
//!   [`MaybeSend`]/[`MaybeSync`] are `Send`/`Sync` on every target but
//!   `wasm32`, where a browser backend's futures need not be. **A native
//!   backend whose futures are not `Send` is not supported.**
//! - **dyn.** [`dyn_store`] boxes the ports for core's `Arc<dyn DynStore>`.
//!
//! # Features
//!
//! - `memory`: [`memory::MemoryStore`], a real backend in memory, held to
//!   every section of the suite: for tests, games, and anything that needs
//!   no durability.
//! - `contract`: the conformance suite, [`contract`] and
//!   [`store_contract!`].

mod error;
mod send;
mod store;
mod stream;

pub mod dyn_store;

#[cfg(feature = "contract")]
pub mod contract;
#[cfg(feature = "memory")]
pub mod memory;

pub use dyn_store::{
    BoxFuture, DynEditions, DynEventStore, DynListStreams, DynOutbox, DynOutboxStore,
    DynOutboxUnit, DynPositionStore, DynReadByCorrelation, DynReadUntilTime, DynSnapshotStore,
    DynStore, DynUnit, DynUnitOfWork,
};
pub use error::{Arg, Cause, Recovery, StoreError};
pub use send::{MaybeSend, MaybeSync};
pub use store::{
    ChangeToken, Editions, EventStore, ListStreams, Outbox, OutboxEntry, PositionStore, Purge,
    ReadByCorrelation, ReadStore, ReadUnit, ReadUntilTime, SnapshotStore, Store, Unit, UnitOfWork,
    UnitOutbox, UnitPurge, Watch, DEFAULT_EDITION_STORE,
};
pub use stream::{Head, PositionKey, Slice, StreamRef};

/// The wire types and `uuid`, as the ports use them.
pub use angzarr_proto;
pub use angzarr_proto::uuid::Uuid;
