# Cucumber features

Language-neutral Gherkin specifications. Every `client-*-lang` and `examples-*-lang`
repo vendors this directory (git submodule) and implements step definitions in
its own language against these feature files.

## Three tiers

| Tier | Path | Purpose | Domain vocabulary | Execution style | Consumed by |
|------|------|---------|-------------------|-----------------|-------------|
| **unit-client** | `client/` | Exercise the framework surface: `Router`, `@command_handler`, `@saga`, `@process_manager`, `@projector`, dispatch, rejection, state rebuild. | Generic — `Order`, `Payment`, `Inventory`, `Shipping`. Never poker. | Synchronous. Direct state. In-memory `EventBook`. Factories invoked per dispatch. | Every `client-*-lang` repo |
| **unit-example** | `example/unit/` | Exercise poker business logic — hand ranking, betting state machine, saga translation, PM orchestration, projector rendering — without infra. | Poker — `Player`, `Table`, `Hand`, `DealCards`, `HandStarted`, … | Synchronous direct handler invocation. State as a plain struct. Assertions check handler output. | Every `examples-*-lang` repo |
| **acceptance-example** | `example/acceptance/` | Exercise the full angzarr stack — dispatch, projection, saga propagation, process managers, cascade error modes — against example business logic. | Poker | `CommandClient` abstraction with two backends: in-process (fast, same VM) or gRPC (talks to live sidecar). Async assertions (`within N seconds`) allowed. Full cross-domain chains observed. | Every `examples-*-lang` repo |

Unit-example and acceptance-example do **not** share feature files. Same
phenomena appear at different granularities with different assertions — sharing
would force dual-implementation of every step. See
[`example/README.md`](example/README.md) for the rationale.

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
`tests/example/acceptance/` for the exact invocation.
