//! The conformance suite, every section, run against the shipped
//! `MemoryStore` (ruling 13: it must pass all of it).
//!
//! Red for one reason: `MemoryStore` is stubbed, so each check panics with
//! "MemoryStore is a proposal". The checks (src/contract.rs) are what is up
//! for review; tests/meta.rs proves each one can fail.
//!
//! # Rulings (the human, 2026-10-28)
//!
//! - **RULED(1) The stream key** is `StreamRef { domain, edition, root }`.
//! - **RULED(2) Append** takes an explicit `expected`; core passes
//!   `pages[0].sequence` (`append_refuses_a_stale_first_sequence`).
//! - **RULED(3) A missing stream** reads as an empty slice at 0; `head` is
//!   provided.
//! - **RULED(4), then withdrawn: no `find_triggered`.** The PM model is
//!   facts only (2026-10-28): a PM's only input is facts addressed to it,
//!   sagas turn foreign events into facts, and there are no triggers. A
//!   fact's events carry its derived command id as their cause, so
//!   `find_command` is the fact lookup too, and no `find_fact` is needed
//!   (`find_command_finds_a_retried_facts_events_by_its_id`).
//! - **RULED(5) Snapshots** are a separate `SnapshotStore`, last written
//!   kept, the caller judging.
//! - **RULED(6) Positions** are the next sequence, `u64`, 0 when never put,
//!   a plain upsert.
//! - **RULED(7, 18) Units:** `begin` returns `Result`; `abort` beside drop;
//!   positions in the unit; a lost race is `Conflict` at append or commit.
//! - **RULED(8) Two units on one handle** are allowed; a backend that cannot
//!   serve the second refuses it as `StoreError::UnitBusy`, never waits
//!   (`a_second_begin_on_a_handle_serves_or_refuses_never_waits`).
//! - **RULED(9) The commit position** is required of every store.
//! - **RULED(10) Purge** is opt-in and deletes positions too.
//! - **RULED(11) EA-3: the store falls through.** An edition's stream is
//!   main's events below its divergence commit position, then its own,
//!   numbered on
//!   (`an_edition_reads_mains_events_below_its_divergence_then_its_own`).
//! - **RULED(12) One trait set,** `Send` except on `wasm32`
//!   (`MaybeSend`/`MaybeSync`); native non-`Send` backends unsupported
//!   (tests/send.rs, tests/wasm.rs).
//! - **RULED(13) `MemoryStore` ships** behind `memory`, a real backend held
//!   to the whole suite (this file).
//! - **RULED(14) Errors** are this crate's, `angzarr-ports-*` (tests/error.rs).
//! - **RULED(15) dyn:** `DynStore` plus per-port dyn traits
//!   (tests/dyn_adapter.rs).
//! - **RULED(16) All now:** read units, watch, core's three reads, and the
//!   outbox, each an opt-in trait with its own section.
//! - **RULED(17)** `find_command`, `Uuid` by value.
//!
//! # Still open (each with a proposal)
//!
//! - **OPEN(A) `UnitBusy`.** "Detect a second begin from the holder" is not
//!   portable (async code has no task identity), so PROPOSED: a backend that
//!   cannot serve two units refuses ANY begin while one is open on the
//!   handle (a try-lock), and `UnitBusy` is `Recovery::Retry`, code
//!   `angzarr-ports-store-unit-busy`. TRADE-OFF: another task's begin is
//!   refused too, rather than queued.
//! - **OPEN(B) EA-3's edges.** Pinned: the history is main's below the
//!   divergence; an edition stream is listed once it holds an event of its
//!   own; `find_command` sees the history; a unit reads it. PROPOSED, not
//!   pinned: a requested past `diverge_at` diverges at the commit position
//!   just above main's last event recorded at or before it; snapshots and
//!   positions never fall through; a stream in an edition never created is
//!   a plain stream outside read units (base appends take any edition).
//! - **OPEN(C) The divergence's home.** PROPOSED: `EditionRecord {
//!   edition: Edition, divergence: u64 }`, since meta.proto's `Edition` has
//!   only `diverged_at` (a time). ALTERNATIVE: a `divergence` field on the
//!   wire `Edition`.
//! - **OPEN(D) Read units** carry annals' `covers` and `read` only; no
//!   `head`, dedup lookups or snapshots.
//! - **OPEN(E) `read_until_time`** answers a `Slice` (the head as read)
//!   rather than core's bare `Vec<EventPage>`.
//! - **OPEN(F) `read_by_correlation`'s books** carry `next_sequence` = the
//!   stream's head (core computed the last page's + 1), no snapshot; an
//!   edition timeline reads as `read` does, history included.
//! - **OPEN(G) `list_streams`** stays its own trait: `covers` needs a
//!   domain, and the base contract has no list of domains. Pinned equal to
//!   `covers` over every domain, in domain order.
//! - **OPEN(O1) The outbox entry** is `{ id: Uuid, origin: String, message:
//!   Any }`: `id` the receiver's dedup key (a command id), `origin` the
//!   writer's handler name, `message` opaque. Kind-agnostic: no field names
//!   a component kind.
//! - **OPEN(O2) Outbox dedup.** Pinned: an id put again while pending keeps
//!   its first message, verbatim. PROPOSED, not pinned: once cleared, the
//!   same id may be put again (dedup across that is the receiver's).
//! - **OPEN(O3) Outbox order:** oldest commit first, then put order; never
//!   by id (pinned).
//! - **OPEN(O4) One relay per store.** `pending` claims nothing, so two
//!   relays would both deliver (still at-least-once). ALTERNATIVE: a leased
//!   `claim(limit, lease)` for several relays; deferred until needed.
//! - **OPEN(O5) No origin filter** on `pending`: one relay drains every
//!   writer's entries.
//! - **OPEN(O6) An outbox entry is no event:** it does not raise the commit
//!   position (pinned). Whether it changes a `Watch` token is not pinned.
//! - **OPEN(O7) The dyn outbox:** a dyn unit writes the outbox only when
//!   opened through `DynOutboxStore::begin_outbox`, beside `DynStore`.
//! - **OPEN(H) The wasm suite** (tests/wasm.rs) is built by `just wasm` but
//!   not run here: no `wasm-bindgen-test-runner` is installed.

#![cfg(not(target_arch = "wasm32"))]

#[cfg(not(all(feature = "contract", feature = "memory")))]
compile_error!("the suite runs on MemoryStore: run `just test` (every feature)");

use angzarr_ports::memory::MemoryStore;

fn pair() -> (MemoryStore, MemoryStore) {
    let a = MemoryStore::new();
    (a.clone(), a)
}

mod base {
    use super::*;
    angzarr_ports::store_contract!(#[tokio::test], MemoryStore::new());
}

mod pair {
    use super::*;
    angzarr_ports::store_contract!(pair, #[tokio::test], pair());
}

mod purge {
    use super::*;
    angzarr_ports::store_contract!(purge, #[tokio::test], MemoryStore::new());
}

mod editions {
    use super::*;
    angzarr_ports::store_contract!(editions, #[tokio::test], MemoryStore::new());
}

mod read {
    use super::*;
    angzarr_ports::store_contract!(read, #[tokio::test], pair());
}

mod read_purge {
    use super::*;
    angzarr_ports::store_contract!(read_purge, #[tokio::test], pair());
}

mod read_editions {
    use super::*;
    angzarr_ports::store_contract!(read_editions, #[tokio::test], MemoryStore::new());
}

mod watch {
    use super::*;
    angzarr_ports::store_contract!(watch, #[tokio::test], MemoryStore::new());
}

mod watch_pair {
    use super::*;
    angzarr_ports::store_contract!(watch_pair, #[tokio::test], pair());
}

mod until_time {
    use super::*;
    angzarr_ports::store_contract!(until_time, #[tokio::test], MemoryStore::new());
}

mod correlation {
    use super::*;
    angzarr_ports::store_contract!(correlation, #[tokio::test], MemoryStore::new());
}

mod list_streams {
    use super::*;
    angzarr_ports::store_contract!(list_streams, #[tokio::test], MemoryStore::new());
}

mod outbox {
    use super::*;
    angzarr_ports::store_contract!(outbox, #[tokio::test], MemoryStore::new());
}
