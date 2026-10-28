//! angzarr's shared storage contract: ONE set of store ports, used by both
//! angzarr core and annals, ONE conformance suite every backend runs, and
//! an in-memory backend that passes it.
//!
//! The tests under `tests/` pin every trait and method, and record each
//! design choice as RULED or OPEN (`tests/contract.rs`).
//!
//! **Editions are per-stream forks (14.32).** Every store reads an edition
//! stream as main below its own fork, then its own events, and refuses
//! outside input to an unforked one; [`Editions`] adds the administration
//! (the time-based fork point, `ListEditions`, `DeleteEdition`). Main is
//! never written by any of it.
//!
//! # The ports
//!
//! | Port | What it keeps | |
//! |---|---|---|
//! | [`EventStore`] | one append-only log of opaque pages per stream, the dedup lookups, the commit position | base |
//! | [`SnapshotStore`] | the snapshot last written per stream; the caller judges it | base |
//! | [`PositionStore`] | a handler's next sequence per stream | base |
//! | [`UnitOfWork`] / [`Unit`] | ONE handling step's atomic write: one stream's appends and snapshot, with the step's positions (and outbox entries), committed or aborted together | base |
//! | [`Purge`] / [`UnitPurge`] | delete a stream | opt-in |
//! | [`Editions`] | per-stream forks' administration: the time-based fork point, `ListEditions`, `DeleteEdition` | opt-in |
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
//!   every section of the suite, editions included: for tests, games, and
//!   anything that needs no durability, and the reference backend for
//!   what-if and AI experimentation (fork a stream into an edition, run
//!   commands there, read both timelines, delete the edition, and main is
//!   unchanged).
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
    UnitOutbox, UnitPurge, Watch, EDITION_FORKED_TYPE_URL,
};
pub use stream::{Head, PositionKey, Slice, StreamRef};

/// The wire types and `uuid`, as the ports use them.
pub use angzarr_proto;
pub use angzarr_proto::uuid::Uuid;
