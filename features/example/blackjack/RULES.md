# Angzarr House Rules (blackjack)

The blackjack example plays a deliberately small game: one hand per seat, no
split, insurance, surrender or side bets. These house rules (AHR) and the
ledger invariants (L) are the whole rulebook. Every scenario in
`blackjack/*.feature` and `../blackjack-acceptance/*.feature` cites the rule it
expresses with a `# Rule:` comment; a scenario that expresses an application
or framework concept instead carries `# Rule: N/A — <reason>`.

`just check-rules` (`../check_rule_citations.py`) fails when a scenario is
uncited, cites a rule not listed here, or when a rule here is cited by no
scenario. The framework tier (`../blackjack-framework/`) is out of scope for
citations; it exercises L3 and L4 in-process (EU-1580..1584).

## House rules

| ID | Rule |
|----|------|
| AHR-1 | A table has 1–7 seats, numbered from 0, each holding one player and one hand. It uses 1–8 decks. Bets are even with `0 < min_bet <= max_bet`; buy-ins satisfy `0 < min_buy_in <= max_buy_in` and `min_bet <= min_buy_in`. |
| AHR-2 | Cards have rank 1–13 (Ace = 1, Jack/Queen/King count 10) and one of four suits. An Ace counts 11 unless that takes the hand over 21 (a soft total), otherwise 1 (a hard total). A blackjack is an Ace and a 10-point card as the first two cards. |
| AHR-3 | The shoe is shuffled deterministically: SplitMix64 from a 64-bit seed drives a descending Fisher–Yates shuffle through unbiased bounded draws, exactly as pinned in `cards.proto`. The full order is recorded when the shoe is shuffled. The first shoe uses the table's seed; each later shoe uses the first SplitMix64 output of the previous seed. |
| AHR-4 | When a round is dealt and fewer than 11 × (wagered seats + 1) cards remain, a new shoe is shuffled first. No hand of 21 or less holds more than 11 cards, so a round never runs the shoe out. |
| AHR-5 | Bets are even, within `[min_bet, max_bet]`, no larger than the stack, one per seat per round, and only before the round is dealt. A round needs at least one bet. |
| AHR-6 | Dealing order: each wagered seat in ascending order, the dealer's up-card, each wagered seat again, the dealer's hole card. |
| AHR-7 | With an Ace or 10-point card showing, the dealer checks for blackjack. A dealer blackjack settles the round at once: player blackjacks push, every other hand loses. |
| AHR-8 | A player blackjack without a dealer blackjack is paid 3 to 2, and the hand is finished at the deal. |
| AHR-9 | Wagered seats act in ascending order, skipping finished hands. Only the seat on turn may act. |
| AHR-10 | A player may hit, stand or double. Doubling is allowed on the first two cards only, needs a stack at least equal to the wager, doubles the wager and deals exactly one card, finishing the hand. A bust finishes the hand. |
| AHR-11 | The dealer stands on every 17, soft or hard, and draws below 17 — but draws nothing when no hand remains that is neither busted nor a blackjack. |
| AHR-12 | Settlement: a win returns twice the wager, a blackjack the wager plus 3/2 of it, a push the wager, a loss nothing. A busted hand loses whatever the dealer holds. The house gains the wagers less everything returned. The action that finishes the last hand also plays the dealer and settles, in the same step. |
| AHR-13 | Seats are taken in two steps: held for a buy-in, then confirmed. A seat that is held or taken cannot be requested, and a seated player cannot request another seat. A buy-in, and a stack after a top-up, stay within `[min_buy_in, max_buy_in]`. Chips can be added, and a player can leave, only when their seat has no wager in the current round. Leaving cashes out the whole stack. |

## Ledger invariants

| ID | Invariant |
|----|-----------|
| L1 | Wallet, after every event: `bankroll >= sum(open holds) >= 0`, every open hold is positive, and `bankroll = deposited - withdrawn - sent to tables + received from tables`. |
| L2 | Table, after every event: `sum(stacks) + sum(wagers) + house result = chips in - chips out`. |
| L3 | Pairing: every seat confirmation pairs with exactly one spent buy-in hold for the same buy-in and amount; every chips-added with exactly one settled top-up; every cash-out with exactly one cash-out credit. |
| L4 | System-wide, when nothing is in flight: `sum(bankrolls) + sum(stacks + wagers) + sum(house results) = deposits - withdrawals`. |

## Rule → scenarios

| Rule | Scenarios |
|------|-----------|
| AHR-1 | EU-1440, EU-1441, EU-1442 |
| AHR-2 | EU-1479, EU-1480 |
| AHR-3 | EU-1520, EU-1521, EU-1522, EU-1523, EU-1524, EU-1525 |
| AHR-4 | EU-1502, EU-1503 |
| AHR-5 | EU-1470 .. EU-1476 |
| AHR-6 | EU-1477, EU-1478 |
| AHR-7 | EU-1493, EU-1494, EU-1495 |
| AHR-8 | EU-1496 |
| AHR-9 | EU-1481, EU-1482 |
| AHR-10 | EU-1483 .. EU-1489, EA-0024 |
| AHR-11 | EU-1490, EU-1491, EU-1492 |
| AHR-12 | EU-1497 .. EU-1501 |
| AHR-13 | EU-1443 .. EU-1463, EA-0029, EA-0030, EA-0031 |
| L1 | EU-1407 .. EU-1430, EU-1437, EU-1438 |
| L2 | EU-1464, EU-1504 |
| L3 | EA-0046 (and EU-1580, EU-1581, EU-1584 in-process) |
| L4 | EA-0047 (and EU-1575, EU-1580 .. EU-1584 in-process) |

Scenarios exempt as application or framework concepts: EU-1400..1406 and
EU-1431..1436 (identity, loyalty, round history) and the remaining cluster
scenarios in `../blackjack-acceptance/cluster.feature`.
