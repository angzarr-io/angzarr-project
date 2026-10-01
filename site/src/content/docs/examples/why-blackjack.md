---
title: Why Blackjack
---
The ⍼ Angzarr example is a small blackjack table. It is chosen because it exercises every event sourcing and CQRS pattern the framework supports, while staying small enough to read in one sitting and concrete enough that every outcome is a number you can check.

The full specification — protos and Gherkin scenarios shared by all six language implementations — lives in the [angzarr-project repository](https://github.com/angzarr-io/angzarr-project): protos under `proto/io/angzarr/examples/blackjack/v1/`, scenarios under `features/example/`.

---

## Two bounded contexts

| Domain | Owns | Key events |
|--------|------|------------|
| **Player** (the wallet) | Every chip not on a table: bankroll, holds, deposits, withdrawals | FundsDeposited, FundsHeld, FundsCaptured, TopUpRequested, CashOutCredited |
| **Table** | Every chip on the table: seats, stacks, the shoe, the current round, the house result | SeatHeld, PlayerSeated, BetPlaced, RoundDealt, RoundSettled, PlayerCashedOut |

Money moves between them only in explicit transfers, so every pattern below has a visible money trail.

---

## Pattern coverage

### 1. Two resources, two domains: a process manager

A **buy-in** needs a seat at the table *and* funds in the wallet. The buy-in process manager holds the seat, holds the funds, confirms the seat, then spends the funds — and undoes whichever half went through if the other is refused. It is the example's only process manager, because it is the only flow that coordinates two domains and whose every next step depends on the previous outcome.

**Same pattern applies to**: booking + payment, order + inventory reservation, account opening across systems.

### 2. Saga with compensation

A **top-up** is a translation: the wallet's `TopUpRequested` becomes the table's `AddChips`. If the table refuses (the player has a bet in play), the refusal is delivered back to the wallet, which releases its hold (`TopUpRefused`).

**Same pattern applies to**: payment → fulfillment rollback, order → inventory release.

### 3. Facts

Chips added at the table and a player's **cash-out** are the table's final word. They reach the wallet as facts — recorded, never refused — and each is recorded exactly once however often it is delivered.

**Same pattern applies to**: payment-provider webhooks, settlement files, any decision another system has already made.

### 4. When *not* to use a process manager

A whole **round** — bets, the deal, each player's turn, dealer play and settlement — happens inside the table aggregate. The command that finishes the last hand also emits the dealer's play and the settlement in the same step. Single-domain orchestration belongs in the aggregate.

### 5. One event, several consumers

`RoundSettled` is folded by the table, turned into round results and loyalty points by two independent sagas, and projected into the ledger. Under a synchronous `CASCADE` request, the four cascade error modes decide what a failed loyalty award does to the caller's answer.

### 6. Read models that prove the money

The ledger projector reads both domains and reports whether everything balances: wallets plus table stacks plus the house result equal deposits minus withdrawals, once no transfer is in flight.

### 7. Concurrency, snapshots, editions, temporal reads

Deposits merge past an unrelated profile change; withdrawals go to human review on conflict; two hits for one hand at once deal exactly one card. The table snapshots routinely and keeps a lasting snapshot at every new shoe. A what-if edition replays a round with a different decision without touching the real table. Wallets can be read as of an earlier point.

### 8. Deterministic replay of randomness

The shoe is shuffled from a seed with a pinned algorithm (SplitMix64 + Fisher–Yates), and the full card order is recorded in the `ShoeShuffled` event. Every language deals the same cards from the same seed, and replay never re-runs the shuffle.

---

## Testing benefits

| Property | Benefit |
|----------|---------|
| **Exact payouts** | Even money, 3:2 for blackjack, the wager back on a push |
| **Fixed dealer rules** | The dealer stands on all 17s; no judgement calls |
| **Golden shoes** | Named seeds deal known cards in every language |
| **Ledger invariants** | Money balances in every wallet, every table, and the system |

---

## A note on games

Blackjack is a *teaching example*. Games are generally not a good fit for event sourcing in production: real-time gameplay needs latency event sourcing does not offer, and most games need neither audit trails nor temporal queries. The patterns, however, transfer directly to the domains where event sourcing pays off — airlines, billing, insurance and anything with money, audit and cross-system coordination.

---

## Next Steps

- **[Aggregates](/examples/aggregates)** — the wallet and table aggregates
- **[Sagas](/examples/sagas)** — translations and compensation
- **[Testing](/operations/testing)** — Gherkin specifications
