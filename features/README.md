# Cucumber features

Language-neutral Gherkin specifications. Every `client-*-lang` and `examples-*-lang`
repo vendors this directory (git submodule) and implements step definitions in
its own language against these feature files.

## Three tiers

| Tier | Path | Purpose | Domain vocabulary | Execution style | Consumed by |
|------|------|---------|-------------------|-----------------|-------------|
| **unit-client** | `client/` | Exercise the framework surface: `Router`, `@command_handler`, `@saga`, `@process_manager`, `@projector`, dispatch, rejection, state rebuild. | Generic — `Order`, `Payment`, `Inventory`, `Shipping`. Never poker. | Synchronous. Direct state. In-memory `EventBook`. Factories invoked per dispatch. | Every `client-*-lang` repo |
| **poker** | `example/poker/` | Exercise poker rules — TDA / WSOP / Robert's. **Same scenarios run at both tiers** (in-process via aggregate handlers, cluster via gRPC). Cluster-only assertions no-op on the in-process tier. | Poker — `Player`, `Table`, `Hand`, `DealCards`, `HandStarted`, … | Both: direct handler invocation (in-process step dir) AND gRPC `CommandClient` (acceptance step dir). | Every `examples-*-lang` repo |
| **example-framework** | `example/framework/` | Exercise the framework concepts (saga dispatch, PM state machine, projector rendering, orchestrator decision coupling) *through* concrete poker handlers — internals visible only in-process. | Poker | Direct handler invocation only. In-process tier only. | Every `examples-*-lang` repo |
| **acceptance-example** | `example/acceptance/` | Cluster-only scenarios that ONLY make sense against a deployed cluster — coordinator restart durability, inter-coordinator routing, observable projector lag. | Poker | `GrpcClient` only. Runs against deployed standalone or k8s. `within N seconds` over the real network. | Every `examples-*-lang` repo |

The **poker** tier is exercised by both in-process and cluster harnesses with
shared `.feature` files. Step impls are duplicated per tier (separate
`unit_steps/` and `acceptance_steps/` dirs in each client), and tier-asymmetric
phrasings get no-op impls in the other dir rather than `@cluster-only` skips.

The **example-framework** tier is in-process-only — it asserts on internals
(replay state, in-memory propagation order, stateful PM progress) that the
cluster tier doesn't expose. Framework behavior at the cluster level is
exercised implicitly by the poker scenarios running there.

See [`example/README.md`](example/README.md) for the rationale and
[`example/poker/README.md`](example/poker/README.md) for poker-tier
conventions.

## Step phrasing

Shared vocabulary conventions across all tiers and all languages:
[`STEP_VOCABULARY.md`](STEP_VOCABULARY.md). Advisory; not CI-enforced.

## Scenario IDs

Every scenario carries a tag `@<tier-code>-NNNN` where:

- `C` — client tier
- `EU` — example unit tier
- `EA` — example acceptance tier
- `NNNN` — zero-padded 4-digit number, assigned in authoring order, never reused

IDs survive file renames and reorderings. Promoting a scenario across tiers
gets a new ID in the new tier's namespace; the old ID is retired.

To allocate the next ID in a tier:

```bash
git grep -hE '@C-[0-9]{4}' features/client/ | grep -oE '@C-[0-9]{4}' | sort -u | tail -1
```

Take `max + 1`. If two concurrent PRs both allocate the same number, the
later-merging PR rebases and bumps.

## Ownership

- **Feature files** live here in `angzarr-project`. One PR adds/edits
  scenarios.
- **Step definitions** live in each consumer repo, implemented in that
  language. Feature-file PRs merge first; step-def PRs follow. CI in consumer
  repos runs red in the window between — by design.

## Consumer wiring

No symlinks. Each consumer repo configures its Gherkin runner to read feature
files directly from the `angzarr-project/` submodule mount path. See each
repo's README under `tests/client/`, `tests/example/unit/`, or
`tests/example/acceptance/` for the exact invocation. Python flavor uses
`unit_steps/` and `acceptance_steps/` at the repo root instead of nested
under `tests/`.
