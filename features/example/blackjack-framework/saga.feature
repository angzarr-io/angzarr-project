# Allocated: EU-1530 .. EU-1549
Feature: Translations between wallet and table
  The wallet and the table never call each other. When something happens on
  one side that the other must act on, a translator turns it into a request
  for the other side.

  Why this matters:
  - one settled round feeds several independent follow-ups: the player's
    round history and their loyalty points
  - a translator only translates: it never looks anything up and never
    decides anything

  The translators:
  - round-history translator (saga-table-player-history): a settled round
    becomes a round result for each seat
  - loyalty translator (saga-table-player-loyalty): a settled round becomes
    loyalty points for each seat, one point per chip wagered

  The top-up translator (wallet top-ups become requests to add chips, with
  refusals undone in the wallet) and the settlement translator (chips added
  and cash-outs become facts in the wallet) wait on rulings in
  docs/design/blackjack-latest-proto-rulings.md.

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
