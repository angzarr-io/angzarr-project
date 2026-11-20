# Allocated: EU-1565 .. EU-1579, EU-1613
Feature: The money ledgers
  Two read models, each built from one domain's events (decision 14.96: the
  examples use no multi-domain projector). The wallet ledger
  (projector-wallet-ledger, served by WalletLedgerQueryService) shows each
  player's bankroll, holds, loyalty and recent results. The table ledger
  (projector-table-ledger, served by TableLedgerQueryService) shows each
  table's stacks, wagers, house result and chips in and out.

  Why this matters:
  - players and operators read balances without touching the wallets or
    tables themselves
  - each ledger reads its own domain's events only, so a run of one stream
    is projected on its own, in any order across streams
  - rebuilding a ledger from the same history always gives the same answer

  Neither ledger pairs a transfer across the two domains. That money adds up
  across the whole system (ledger rule L4) is an end-to-end assertion over
  both read models once a run settles
  (../blackjack-acceptance/cluster.feature, EA-0050).

  # ==========================================================================
  # Wallets
  # ==========================================================================

  @EU-1565
  Scenario: A registered player appears with an empty wallet
    When the wallet ledger applies "Alice" registering as "Alice"
    Then the wallet ledger shows "Alice" as "Alice" with a bankroll of 0 and nothing held

  @EU-1566
  Scenario: A player the wallet ledger has never seen is answered not seen
    When the wallet ledger is asked for the balance of "Zed"
    Then the answer is the not_seen arm, with no balance

  @EU-1567
  Scenario: Deposits and withdrawals change the bankroll
    Given the wallet ledger has applied "Alice" registering
    When the wallet ledger applies, for "Alice":
      | event      | amount |
      | deposit    | 1000   |
      | withdrawal | 250    |
    Then the wallet ledger shows "Alice" with a bankroll of 750 and nothing held

  @EU-1568
  Scenario: Held money shows as held, not spent
    Given the wallet ledger has applied "Alice" registering and depositing 1000
    When the wallet ledger applies a hold of 500 for buy-in "B1" for "Alice"
    Then the wallet ledger shows "Alice" with a bankroll of 1000, 500 held and 500 available

  @EU-1569
  Scenario: A deposit recorded by an older version is counted
    Given the wallet ledger has applied "Alice" registering
    When the wallet ledger applies a deposit of 300 for "Alice" stored in the previous shape
    Then the wallet ledger shows "Alice" with a bankroll of 300 and nothing held

  # ==========================================================================
  # A buy-in, as each ledger sees it, and rounds
  # ==========================================================================

  @EU-1571
  Scenario: A spent buy-in hold moves money out of the wallet
    Given the wallet ledger has applied "Alice" registering and depositing 1000
    And the wallet ledger has applied a hold of 500 for buy-in "B1" for "Alice"
    When the wallet ledger applies the hold for buy-in "B1" spent
    Then the wallet ledger shows "Alice" with a bankroll of 500 and nothing held

  @EU-1613
  Scenario: A confirmed seat moves chips onto a table stack
    Given the table ledger has applied table "Main" opening
    When the table ledger applies "Alice" seated at table "Main" through buy-in "B1" with a stack of 500
    Then the table ledger shows table "Main" with stacks of 500 and chips in of 500

  # EU-1572 (a buy-in seen on only one side is in flight) is retired: no
  # ledger pairs a transfer across the wallet and the table any more, so
  # nothing is in flight in a read model (decision 14.96).

  @EU-1574
  Scenario: A settled round updates stacks, wagers and the house result
    Given the table ledger shows table "Main" with stacks of 1000 after buy-ins
    And the table ledger has applied bets of 20 and 30 at table "Main"
    When the table ledger applies round 1 at table "Main" settling with 40 returned and the house winning 10
    Then the table ledger shows table "Main" with stacks of 990, no wagers and a house result of 10

  # ==========================================================================
  # Replay
  # ==========================================================================

  @EU-1576
  Scenario: Applying the same event twice changes nothing
    Given the wallet ledger has applied "Alice" registering and depositing 1000
    When the wallet ledger applies the same deposit of 1000 for "Alice" again
    Then the wallet ledger shows "Alice" with a bankroll of 1000 and nothing held

  @EU-1577
  Scenario Outline: Rebuilding a ledger from the same history gives the same ledger
    Given the <ledger> ledger has applied a complete two-player session
    When the <ledger> ledger is rebuilt from the same history
    Then the rebuilt <ledger> ledger equals the original

    Examples:
      | ledger |
      | wallet |
      | table  |
