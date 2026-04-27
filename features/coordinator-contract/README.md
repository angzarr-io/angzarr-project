# Coordinator-contract features

These cucumber features describe **coordinator-side** behavior — they
were originally placed under `features/client/` but have no client
production code to call. The PARITY_AUDIT.md campaign surfaced them
as findings #22, #26, and #28:

| Feature | Audit finding | Why it doesn't belong in client |
|---|---|---|
| `merge_strategy.feature` | #22 | Sequence/strategy validation is enforced by the coordinator; the client only sets the proto `merge_strategy` field. The 18 scenarios test conflict resolution, retry semantics, and aggregate-handles invariants — all server-side. |
| `state_building.feature` | #26 | Describes a public `build_state(state, event_book)` + `_apply_event` API that doesn't exist in any client. Both clients have private `_rebuild_state` / runtime equivalents called internally during dispatch — the cucumber's documented surface is at the runtime/coordinator tier. |
| `fact_flow.feature` | #28 | Sagas/PMs construct a `SagaResponse.events` payload — already covered end-to-end by `client/saga.feature` running real `dispatch_saga`. The 7 fact_flow scenarios test what the coordinator does with those emitted events: sequence assignment, `external_id` idempotency, failure rollback. |

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
