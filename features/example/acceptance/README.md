# Tier: acceptance-example

End-to-end poker. Exercises the full angzarr stack — dispatch, projection,
sagas, process managers, rejection, cascade error modes — via the
`CommandClient` abstraction.

## What lives here

| File | Scope |
|------|-------|
| `poker_game.feature` | Player lifecycle → table lifecycle → hand lifecycle → pot awards → variants → tournament flow → error cases |
| `sync_modes.feature` | ASYNC / SIMPLE / CASCADE propagation semantics + CascadeErrorMode (FAIL_FAST / CONTINUE / COMPENSATE / DEAD_LETTER) + PM correlation + latency profiles |

## Domain vocabulary

Poker. See [`../README.md`](../README.md).

## Execution style

`CommandClient` with two pluggable backends:

- **`InProcessClient`** (default) — runs the real router in the test process.
  Fast. Used by local `just` runs and by CI when no sidecar deployment is
  available.
- **`GrpcClient`** — activated when `PLAYER_URL` env var is set. Connects to a
  live aggregate coordinator. Used for CI runs against Kind / Kubernetes and
  standalone docker-compose deployments.

The same feature files run against either backend — pick via environment,
not by switching the scenarios.

**Async assertions allowed.** `within N seconds` is the primary pattern for
observing cross-domain saga propagation — see
[STEP_VOCABULARY.md §4](../../STEP_VOCABULARY.md).

**Full chain visible.** Scenarios can assert on intermediate events emitted
across domains, not just final state. This is what distinguishes acceptance
from unit.

## Environments

| Backend | Trigger | Use case |
|---------|---------|----------|
| InProcessClient | default | Dev loop, fast pre-commit check |
| GrpcClient (standalone) | `PLAYER_URL=localhost:1310` after `docker-compose up` | Local full-stack dev |
| GrpcClient (kind) | `PLAYER_URL=localhost:1310` after port-forward | CI `kind` jobs |
| GrpcClient (cluster) | `PLAYER_URL=<ingress>:<port>` | Pre-release against real cluster |

## Scenario IDs

Tag format: `@EA-NNNN`. Allocate via:

```bash
git grep -hoE '@EA-[0-9]{4}' features/example/acceptance/ | sort -u | tail -1
```

Take `max + 1`. Concurrent PRs race; later-merger rebases.

## Consumer wiring

- **Python**: `examples-python/main/tests/example/acceptance/steps/` — behave,
  CommandClient abstraction
- Other languages: per-repo `tests/example/acceptance/`

Each runner reads feature files from
`angzarr-project/features/example/acceptance/` directly.

## Adding a scenario

1. Does the assertion need the full stack running? → here. Otherwise →
   `../unit/`.
2. Decide whether the scenario should work in *both* InProcess and gRPC
   backends (usually yes) — avoid backend-specific assumptions
3. Prefer `within N seconds` over fixed sleeps; timeouts should be generous
   (2–5s is typical)
4. Pick the next `@EA-NNNN` ID
5. Land in `angzarr-project` first; step defs follow
