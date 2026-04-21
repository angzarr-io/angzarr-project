# Tier: acceptance-example

Cluster-tier acceptance. Scenarios here are only meaningful against a deployed
angzarr cluster (standalone docker-compose or Kubernetes) — they exercise
network serialization, pod lifecycle, inter-coordinator routing, and
observable read-model lag.

In-process integration scenarios (single-process sagas, PMs, projectors) live
in [`../unit/`](../unit/) (see `poker_game.feature` and `sync_modes.feature`).
They are NOT duplicated here.

## What lives here

| File | Scope |
|------|-------|
| `cluster.feature` | Smoke end-to-end, saga latency over the wire, coordinator-restart durability, projector consistency bound, cross-coordinator command routing |

## Execution style

gRPC only. The `CommandClient` abstraction is still used by consumer runners,
but this tier pins the `GrpcClient` backend — no `InProcessClient`.

Runners fail fast if neither a cluster bootstrap nor explicit coordinator URLs
(`PLAYER_URL`, `TABLE_URL`, `HAND_URL`) are available.

**Async assertions allowed.** `within N seconds` is the primary pattern — see
[STEP_VOCABULARY.md §4](../../STEP_VOCABULARY.md).

## Environments

| Backend | Trigger | Use case |
|---------|---------|----------|
| GrpcClient (standalone) | `PLAYER_URL=localhost:1310` after `docker-compose up` | Local cluster validation |
| GrpcClient (kind) | `PLAYER_URL=localhost:1310` after port-forward | CI `kind` jobs |
| GrpcClient (cluster) | `PLAYER_URL=<ingress>:<port>` | Pre-release against real cluster |

## Scenario IDs

Tag format: `@EA-NNNN`. Allocate via:

```bash
git grep -hoE '@EA-[0-9]{4}' features/example/acceptance/ | sort -u | tail -1
```

Take `max + 1`. Concurrent PRs race; later-merger rebases.

## Consumer wiring

- **Python**: `examples-python/main/acceptance_steps/` — behave
- **Rust**: `examples-rust/main/tests/tests/acceptance.rs` — cucumber-rs
- Other languages: per-repo `tests/example/acceptance/`

Each runner reads feature files from
`angzarr-project/features/example/acceptance/` directly.

## Adding a scenario

1. Does the scenario ONLY make sense against a deployed cluster? (network
   latency assertions, pod restart, inter-coordinator routing, real-wire
   projector lag) → here. Otherwise → `../unit/`.
2. Each scenario (or logical group) should carry a `# CLUSTER-ONLY:` comment
   noting which deployment it was validated against.
3. Pick the next `@EA-NNNN` ID.
4. Land in `angzarr-project` first; step defs follow.
