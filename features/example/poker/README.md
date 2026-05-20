# Tier: poker

Poker rule scenarios — TDA 2024 / WSOP 2025 / Robert's v11 codified as
cucumber. **Same scenarios run at both tiers**:

- **In-process tier** (formerly "unit-example"): direct aggregate
  handler invocation, synchronous, in-memory. Driven by each client's
  in-process step dir (`unit_steps/` in Python, `tests/example/unit/steps/`
  in other clients).
- **Cluster tier**: live gRPC stack via the client's `CommandClient`,
  hitting deployed coordinators. Driven by `acceptance_steps/`.

Cluster-only assertions (e.g. *"the saga propagates within 5 seconds"*)
are no-ops on the in-process tier — in-process sagas run inline so the
condition is trivially met.

## What lives here

One feature file per poker aggregate / rule grouping:

| File | Scope |
|------|-------|
| `player.feature` | Player aggregate: register, deposit, withdraw, reserve, release, reservation flows |
| `table.feature` | Table aggregate: create, seat, leave, start hand, end hand, hand-for-hand |
| `hand.feature` | Hand aggregate: deal (3 variants), betting, community cards, showdown, ranking |
| `tournament.feature` | Tournament aggregate: registration, lifecycle, blinds, rebuys, penalties, H4H, bag-and-tag |
| `game_rules.feature` | Hand-ranking evaluator and game-rules helpers |
| `betting_round.feature` | Betting-round state machine |
| `raise_tracking.feature` | Per-round raise tracking + short-all-in reopen logic |

Framework-concept features (saga dispatch, projector replay, process-manager
state, orchestration patterns) live in [`../framework/`](../framework/) and
run in-process only. Distributed-orchestration scenarios (multi-coordinator
restart, k8s pod state) live in [`../acceptance/`](../acceptance/).

## Rule citations

Every scenario carries a `# Rule:` comment linking to TDA section, WSOP
rule number, or Robert's Rules paragraph. See
[`../RULES.md`](../RULES.md) for the bidirectional rule ↔ scenario index.

## Scenario IDs

Tag format: `@EU-NNNN`. Allocate via:

```bash
git grep -hoE '@EU-[0-9]{4}' features/example/poker/ | sort -u | tail -1
```

Take `max + 1`. Concurrent PRs race; later-merger rebases.

## Consumer wiring

- **Python**: `examples-python/main/unit_steps/` (in-process) and
  `acceptance_steps/` (gRPC) — both behave-driven; runner selects via
  `--stage unit` or `--stage acceptance`.
- **Other languages**: per-repo test dirs under
  `tests/example/{unit,acceptance}/`.

Each runner reads feature files from
`angzarr-project/features/example/poker/` directly. The same `.feature`
file is exercised twice — once per tier.

## Adding a scenario

1. Assert against a single rule's input/output? → here.
   Asserts that depend on multi-coordinator orchestration? → `../acceptance/`.
   Asserts that exercise framework concepts (saga, PM, projector)? →
   `../framework/`.
2. Edit or create a `.feature` file
3. Pick the next `@EU-NNNN` ID
4. Cite the rule in a `# Rule:` comment and update `../RULES.md`
5. Land in `angzarr-project` first; client step defs follow
