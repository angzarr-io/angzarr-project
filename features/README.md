# Cucumber features

Language-neutral Gherkin specifications. Every `client-*-lang` and `examples-*-lang`
repo vendors this directory (git submodule) and implements step definitions in
its own language against these feature files.

## Tiers

| Tier | Path | Purpose | Domain vocabulary | Execution style | Consumed by |
|------|------|---------|-------------------|-----------------|-------------|
| **unit-client** | `client/` | Exercise what a client provides: consumer clients (`CommandHandlerClient`, `QueryClient`, `SpeculativeClient`, `DomainClient`). Dispatch behaviour is specified only by angzarr-router's conformance suite, which every client CI runs against its binding. | Generic — `Order`, `Payment`, `Inventory`, `Shipping`. Never example concepts. | Synchronous, against an in-process fake of the coordinator stubs. | Every `client-*-lang` repo |
| **codegen** | `codegen/` | Declaration lint and generated handler/dispatch shape for `ComponentOptions`. | Generic — `Order`, `Inventory`, … | Against compiled descriptors. | angzarr-cli |
| **coordinator-contract** | `coordinator-contract/` | Behaviour every coordinator implements (sync modes, merge strategies, cascade errors, facts, snapshots, editions). | Generic | Per implementation. | core and every coordinator |
| **blackjack** | `example/blackjack/` | Blackjack house rules (AHR) and wallet/table ledger rules, with exact shoes set up as prior history. | Blackjack — `Player`, `Table`, `RequestSeat`, `RoundSettled`, … | Direct handler invocation. In-process tier only. | Every `examples-*-lang` repo |
| **blackjack-framework** | `example/blackjack-framework/` | Framework concepts (sagas, facts, compensation, process manager, projector, snapshots, whole session) through the blackjack components; asserts on internals the cluster does not expose. | Blackjack | Direct handler invocation only. In-process tier only. | Every `examples-*-lang` repo |
| **blackjack-acceptance** | `example/blackjack-acceptance/` | Cluster-only scenarios: sync modes, merge strategies, cascade error modes, restarts, snapshots, editions, temporal and speculative reads. | Blackjack | `GrpcClient` only, against a deployed cluster. `within N seconds` over the real network. | Every `examples-*-lang` repo |

See [`example/README.md`](example/README.md) for the example's rationale and
layout.

## Step phrasing

Shared vocabulary conventions across all tiers and all languages:
[`STEP_VOCABULARY.md`](STEP_VOCABULARY.md). Advisory; not CI-enforced.

## Scenario IDs

Every scenario carries exactly one tag `@<tier-code>-NNNN`, unique across
the repo, where:

- `C` — framework tiers (`client/`, `coordinator-contract/`, `codegen/`, `../parity/`)
- `EU` — example unit tier
- `EA` — example acceptance tier
- `NNNN` — zero-padded 4-digit number, assigned in authoring order, never reused

`just check-feature-ids [dirs...]` verifies presence, format and uniqueness;
the Contracts workflow runs it on the framework tiers.

IDs survive file renames and reorderings. Promoting a scenario across tiers
gets a new ID in the new tier's namespace; the old ID is retired.

To allocate the next ID in a tier:

```bash
git grep -hoE '@C-[0-9]{4}' -- features parity | sort -u | tail -1
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
