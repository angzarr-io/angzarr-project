# Tier: unit-example

Poker business logic at the handler level. Direct invocation, synchronous, no
infrastructure.

## What lives here

One feature file per aggregate/component of the poker example:

| File | Scope |
|------|-------|
| `player.feature` | Player aggregate: register, deposit, withdraw, reserve, release |
| `table.feature` | Table aggregate: create, seat, leave, start hand, end hand |
| `hand.feature` | Hand aggregate: deal (3 variants), betting, community cards, showdown, ranking |
| `saga.feature` | `TableSyncSaga`, `HandResultsSaga` — translation from source events to target commands |
| `process_manager.feature` | Hand-flow PM: betting state machine, phase transitions, auto-fold/check timeouts |
| `projector.feature` | Output projector: event rendering, card formatting, timestamp handling |
| `orchestration.feature` | `BuyInOrchestrator`, `RegistrationOrchestrator`, `RebuyOrchestrator` — compensating triads |

## Domain vocabulary

Poker. See [`../README.md`](../README.md).

## Execution style

Synchronous direct handler invocation.

- State is a plain Python/Go/Rust struct constructed in `Given`
- Events applied with `apply_events(state, events)` helpers
- Commands dispatched with `execute_command(handler, cmd, state)` helpers
- Assertions check the return value: emitted events, emitted commands, state
  deltas, rejection notifications

No `CommandClient`, no sidecars, no `within N seconds`. A scenario that needs
cross-aggregate coordination through the real router belongs in
[`../acceptance/`](../acceptance/).

## Scenario IDs

Tag format: `@EU-NNNN`. Allocate via:

```bash
git grep -hoE '@EU-[0-9]{4}' features/example/unit/ | sort -u | tail -1
```

Take `max + 1`. Concurrent PRs race; later-merger rebases.

## Consumer wiring

- **Python**: `examples-python/main/unit_steps/` — behave
- Other languages: per-repo test dirs under `tests/example/unit/`

Each runner reads feature files from `angzarr-project/features/example/unit/`
directly.

## Adding a scenario

1. Assert against a single handler/saga/PM/projector output? → here.
   Otherwise → `../acceptance/`.
2. Edit or create a `.feature` file
3. Pick the next `@EU-NNNN` ID
4. Land in `angzarr-project` first; step defs follow
