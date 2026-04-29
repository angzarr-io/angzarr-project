# Coordinator-contract features

These cucumber features describe **coordinator-side** behavior — they
were originally placed under `features/client/` but have no client
production code to call (or, in the case of `edition_propagation`, were
landed in client code that's now being reverted because the policy
belongs at the coordinator). The PARITY_AUDIT.md campaign surfaced them
as findings #22, #26, #28, and #86:

| Feature | Audit finding | Why it doesn't belong in client |
|---|---|---|
| `merge_strategy.feature` | #22 | Sequence/strategy validation is enforced by the coordinator; the client only sets the proto `merge_strategy` field. The 18 scenarios test conflict resolution, retry semantics, and aggregate-handles invariants — all server-side. |
| `state_building.feature` | #26 | Describes a public `build_state(state, event_book)` + `_apply_event` API that doesn't exist in any client. Both clients have private `_rebuild_state` / runtime equivalents called internally during dispatch — the cucumber's documented surface is at the runtime/coordinator tier. |
| `fact_flow.feature` | #28 | Sagas/PMs construct a `SagaResponse.events` payload — already covered end-to-end by `client/saga.feature` running real `dispatch_saga`. The 7 fact_flow scenarios test what the coordinator does with those emitted events: sequence assignment, `external_id` idempotency, failure rollback. |
| `edition_propagation.feature` | #86 (reverted) | Audit #86 originally landed in clients as `Cover::propagate_edition_from` + `_propagate_edition_into_books` mutating handler-emitted books in `dispatch_saga` / `dispatch_process_manager`. User direction 2026-04-29: edition propagation belongs at the coordinator — one canonical implementation, universally applied across all clients regardless of language, rather than N copies of the same policy in N client libraries. The 8 scenarios (C-0138..C-0145) describe the always-override contract that the coordinator must enforce. **Tested** in `core/main` via Rust unit tests (12 tests covering all 8 scenarios + main-timeline / divergences / no-trigger-cover edge cases) — see file trailer for the coverage map. |

## Status

These features remain as **living documentation** of the
coordinator's contract. They are NOT executed by any test suite at
the moment.

When a coordinator-tier cucumber suite is built (in the coordinator's
own repo, not the client repos), it should import these and add step
definitions that drive the real coordinator implementation rather
than hand-rolled simulations.

## Why the move?

The original step files in `client-python/main/tests/client/steps/`
and `client-rust/main/tests/steps/` were pure simulations: hand-rolled
`_State` dataclasses + `_MockEvent` / `_MockCommand` types that
asserted against fake state. The cucumber tier reported "green" but
nothing tested real production code. Deep-scan in the audit's
P1.12 campaign caught this; the simulation step files were deleted
along with the move so they don't drift back in.
