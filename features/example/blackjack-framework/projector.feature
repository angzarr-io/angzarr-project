# Allocated: EU-1565 .. EU-1579
Feature: The money ledger
  The ledger is a read model built from both the wallets and the tables. It
  shows each player's wallet, each table's chips and the house result, and
  says whether all the money in the system adds up.

  Why this matters:
  - players and operators read balances without touching the wallets or
    tables themselves
  - money moving between a wallet and a table is visible on both sides, and
    the ledger can tell when a transfer has only been seen on one side
  - when nothing is in flight, everything in wallets, on tables and won by
    the house equals what was deposited minus what was withdrawn (ledger
    rule L4)
  - rebuilding the ledger from the same history always gives the same
    answer

  # ==========================================================================
  # Wallets
  # ==========================================================================

  @EU-1565
  Scenario: A registered player appears with an empty wallet
    When the ledger applies "Alice" registering as "Alice"
    Then the ledger shows "Alice" as "Alice" with a bankroll of 0 and nothing held

  @EU-1566
  Scenario: A player the ledger has never seen is reported as not found
    When the ledger is asked for "Zed"
    Then the ledger reports that it has not seen "Zed"

  @EU-1567
  Scenario: Deposits and withdrawals change the bankroll
    Given the ledger has applied "Alice" registering
    When the ledger applies, for "Alice":
      | event      | amount |
      | deposit    | 1000   |
      | withdrawal | 250    |
    Then the ledger shows "Alice" with a bankroll of 750 and nothing held

  @EU-1568
  Scenario: Held money shows as held, not spent
    Given the ledger has applied "Alice" registering and depositing 1000
    When the ledger applies a hold of 500 for buy-in "B1" for "Alice"
    Then the ledger shows "Alice" with a bankroll of 1000, 500 held and 500 available

  @EU-1569
  Scenario: A deposit recorded by an older version is counted
    Given the ledger has applied "Alice" registering
    When the ledger applies a deposit of 300 for "Alice" stored in the previous shape
    Then the ledger shows "Alice" with a bankroll of 300 and nothing held

  @EU-1570
  Scenario: Loyalty points and recent round results are shown
    Given the ledger has applied "Alice" registering and enrolling in the loyalty programme
    When the ledger applies, for "Alice":
      | event                  | round | amount |
      | round result recorded  | 1     | 20     |
      | loyalty points awarded | 1     | 20     |
      | round result recorded  | 2     | -20    |
      | round result retracted | 2     | -20    |
    Then the ledger shows "Alice" with 20 loyalty points
    And the ledger shows "Alice"'s recent results as round 1 net 20 and round 2 net -20 retracted

  # ==========================================================================
  # Tables and transfers
  # ==========================================================================

  @EU-1571
  Scenario: Seating moves money from a wallet to a table stack
    Given the ledger has applied "Alice" registering and depositing 1000
    And the ledger has applied a hold of 500 for buy-in "B1" for "Alice"
    When the ledger applies both sides of buy-in "B1": "Alice" seated at table "Main" with a stack of 500, and the hold spent
    Then the ledger shows "Alice" with a bankroll of 500 and nothing held
    And the ledger shows table "Main" with stacks of 500
    And the ledger reports nothing in flight

  @EU-1572
  Scenario: A buy-in seen on only one side is in flight
    Given the ledger has applied "Alice" registering and depositing 1000
    And the ledger has applied a hold of 500 for buy-in "B1" for "Alice"
    When the ledger applies "Alice" being seated at table "Main" through buy-in "B1" with a stack of 500
    Then the ledger reports 500 in flight in 1 transfer
    And the ledger does not report the money as balanced

  @EU-1573
  Scenario Outline: A transfer counts as complete whichever side the ledger sees first
    Given the ledger has applied the deposits and holds behind a <transfer> of 200 between "Alice" and table "Main"
    When the ledger applies the table side and the wallet side of the <transfer> in <order> order
    Then the ledger reports nothing in flight
    And the ledger reports the money as balanced

    Examples:
      | transfer | order          |
      | buy-in   | table-first    |
      | buy-in   | wallet-first   |
      | top-up   | table-first    |
      | top-up   | wallet-first   |
      | cash-out | table-first    |
      | cash-out | wallet-first   |

  @EU-1574
  Scenario: A settled round updates stacks, wagers and the house result
    Given the ledger shows table "Main" with stacks of 1000 after buy-ins
    And the ledger has applied bets of 20 and 30 at table "Main"
    When the ledger applies round 1 at table "Main" settling with 40 returned and the house winning 10
    Then the ledger shows table "Main" with stacks of 990, no wagers and a house result of 10

  # ==========================================================================
  # Whole-system balance (L4) and replay
  # ==========================================================================

  @EU-1575
  Scenario: The ledger balances when nothing is in flight
    Given the ledger has applied a complete session in which:
      | what                         | amount |
      | "Alice" deposits             | 1000   |
      | "Bob" deposits               | 1000   |
      | "Alice" buys in at "Main"    | 500    |
      | "Bob" buys in at "Main"      | 500    |
      | the house wins a round       | 50     |
      | "Alice" cashes out           | 480    |
      | "Bob" withdraws              | 200    |
    When the ledger is asked for the totals
    Then the ledger reports nothing in flight
    And the ledger reports the money as balanced
    And the ledger totals are:
      | total        | amount |
      | deposits     | 2000   |
      | withdrawals  | 200    |
      | bankrolls    | 1280   |
      | stacks       | 470    |
      | wagers       | 0      |
      | house result | 50     |

  @EU-1576
  Scenario: Applying the same event twice changes nothing
    Given the ledger has applied "Alice" registering and depositing 1000
    When the ledger applies the same deposit of 1000 for "Alice" again
    Then the ledger shows "Alice" with a bankroll of 1000 and nothing held

  @EU-1577
  Scenario: Rebuilding the ledger from the same history gives the same ledger
    Given the ledger has applied a complete two-player session
    When the ledger is rebuilt from the same history
    Then the rebuilt ledger equals the original ledger
