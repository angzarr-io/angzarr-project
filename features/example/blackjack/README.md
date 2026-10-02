# Tier: blackjack rules

House-rule scenarios for the blackjack example: the wallet, the table's seats
and chips, playing a round, and the deterministic shoe. In-process tier only:
scenarios set up prior history (including the exact cards in the shoe) and
drive the aggregates directly. The cluster tier uses named shoe seeds instead
and lives in [`../blackjack-acceptance/`](../blackjack-acceptance/).

| File | Scope | IDs |
|------|-------|-----|
| `player.feature` | Wallet: identity, deposits, withdrawals, holds, top-ups, cash-out credits, loyalty, round history, ledger rule L1 | EU-1400..1439 |
| `table.feature` | Table creation, seat holds and confirmation, adding chips, leaving, ledger rule L2 | EU-1440..1469 |
| `round.feature` | Betting, dealing, card values, turns, dealer play, settlement, reshuffling, L2 per round | EU-1470..1519 |
| `shoe.feature` | Golden vectors for the shuffle pinned in `cards.proto` | EU-1520..1529 |

Every scenario cites a house rule or ledger invariant from
[`RULES.md`](RULES.md) with `# Rule:`; `just check-rules` enforces it.

Protos: `proto/io/angzarr/examples/v1/`.
