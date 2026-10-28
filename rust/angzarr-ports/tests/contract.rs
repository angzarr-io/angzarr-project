//! The conformance suite, every section, run against the shipped
//! `MemoryStore` (ruling 13: it must pass all of it).
//!
//! tests/meta.rs proves each check can fail.
//!
//! **Red, for the owner's review (this revision):** the step-scoped unit
//! (plan ruling 2) and editions as per-stream forks (14.32) are pinned
//! here and not yet implemented by `MemoryStore`; their checks fail on it,
//! by assertion (the fork rule, the unit's one stream) or at `todo!()`
//! (`Editions`, `Unit::write_snapshot`), and every other check passes.
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
//!   NARROWED by plan ruling 2 (2026-10-28; no cross-stream unit, which was
//!   CASCADE): a unit is ONE handling step's atomic write, one stream's
//!   appends and snapshot with the step's positions and outbox entries
//!   (`a_unit_of_work_writes_one_stream_and_refuses_a_second`,
//!   `a_unit_of_work_lands_its_snapshot_with_its_appends`,
//!   `two_steps_racing_on_one_stream_land_one`).
//! - **RULED(8) Two units on one handle** are allowed; a backend that cannot
//!   serve the second refuses it as `StoreError::UnitBusy`, never waits
//!   (`a_second_begin_on_a_handle_serves_or_refuses_never_waits`).
//! - **RULED(9) The commit position** is required of every store.
//! - **RULED(10) Purge** is opt-in and deletes positions too.
//! - **RULED(11), revised by 14.32: editions are per-stream forks.** Every
//!   store holds the fork rule: an unforked edition stream reads as main's;
//!   its first own event is its fork (else `EditionNotForked`); a forked
//!   stream reads main below ITS OWN fork sequence, then its own; main is
//!   never written (`an_unforked_edition_stream_reads_as_main`,
//!   `an_edition_stream_takes_only_a_fork_as_its_first_own_event`,
//!   `a_forked_stream_reads_main_below_its_fork_then_its_own`). `Editions`
//!   is the administration: the time-based fork point, `ListEditions`
//!   derived from fork events, `DeleteEdition` removing every row tagged
//!   with the edition, and the what-if scenario (the `editions` section).
//! - **RULED(12) One trait set,** `Send` except on `wasm32`
//!   (`MaybeSend`/`MaybeSync`); native non-`Send` backends unsupported
//!   (tests/send.rs, tests/wasm.rs).
//! - **RULED(13) `MemoryStore` ships** behind `memory`, a real backend held
//!   to the whole suite (this file), editions included: the owner's
//!   reference backend for what-if and AI experimentation
//!   (`a_what_if_edition_runs_beside_main_and_leaves_main_untouched`).
//! - **RULED(14) Errors** are this crate's, `angzarr-ports-*` (tests/error.rs).
//!   Every stream an error names is BOXED (owner ruling, 2026-10-28), behind
//!   constructors (`StoreError::conflict(..)`) and `StoreError::stream()`, so
//!   the error stays at most 64 bytes (`the_error_stays_small`) and clippy's
//!   `result_large_err` needs no allowance anywhere.
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
//! - **RULED(B) EA-3's edges,** as 14.32 reworks them: the history is
//!   main's events below the stream's own fork; a forked stream is listed
//!   once forked; `find_command` and units see the history; snapshots and
//!   positions never fall through.
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
//!   `read_snapshot`, every one at the unit's moment and reading editions
//!   as the store does; a stream in an edition that does not exist (no fork
//!   event of it) is refused (`a_read_unit_heads_and_snapshots_as_it_began`,
//!   `a_read_unit_refuses_an_unknown_edition_and_reads_an_unforked_stream_as_main`,
//!   `a_read_unit_keeps_the_head_and_snapshot_of_a_stream_purged_after_it_began`,
//!   `a_read_unit_reads_a_forked_stream_through_to_main`).
//! - **RULED(G) `ListStreams`** stays an opt-in trait, REQUIRED of any
//!   backend serving angzarr's `QueryService` (`GetAggregateRoots` lists
//!   every stream across all domains); pinned equal to `covers` over every
//!   domain, in domain order.
//! - **RULED(O7) The dyn outbox:** a dyn unit writes the outbox only when
//!   opened through `DynOutboxStore::begin_outbox`, beside `DynStore`.
//!
//! - **RULED(C) Edition creation is an event:** the stream's fork,
//!   `EditionForked`, the first event of the edition's version of each
//!   stream (14.32). There is no edition record.
//!
//! # Flagged for the owner (this revision's proposals)
//!
//! - **FLAG(U1) How a unit is bound to its one stream.** PROPOSED: its
//!   first write (an append, even an empty one, a snapshot, a purge) binds
//!   it, and a write to another stream is refused `UnitStreamBound`
//!   (`Recovery::Bug`). ALTERNATIVE: `begin(stream)`, binding up front, with
//!   no stream argument on the unit's writes, so a second stream is
//!   impossible by type. TRADE-OFF: binding by first write keeps one
//!   `begin()` for a step that writes no stream at all (a saga's: positions
//!   and outbox only) and keeps the unit's signatures; `begin(stream)` makes
//!   the refusal unnecessary but needs an unbound begin for those steps.
//! - **FLAG(U2) The step's snapshot is written in its unit**
//!   (`Unit::write_snapshot`), landing with its appends; ruling 5 had kept
//!   snapshots out of units.
//! - **FLAG(E1) The fork is an append.** A store recognises a fork by its
//!   payload type (`EDITION_FORKED_TYPE_URL`) and takes it as the stream's
//!   first own event, at main's head or (time-based) below it; there is no
//!   separate `fork_stream` port, and an arriving saga command's fork and
//!   events may land in one write. The store decodes `EditionForked` only
//!   for `ListEditions`.
//! - **FLAG(E2) `DeleteEdition`'s sequencing is the caller's;** the port is
//!   the removal. The outbox's entries are not yet tagged with an edition
//!   (`OutboxEntry` has none), so the removal does not reach X's outbox
//!   entries: adding `OutboxEntry.edition` is proposed, not pinned.
//! - **FLAG(E3) `read_by_correlation` in an edition** is pinned for the
//!   edition's forked streams (history included); what it answers for the
//!   edition's unforked streams (main's version under the edition's cover,
//!   or nothing) is not pinned.
//! - **FLAG(N) "Reaction" stays out of code:** no identifier in this crate
//!   names it (comments that said "a reactor's output" now say "a step's").

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

mod read_forks {
    use super::*;
    angzarr_ports::store_contract!(read_forks, #[tokio::test], MemoryStore::new());
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
