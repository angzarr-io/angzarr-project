# Tier group: example

Cucumber specs for the canonical angzarr example — a small blackjack table.
Protos live in `proto/io/angzarr/examples/v1/`.

- **[`blackjack/`](blackjack/)** — house rules (AHR-1..13) and ledger rules
  (L1, L2) for the wallet, the table, a round and the deterministic shoe.
  In-process tier.
- **[`blackjack-framework/`](blackjack-framework/)** — framework concepts
  (translators, the buy-in process manager, the ledger projector,
  snapshots) demonstrated through the blackjack components. In-process tier
  only.
- **[`blackjack-acceptance/`](blackjack-acceptance/)** — scenarios that only
  make sense against a deployed cluster.

## Why blackjack

- **Two bounded contexts** — the wallet owns money off the table, the table
  owns chips on it; every transfer between them is explicit
- **One real process manager** — a buy-in secures a seat and funds in two
  domains, one step at a time
- **In-aggregate lifecycle** — a whole round (deal, turns, dealer, settlement)
  is one aggregate's job, showing when *not* to use a process manager
- **Money provably balances** — ledger invariants L1–L4 are checked at every tier
- **Deterministic** — the shoe is shuffled from a seed with a pinned algorithm,
  so every language deals the same cards

The earlier spec also showed a top-up refused mid-round being undone in the
wallet (compensation), chips added and cash-outs recorded as facts, and a
buy-in undoing either half when the other is refused. The latest
`io.angzarr.v1` contract removes or reshapes each of those constructs; they
wait on the rulings listed in
[`docs/design/blackjack-latest-proto-rulings.md`](../../docs/design/blackjack-latest-proto-rulings.md).

## Domain vocabulary

Blackjack only: player, wallet, bankroll, hold, table, seat, stack, wager,
shoe, round, dealer, cash-out, ledger. No generic `Order`/`Payment` — those
belong in [`../client/`](../client/).

## Consumer wiring

Each `examples-*-lang` repo configures its runner to read these feature files
directly from the `angzarr-project/` submodule mount. See the sub-tier READMEs.

## Adding a scenario

- Codifies a house rule or ledger invariant? → `blackjack/`. Cite it with a
  `# Rule:` comment; add a new rule to [`blackjack/RULES.md`](blackjack/RULES.md)
  first. `just check-rules` enforces citations.
- Asserts on a framework concept's internals? → `blackjack-framework/`.
- Only meaningful on a deployed cluster? → `blackjack-acceptance/` (also cites
  a rule or `# Rule: N/A — <reason>`).
