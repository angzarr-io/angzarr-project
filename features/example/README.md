# Tier group: example

Cucumber specs for the canonical angzarr example — a poker domain spanning
player, table, and hand aggregates with cross-domain sagas and process
managers.

Two sub-tiers, different granularities:

- **[`unit/`](unit/)** — handler-level, synchronous, direct invocation. Tests
  poker business logic (hand ranking, betting rules, saga translation) in
  isolation.
- **[`acceptance/`](acceptance/)** — end-to-end, async, via `CommandClient`.
  Tests the full stack with live sidecars (in-process or gRPC).

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
| Granularity | Single handler / saga / PM | Full chain across aggregates |
| Assertion | `emits DealCards command` | `within 3s, hand domain has CardsDealt event` |
| Setup | State struct, maybe an `EventBook` | Live sidecar, CommandClient, seeded DB |
| Step vocabulary | `a TableSyncSaga` / `the saga handles the event` | `a table "Main" with seated players` / `I start a hand at table "Main"` |
| Failure surface | Handler validation rejections | Wire errors, timeouts, saga propagation failures |
| Temporal model | Synchronous | Async with latency |

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

- Can you assert the outcome against a single handler's return value in a
  synchronous call? → `unit/`
- Does the assertion require the saga chain to actually execute across
  domains, or is it observing final state after async propagation? →
  `acceptance/`

Then follow the sub-tier README's process.
