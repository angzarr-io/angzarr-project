//! The conformance suite, every section, run against the shipped
//! `MemoryStore` (ruling 13: it must pass all of it).
//!
//! Every section passes but the editions ones, which are PENDING the
//! per-stream editions spec (owner ruling 2026-10-28): kept, ignored, and
//! outside the required-green set. tests/meta.rs proves each check can
//! fail.
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
//!   A refusal fact (14.31, the merged spec) takes the REFUSED command's
//!   `command_id` as its id, no derivation, and lands on the exact stream
//!   of the saga's trigger; `find_command` finds it there and only there
//!   (`find_command_finds_a_refusal_fact_on_the_trigger_stream_by_the_refused_id`).
//!   A process manager is a domain: it keeps no reactor position.
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
//! - **RULED(A) `UnitBusy` is a try-lock.** A backend that cannot serve
//!   two units refuses ANY begin on the handle while one is open, at once,
//!   as `UnitBusy` (`Recovery::Retry`, `angzarr-ports-store-unit-busy`)
//!   (`a_second_begin_on_a_handle_serves_or_refuses_never_waits`).
//! - **RULED(B) EA-3's edges.** The history is main's events below the
//!   divergence commit position; an edition stream is listed once it holds
//!   an event of its own; `find_command` and units see the history. A past
//!   `diverge_at` diverges at the commit position just above main's last
//!   event recorded at or before it; snapshots and positions never fall
//!   through; a stream in an edition never created is a plain stream
//!   outside read units.
//! - **RULED(E) `read_until_time`** answers a `Slice`.
//! - **RULED(F) `read_by_correlation`'s books** carry `next_sequence` = the
//!   stream's head and no snapshot; an edition timeline reads as `read`
//!   does, history included.
//! - **RULED(O1-O6) The outbox.** O1 the entry `{ id, origin, message }`;
//!   O2 an id put again while pending keeps its first message, and once
//!   cleared is a NEW entry (`a_cleared_id_put_again_is_a_new_pending_entry`);
//!   O3 oldest commit first, then put order; O4 one relay per store; O5 no
//!   origin filter; O6 an entry is no event (no commit position) but an
//!   outbox write CHANGES the `Watch` token, so a relay waits rather than
//!   polls (`an_outbox_write_changes_the_change_token`).
//! - **RULED(H) The wasm suite runs:** `just tools` installs
//!   wasm-bindgen-test-runner (pinned to Cargo.lock's wasm-bindgen) and
//!   `just check` runs `just wasm-test`.
//!
//! - **RULED(D) Read units** carry `covers`, `read`, `head` and
//!   `read_snapshot`, every one at the unit's moment and respecting
//!   editions as the store does: a created edition falls through to main
//!   below its divergence, its snapshot never does, an edition never created
//!   is refused (`a_read_unit_heads_and_snapshots_as_it_began`,
//!   `a_read_unit_refuses_heads_and_snapshots_in_an_edition_never_created`,
//!   `a_read_unit_keeps_the_head_and_snapshot_of_a_stream_purged_after_it_began`,
//!   `a_read_unit_heads_a_created_edition_through_to_main_but_not_its_snapshots`).
//! - **RULED(G) `ListStreams`** stays an opt-in trait, REQUIRED of any
//!   backend serving angzarr's `QueryService` (`GetAggregateRoots` lists
//!   every stream across all domains); pinned equal to `covers` over every
//!   domain, in domain order.
//! - **RULED(O7) The dyn outbox:** a dyn unit writes the outbox only when
//!   opened through `DynOutboxStore::begin_outbox`, beside `DynStore`.
//!
//! # Still open
//!
//! - **OPEN(C) Edition creation is an event; its home is pending the
//!   human.** The edition's divergence commit position is pinned only as
//!   behaviour ("main's events committed before the create are its
//!   history"), however it is recorded; `Editions` returns the wire
//!   `Edition`, and the store-side `EditionRecord` is withdrawn. Where the
//!   creation event lives (which stream, which message) is not designed yet.
//!
//!   **To be reworked (owner, 2026-10-28):** editions become PER-STREAM
//!   FORKS. Creating edition X appends a fork event to (D, X, R) at that
//!   stream's next sequence; (D, X, R) reads main's events below ITS OWN
//!   fork sequence, then X's; forks reach downstream streams through
//!   angzarr's data flow (eventually consistent); a time-based fork (one
//!   commit position for all streams) stays an option; there is no
//!   administrative registry. The spec draft (spec/editions-forks) is being
//!   written; until it lands the ports are unchanged, and then C, the
//!   `Editions` trait, and the `editions` and `read_editions` sections (and
//!   the read units' edition refusal) are reworked to the per-stream fork
//!   rule.

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

/// PENDING the per-stream editions spec (owner ruling 2026-10-28): kept,
/// not run, not required green.
mod editions {
    use super::*;
    angzarr_ports::store_contract!(
        editions,
        #[tokio::test]
        #[ignore = "pending the per-stream editions spec, owner ruling 2026-10-28"],
        MemoryStore::new()
    );
}

mod read {
    use super::*;
    angzarr_ports::store_contract!(read, #[tokio::test], pair());
}

mod read_purge {
    use super::*;
    angzarr_ports::store_contract!(read_purge, #[tokio::test], pair());
}

/// PENDING the per-stream editions spec (owner ruling 2026-10-28).
mod read_editions {
    use super::*;
    angzarr_ports::store_contract!(
        read_editions,
        #[tokio::test]
        #[ignore = "pending the per-stream editions spec, owner ruling 2026-10-28"],
        MemoryStore::new()
    );
}

/// PENDING the per-stream editions spec (owner ruling 2026-10-28): a read
/// unit's refusal of an edition "never created" is the registry's rule.
mod read_unknown_edition {
    use super::*;
    angzarr_ports::store_contract!(
        read_unknown_edition,
        #[tokio::test]
        #[ignore = "pending the per-stream editions spec, owner ruling 2026-10-28"],
        pair()
    );
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

mod outbox_watch {
    use super::*;
    angzarr_ports::store_contract!(outbox_watch, #[tokio::test], MemoryStore::new());
}
