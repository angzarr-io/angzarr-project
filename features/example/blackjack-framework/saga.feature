# Allocated: EU-1530 .. EU-1549
Feature: Translations between wallet and table
  The wallet and the table never call each other. When something happens on
  one side that the other must act on, a translator turns it into a request
  (which the other side may refuse) or into a fact (which it must accept).

  Why this matters:
  - a top-up needs the table's agreement, so it travels as a request; if the
    table says no, the wallet hears about it and undoes its hold
  - chips added at the table and a player's cash-out are already decided, so
    they travel as facts the wallet records exactly once, however often they
    are delivered
  - one settled round feeds several independent follow-ups: the player's
    round history and their loyalty points
  - a translator only translates: it never looks anything up and never
    decides anything

  The translators:
  - top-up translator (saga-player-table): wallet top-up requests become
    requests to add chips at the table
  - settlement translator (saga-table-player-settlement): chips added and
    cash-outs at the table become facts in the wallet
  - round-history translator (saga-table-player-history): a settled round
    becomes a round result for each seat
  - loyalty translator (saga-table-player-loyalty): a settled round becomes
    loyalty points for each seat, one point per chip wagered

  # ==========================================================================
  # Top-ups: wallet -> table
  # ==========================================================================

  @EU-1530
  Scenario: A top-up request becomes a request to add chips at the named table
    Given "Alice" asked to top up 200 at table "Main" with request "T1"
    When the top-up translator handles the request
    Then table "Main" is asked to add 200 chips for "Alice" from top-up "T1"
    And the request is applied to whatever the table looks like when it arrives

  @EU-1531
  Scenario: The top-up translator ignores wallet events it does not handle
    Given "Alice" deposited 1000
    When the top-up translator handles the deposit
    Then no request is sent to any table

  @EU-1532
  Scenario: A redelivered top-up request adds the chips only once
    # Each request is identified by where it came from, so the table can
    # recognise a second delivery of the same one.
    Given "Alice" is seated at table "Main" with a stack of 500
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    And the top-up translator has handled the request
    When the top-up translator handles the same request again
    Then "Alice" has a stack of 700 at table "Main"
    And table "Main" recorded chips from top-up "T1" once

  # ==========================================================================
  # Refused top-ups: compensation back to the wallet
  # ==========================================================================

  @EU-1533
  Scenario: A top-up the table refuses is undone in the wallet
    Given "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    And "Alice" has a bet in play at table "Main"
    When table "Main" handles the request to add chips from top-up "T1"
    Then the request is refused because a wager is in play
    And the wallet of "Alice" is told the request was refused
    And the top-up "T1" is refused with code "WAGER_IN_PLAY"
    And "Alice" has a bankroll of 1000 with 1000 available

  @EU-1534
  Scenario: The wallet undoes a refused top-up using its current state
    # Between the request and the refusal the player deposited more money;
    # the undo works from the wallet as it is now, not as it was.
    Given "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    And "Alice" deposited 300 afterwards
    When the wallet of "Alice" is told table "Main" refused the request to add chips from top-up "T1" with code "WAGER_IN_PLAY"
    Then the top-up "T1" is refused with code "WAGER_IN_PLAY"
    And "Alice" has a bankroll of 1300 with 1300 available

  @EU-1535
  Scenario: A refusal of a different request does not undo a top-up
    Given "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    When the wallet of "Alice" is told table "Main" refused a seat confirmation
    Then nothing is undone in the wallet of "Alice"
    And "Alice" has an open hold "T1" of 200 for table "Main"

  # ==========================================================================
  # Facts: table -> wallet
  # ==========================================================================

  @EU-1536
  Scenario: Chips added at the table settle the top-up in the wallet
    Given "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    And table "Main" added 200 chips for "Alice" from top-up "T1"
    When the settlement translator handles the chips added
    Then the wallet of "Alice" records, as a fact it cannot refuse, that top-up "T1" of 200 settled
    And "Alice" has a bankroll of 800 with 800 available

  @EU-1537
  Scenario: A cash-out at the table is credited to the wallet
    Given "Alice" is registered with 1000 deposited
    And "Alice" cashed out 640 from table "Main"
    When the settlement translator handles the cash-out
    Then the wallet of "Alice" records, as a fact it cannot refuse, a credit of 640 from table "Main"
    And "Alice" has a bankroll of 1640 with 1640 available

  @EU-1538
  Scenario: Delivering the same cash-out twice credits it once
    Given "Alice" is registered with 1000 deposited
    And "Alice" cashed out 640 from table "Main"
    And the settlement translator has handled the cash-out
    When the settlement translator handles the same cash-out again
    Then the second delivery is recognised as already recorded
    And "Alice" has a bankroll of 1640 with 1640 available

  @EU-1539
  Scenario: Delivering the same chips-added twice settles the top-up once
    Given "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    And table "Main" added 200 chips for "Alice" from top-up "T1"
    And the settlement translator has handled the chips added
    When the settlement translator handles the same chips added again
    Then the second delivery is recognised as already recorded
    And "Alice" has a bankroll of 800 with 800 available

  @EU-1540
  Scenario: A fact the wallet cannot match is still recorded, and flagged
    Given "Alice" is registered with 1000 deposited
    And table "Main" added 200 chips for "Alice" from top-up "T9" that the wallet never requested
    When the settlement translator handles the chips added
    Then the wallet of "Alice" records the settlement and flags it because it matches no open hold
    And "Alice" has a bankroll of 800 with 800 available

  # ==========================================================================
  # A settled round: one event, several follow-ups
  # ==========================================================================

  @EU-1541
  Scenario: A settled round becomes a round result for each seat
    Given round 1 at table "Main" settled with:
      | seat | player | wager | outcome | returned |
      | 0    | Alice  | 20    | win     | 40       |
      | 1    | Bob    | 30    | lose    | 0        |
    When the round-history translator handles the settlement
    Then the wallets are asked to record round 1 at table "Main" as:
      | player | wager | net |
      | Alice  | 20    | 20  |
      | Bob    | 30    | -30 |

  @EU-1542
  Scenario: A settled round awards loyalty points for each seat
    Given round 1 at table "Main" settled with:
      | seat | player | wager | outcome | returned |
      | 0    | Alice  | 20    | win     | 40       |
      | 1    | Bob    | 30    | lose    | 0        |
    When the loyalty translator handles the settlement
    Then the wallets are asked to award loyalty points for round 1 at table "Main" as:
      | player | points |
      | Alice  | 20     |
      | Bob    | 30     |

  @EU-1543
  Scenario: A settled round reaches the table, both translators and the ledger
    Given round 1 at table "Main" settled
    When the settlement is delivered
    Then it is folded into table "Main"
    And it is handled by the round-history translator and the loyalty translator
    And it is applied to the ledger

  @EU-1544
  Scenario: A loyalty award for a player who never enrolled is refused
    Given "Bob" is registered and not a loyalty member
    And the loyalty translator asked to award "Bob" 30 points for round 1 at table "Main"
    When the wallet of "Bob" handles the request
    Then the award is refused because "Bob" is not a loyalty member
    And nothing is undone at table "Main"
