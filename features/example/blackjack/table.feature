# Allocated: EU-1440 .. EU-1469
Feature: Table seats and chips
  A table owns every chip in front of its players. Players reach a seat in two
  steps: the seat is held while their money is secured, then confirmed with the
  buy-in as their stack. Players leave with their whole stack at any point
  where they have nothing riding.

  Why this matters:
  - two players can never end up in the same seat
  - chips only arrive at a table backed by money from a wallet
  - nobody can take chips away while their bet is in play
  - the table always explains its own chips: buy-ins in, cash-outs out, and
    everything in between is in a stack, a wager or the house result (ledger
    rule L2)

  Adding chips (top-ups), and what happens when a buy-in's seat cannot be
  confirmed, wait on rulings in docs/design/blackjack-latest-proto-rulings.md.

  Unless a scenario says otherwise, table "Main" has 3 seats (0 to 2), one
  deck, bets from 10 to 100 and buy-ins from 100 to 1000.

  # ==========================================================================
  # Creating a table
  # ==========================================================================
  # Rule: AHR-1

  @EU-1440
  Scenario: Creating a table shuffles its first shoe from the seed
    Given table "Main" does not exist
    When table "Main" is created with 3 seats, 1 deck and shoe seed 42
    Then table "Main" is open with 3 empty seats
    And table "Main" has shoe 1 shuffled from seed 42
    And the first 12 cards of the shoe are "7♣ 3♥ K♣ A♠ 2♠ A♣ A♥ K♦ 10♦ 5♣ 8♠ J♥"

  @EU-1441
  Scenario Outline: A table configuration outside the house rules is refused
    Given table "Main" does not exist
    When table "Main" is created with <seats> seats, <decks> decks, bets <min_bet> to <max_bet> and buy-ins <min_buy_in> to <max_buy_in>
    Then the table is refused because its configuration is invalid

    Examples:
      | seats | decks | min_bet | max_bet | min_buy_in | max_buy_in |
      | 0     | 1     | 10      | 100     | 100        | 1000       |
      | 8     | 1     | 10      | 100     | 100        | 1000       |
      | 3     | 0     | 10      | 100     | 100        | 1000       |
      | 3     | 9     | 10      | 100     | 100        | 1000       |
      | 3     | 1     | 100     | 10      | 100        | 1000       |
      | 3     | 1     | 11      | 100     | 100        | 1000       |
      | 3     | 1     | 10      | 100     | 1000       | 100        |
      | 3     | 1     | 10      | 100     | 5          | 1000       |

  @EU-1442
  Scenario: A table cannot be created twice
    Given table "Main" exists
    When table "Main" is created with 3 seats, 1 deck and shoe seed 42
    Then the table is refused because "Main" already exists

  # ==========================================================================
  # Taking a seat (driven by the buy-in process)
  # ==========================================================================
  # Rule: AHR-13

  @EU-1443
  Scenario: A seat request holds the seat for the buy-in
    Given table "Main" exists
    When "Alice" asks for seat 0 at table "Main" with a buy-in of 500 as request "B1"
    Then seat 0 at table "Main" is held for "Alice" by buy-in "B1" of 500
    And no one is seated at table "Main"

  @EU-1444
  Scenario: Repeating a seat request changes nothing
    Given table "Main" exists
    And "Alice" asked for seat 0 at table "Main" with a buy-in of 500 as request "B1"
    When "Alice" asks for seat 0 at table "Main" with a buy-in of 500 as request "B1"
    Then the request succeeds without any change to the table

  @EU-1445
  Scenario Outline: A seat that is taken or held cannot be requested
    Given table "Main" exists
    And seat 1 at table "Main" is <occupied> by "Bob"
    When "Alice" asks for seat 1 at table "Main" with a buy-in of 500 as request "B2"
    Then the seat request is refused because seat 1 is taken

    Examples:
      | occupied |
      | held     |
      | taken    |

  @EU-1446
  Scenario Outline: A seat outside the table cannot be requested
    Given table "Main" exists
    When "Alice" asks for seat <seat> at table "Main" with a buy-in of 500 as request "B1"
    Then the seat request is refused because seat <seat> does not exist

    Examples:
      | seat |
      | -1   |
      | 3    |

  @EU-1447
  Scenario Outline: A buy-in outside the table's range is refused
    Given table "Main" exists
    When "Alice" asks for seat 0 at table "Main" with a buy-in of <amount> as request "B1"
    Then the seat request is refused because the buy-in is outside 100 to 1000

    Examples:
      | amount |
      | 99     |
      | 1001   |

  @EU-1448
  Scenario: A seated player cannot ask for a second seat
    Given table "Main" exists
    And "Alice" is seated at seat 0 of table "Main" with a stack of 500
    When "Alice" asks for seat 2 at table "Main" with a buy-in of 500 as request "B2"
    Then the seat request is refused because "Alice" is already seated

  @EU-1449
  Scenario: Confirming a held seat seats the player with the buy-in as stack
    Given table "Main" exists
    And seat 0 at table "Main" is held for "Alice" by buy-in "B1" of 500
    When buy-in "B1" is confirmed at table "Main"
    Then "Alice" is seated at seat 0 of table "Main" with a stack of 500
    And table "Main" has taken in 500 chips

  @EU-1450
  Scenario: Confirming the same buy-in again changes nothing
    Given table "Main" exists
    And "Alice" is seated at seat 0 of table "Main" through buy-in "B1" of 500
    When buy-in "B1" is confirmed at table "Main"
    Then the request succeeds without any change to the table

  @EU-1453
  Scenario: Releasing a held seat frees it
    Given table "Main" exists
    And seat 0 at table "Main" is held for "Alice" by buy-in "B1" of 500
    When the seat held by buy-in "B1" is released because "funds were refused"
    Then seat 0 at table "Main" is free

  @EU-1454
  Scenario: Releasing a seat that is no longer held changes nothing
    Given table "Main" exists
    When the seat held by buy-in "B9" is released because "funds were refused"
    Then the request succeeds without any change to the table

  # ==========================================================================
  # Leaving
  # ==========================================================================
  # Rule: AHR-13

  @EU-1460
  Scenario: Leaving cashes out the whole stack and frees the seat
    Given table "Main" exists
    And "Alice" is seated at seat 0 of table "Main" with a stack of 640
    When the player at seat 0 of table "Main" leaves
    Then "Alice" cashes out 640 from table "Main"
    And seat 0 at table "Main" is free
    And table "Main" has paid out 640 chips
    And the table "Main" ledger balances

  @EU-1461
  Scenario: A cash-out is identified the same way every time it is replayed
    # The wallet uses this identity to credit a cash-out exactly once.
    Given table "Main" exists
    And "Alice" is seated at seat 0 of table "Main" with a stack of 640
    When the player at seat 0 of table "Main" leaves
    Then the cash-out identity is derived from table "Main" and the position of the cash-out in its history

  @EU-1462
  Scenario: A player with a bet in play cannot leave
    Given table "Main" exists
    And "Alice" is seated at seat 0 of table "Main" with a stack of 500
    And "Alice" has bet 20 at seat 0
    When the player at seat 0 of table "Main" leaves
    Then leaving is refused because a wager is in play

  @EU-1463
  Scenario: Nobody can leave an empty seat
    Given table "Main" exists
    When the player at seat 2 of table "Main" leaves
    Then leaving is refused because seat 2 is not occupied
