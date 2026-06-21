# Tier: framework

Framework-concept scenarios — sagas, projectors, process managers,
orchestrators — demonstrated *through* the poker example types. These
test the angzarr framework's CQRS/event-sourcing machinery using
concrete poker handlers as the substrate, rather than as generic
abstractions.

Compare with [`../../client/`](../../client/), which tests the same
framework concepts at a fully-generic level (using `OrderFulfillment`
and similar placeholder types).

## In-process tier only

These scenarios assert on event-replay state, in-memory propagation
order, and stateful PM progress — internals that aren't observable at
the cluster tier. The cluster tier exercises framework behavior
implicitly via the poker scenarios in [`../poker/`](../poker/).

## What lives here

| File | Scope |
|------|-------|
| `saga.feature` | Saga dispatch — `TableSyncSaga`, `HandResultsSaga`: event → command translation, cross-domain coordination, deferred sequences |
| `process_manager.feature` | `HandFlowPM`: betting state machine, phase transitions, action-clock timeouts, multi-domain correlation |
| `projector.feature` | `OutputProjector`: event-stream rendering, idempotence on replay, deployment independence from aggregates |
| `orchestration.feature` | `BuyInOrchestrator`, `RegistrationOrchestrator`, `RebuyOrchestrator`: cross-aggregate decision coupling, compensating triads, synchronous client responses |

## Tag allocation

| Tag range | Scope |
|-----------|-------|
| `@EU-0300..0399` | saga.feature |
| `@EU-0400..0499` | process_manager.feature |
| `@EU-0500..0599` | projector.feature |
| `@EU-0600..0699` | orchestration.feature |

Next ID:
```bash
git grep -hoE '@EU-[0-9]{4}' features/example/framework/ | sort -u | tail -1
```

## Consumer wiring

- **Python**: `examples-python/main/unit_steps/` — behave with
  `--stage unit`
- **Other languages**: per-repo test dirs under `tests/example/unit/`

Framework features run *only* at the in-process tier. The cluster tier
skips this directory.
