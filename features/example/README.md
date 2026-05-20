# Tier group: example

Cucumber specs for the canonical angzarr example — a poker domain spanning
player, table, and hand aggregates with cross-domain sagas and process
managers.

Three sibling directories:

- **[`poker/`](poker/)** — TDA / WSOP / Robert's rule scenarios.
  **Run at both tiers** (in-process via aggregate handlers AND cluster via
  gRPC). Cluster-only assertions no-op on the in-process tier so the same
  `.feature` files exercise both stacks.
- **[`framework/`](framework/)** — framework-concept scenarios (saga
  dispatch, PM state machine, projector rendering, orchestrator decision
  coupling) demonstrated *through* concrete poker handlers. In-process tier
  only — asserts on internals the cluster doesn't expose.
- **[`acceptance/`](acceptance/)** — cluster-tier-only scenarios that ONLY
  make sense against a deployed cluster: coordinator-restart durability,
  inter-coordinator routing, observable projector lag. Not duplicated by
  the in-process tier.

## Why poker

- **Concrete outcomes** — "Bob wins the pot of 15" is easy to assert
- **Multi-aggregate** — Player ↔ Table ↔ Hand forces cross-domain sagas and PMs
- **Deterministic** — seeded decks make showdowns reproducible
- **Rich edge cases** — all-in, side pots, split pots, elimination — real complexity
- **Visible side effects** — player balance changes reflect cross-domain saga execution

## Why the split

The previous layout (`unit/` + `acceptance/`) mixed concerns. Three
distinct things live here:

| | What it asserts | When it runs |
|--|---|---|
| Poker rules | Domain outcomes per TDA/WSOP/Robert's | Both tiers — same `.feature`, two harness backends |
| Framework concepts | Saga/PM/projector/orchestrator internals (replay state, in-memory propagation order, stateful progress) | In-process only |
| Cluster orchestration | Wire latency, pod restart, multi-coordinator routing | Cluster only |

Splitting them three ways means each scenario sits where its assertions
actually make sense.

## Domain vocabulary

Poker only. `Player`, `Table`, `Hand`, `DealCards`, `HandStarted`,
`ShowdownStarted`, pot, stack, buy-in. No generic `Order`/`Payment` — those
belong in [`../client/`](../client/).

## Consumer wiring

Each `examples-*-lang` repo configures its runner to read these feature files
directly from the `angzarr-project/` submodule mount. See the sub-tier READMEs
for invocation details.

## Adding a scenario

Pick the right sub-tier first:

- Codifies a TDA / WSOP / Robert's rule? → `poker/`. Cite the rule via
  `# Rule:` comment and update [`RULES.md`](RULES.md).
- Asserts on a framework concept's internals (saga dispatch order, PM
  state-machine progress, projector idempotence on replay)? → `framework/`.
- Asserts on cluster orchestration (coordinator restart, pod state, sync
  mode propagation timing)? → `acceptance/`.

Then follow the sub-tier README's process.
