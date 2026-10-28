//! The conformance suite, run against the reference backend: every section.
//!
//! Red for one reason: the reference `MemoryStore` (tests/memory) is
//! stubbed, so each check panics at the first store call with "the
//! reference MemoryStore is stubbed". The checks themselves are written
//! (src/contract.rs) and are what is up for review.
//!
//! # Open design choices, each with the proposed answer
//!
//! Every choice below is pinned by the checks or signatures named, and is
//! for the human to rule on. Changing one is an edit to the test, then the
//! signature.
//!
//! - **OPEN(1) The stream key.** PROPOSED: core's `StreamRef<'a> { domain,
//!   edition: Option<&str>, root: Uuid }`, `Copy`, its derived order the
//!   listing order, with `TryFrom<&Cover>` refusing a malformed cover once,
//!   at the boundary. ALTERNATIVE: annals' `&Cover`. TRADE-OFF: annals
//!   converts at its edge (one fallible call); listings still return owned
//!   `Cover`s (`covers`), since a `StreamRef` borrows. (tests/stream_ref.rs)
//! - **OPEN(2) Append's expected length.** PROPOSED: annals' explicit
//!   `append(stream, expected, pages) -> new_len`; core passes
//!   `pages[0].sequence` (`append_refuses_a_stale_first_sequence`).
//!   ALTERNATIVE: core's head-implied `append(stream, pages)`. TRADE-OFF: an
//!   argument redundant for core, against an empty append that can still
//!   check `expected`, and a gap (`Discontinuous`) told apart from a race
//!   (`Conflict`).
//! - **OPEN(3) Reads.** PROPOSED: `read(stream, from, to) -> Slice`, an
//!   absent stream an empty slice at 0 (`a_read_of_no_such_stream_is_empty_at_zero`);
//!   `head` kept, as a provided method defaulting to a read past the end
//!   (`head_is_the_next_sequence_and_the_last_recorded_at` holds an override
//!   to the same answer). ALTERNATIVE: annals' `Option<Slice>`. TRADE-OFF:
//!   "no such stream" and "empty" become one answer, which the contract
//!   already treats as the same ("created" means "has a page").
//! - **OPEN(4) `find_triggered` is required,** with no default
//!   (`find_triggered_finds_a_process_managers_events_by_trigger`).
//!   ALTERNATIVE: annals' default "none found". TRADE-OFF: core implements
//!   the trigger index now, before its PMs return; a default would be a
//!   silent dedup hole in any store that forgot it.
//! - **OPEN(5) Snapshots** are core's separate `SnapshotStore`, named
//!   `read_snapshot`/`write_snapshot` (core's `get`/`put` would be ambiguous
//!   with positions' on one type). The store keeps the LAST WRITTEN, even a
//!   lower sequence or other rules: the caller judges
//!   (`a_store_keeps_the_newest_snapshot_per_stream`). A unit reads
//!   snapshots but never writes them: a cache is not part of a commit.
//! - **OPEN(6) Positions** hold the handler's NEXT sequence, `u64`, 0 when
//!   never put (`a_position_is_zero_until_put_then_the_last_put`); a plain
//!   upsert that may lower it (recovery resets), monotonicity being the
//!   dispatcher's. ALTERNATIVE: core's old `Option<u32>` of the last
//!   processed. Keyed by `(handler, StreamRef)`, so main is `None`, not
//!   core's old `"angzarr"` string (pass 7).
//! - **OPEN(7) The unit of work.** `begin` returns `Result` (annals deferred
//!   a failure to the first operation); an explicit `abort` beside
//!   drop-rolls-back (`an_aborted_unit_of_work_lands_nothing`); positions
//!   are written in the unit, so 5.6's checkpoint is atomic with the output
//!   (`a_unit_of_work_puts_positions_with_its_appends`); `Unit<'s>` may
//!   borrow its store (a held connection).
//! - **OPEN(8) Two units on one handle.** `&self` lets a caller begin a
//!   second unit while one is open. PROPOSED: allowed; a backend that cannot
//!   run two (one SQLite connection) makes the second wait. The suite never
//!   opens two on one handle; races use two handles (`pair`). TRADE-OFF: a
//!   task that begins twice on a single-connection backend deadlocks itself.
//! - **OPEN(9) The commit position** is required of every `EventStore`
//!   (annals had it on its unit-opening `Store`), and a snapshot or position
//!   write does not raise it (`the_commit_position_rises_with_every_commit`).
//! - **OPEN(10) Purge** is in the ports as an opt-in capability (annals is
//!   its only implementor), and now also deletes every handler's position on
//!   the stream, which restarts at 0 (`a_purge_deletes_the_streams_positions`).
//! - **OPEN(11) Editions** are in the ports as an opt-in registry
//!   (`Editions`, EA-1), on angzarr-proto's `CreateEditionRequest`/`Edition`,
//!   their refusals folded into `StoreError`. NOT pinned here: EA-3's
//!   fall-through (an edition stream reading main's prefix), undecided as
//!   store-level or caller-level; and EA-2's refusal, which lives in annals'
//!   read units, not yet moved (OPEN(16)). Base appends take any edition.
//! - **OPEN(12) Send and local.** Two trait sets: the root ports' futures are
//!   `Send`, `local::*` the same without, with a blanket impl from each
//!   `Send` port to its local twin, and the suite written over the local
//!   ones (tests/local.rs, tests/send.rs). ALTERNATIVES: the `trait-variant`
//!   proc macro (the same two sets, generated); `cfg(target_arch = "wasm32")`
//!   dropping `Send` (one set, but an API that differs by target); a
//!   `SendWrapper` in the wasm adapter (no variant at all). TRADE-OFF: with
//!   both sets in scope a method call on a concrete store is ambiguous, so a
//!   caller imports one set.
//! - **OPEN(13) The reference in-memory store** lives in this crate's tests,
//!   as the brief asks. ALTERNATIVE: ship it behind a `memory` feature, as
//!   annals' `InMemoryStore` is, for applications' fakes (taskloom's need
//!   one once `Ready` goes).
//! - **OPEN(14) Errors** are this crate's `StoreError`, not annals' (whose
//!   `Report` would mean depending on annals): codes `angzarr-ports-*`,
//!   adapters' failures as `Cause { code, message }`, args as this crate's
//!   `Arg`, a three-way `Recovery`. annals forwards them through its own
//!   errors' `Diagnostic`, and its `annals-next-store-*` codes are renamed
//!   (its catalog changes). (tests/error.rs)
//! - **OPEN(15) The dyn adapter** is one `Arc<dyn DynStore>` (every base
//!   port) that is a `Store` again, plus a `Dyn` twin per port for core's
//!   per-port fields. `Send` backends only. (tests/dyn_adapter.rs)
//! - **OPEN(16) Not moved yet:** annals' `ReadStore`/`ReadUnit` and
//!   `Watch`; core's `read_until_time`, `read_by_correlation`,
//!   `list_streams`; core's 5.6 outbox. PROPOSED: each a later opt-in
//!   capability trait here, with its own section.
//! - **OPEN(17) Names and the command id:** `find_command` (annals') over
//!   `find_by_command_id` (core's); the id is `uuid::Uuid` by value, as
//!   `StreamRef.root` is, not the wire `&Uuid`.
//! - **OPEN(18) A lost race** is refused as `Conflict` at the unit's append
//!   OR its commit, whichever the backend finds it at; the suite accepts
//!   either, and requires nothing of the unit to land
//!   (`a_unit_that_lost_a_race_lands_nothing`).

#[cfg(not(feature = "contract"))]
compile_error!("the suite is behind the `contract` feature: run `just test`");

mod memory;

use memory::MemoryStore;

mod base {
    use super::*;
    angzarr_ports::store_contract!(#[tokio::test], MemoryStore::new());
}

mod purge {
    use super::*;
    angzarr_ports::store_contract!(purge, #[tokio::test], MemoryStore::new());
}

mod editions {
    use super::*;
    angzarr_ports::store_contract!(editions, #[tokio::test], MemoryStore::new());
}

mod pair {
    use super::*;
    angzarr_ports::store_contract!(pair, #[tokio::test], MemoryStore::pair());
}
