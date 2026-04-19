# Tier group: example

Cucumber specs for the canonical angzarr example — a poker domain spanning
player, table, and hand aggregates with cross-domain sagas and process
managers.

Two sub-tiers, different granularities:

- **[`unit/`](unit/)** — handler-level and in-process integration tests.
  Single-process invocation (direct handler or `InProcessClient`), no
  deployed cluster. Covers hand ranking, betting rules, saga translation,
  cross-aggregate flow, and sync-mode semantics.
- **[`acceptance/`](acceptance/)** — cluster-tier, gRPC-only. Scenarios that
  ONLY make sense against a deployed cluster: wire-latency assertions,
  coordinator-restart durability, inter-coordinator routing, observable
  projector lag.

## Why poker

- **Concrete outcomes** — "Bob wins the pot of 15" is easy to assert
- **Multi-aggregate** — Player ↔ Table ↔ Hand forces cross-domain sagas and PMs
- **Deterministic** — seeded decks make showdowns reproducible
- **Rich edge cases** — all-in, side pots, split pots, elimination — real complexity
- **Visible side effects** — player balance changes reflect cross-domain saga execution

## Why two sub-tiers, not one

The two sub-tiers look like they overlap — same domain, same entities, often
similar-looking scenario titles. They do not share feature files.

| Dimension | `unit/` | `acceptance/` |
|-----------|---------|---------------|
| Granularity | Single handler OR full in-process chain | Full chain across deployed coordinators |
| Assertion | `emits DealCards command` / `within 3s, hand domain has CardsDealt event` | `within 5s, hand domain has CardsDealt event` over the wire; pod restart; projector lag |
| Setup | State struct / `InProcessClient` | Live gRPC sidecars, bootstrap or external URLs |
| Step vocabulary | `a TableSyncSaga` / `I start a hand at table "Main"` | `the poker cluster is reachable via gRPC` / `the player coordinator is restarted` |
| Failure surface | Handler validation rejections, logical saga failures | Wire errors, timeouts, pod lifecycle, real-network latency |
| Temporal model | Synchronous or in-process async | Network-async with realistic margins |

A scenario that happens to have the same English title in both tiers asserts
different things — that's healthy defense-in-depth, not duplication. See the
root [STEP_VOCABULARY.md](../STEP_VOCABULARY.md).

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

- Does the assertion only make sense against a deployed cluster — wire
  latency, pod restart, coordinator routing, observable projector lag? →
  `acceptance/`
- Everything else (single handler, full in-process flow, sync-mode
  semantics, saga translation) → `unit/`

Then follow the sub-tier README's process.
