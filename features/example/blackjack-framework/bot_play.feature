# Allocated: EU-1600 .. EU-1619
Feature: A player bot plays a seat
  Each person has a player, the "player" domain: a bot that decides their
  moves and keeps what it has seen (decision 14.38). It is an aggregate, not
  a translator, so it can learn later. Their wallet, the "wallet" domain,
  shares the player's root. The table never calls the player and the player
  never calls the table: two translators carry the turn across.

  - The table-to-player translator (policy-table-player) turns every turn
    the table starts (TurnStarted) into a request to that seat's player to
    decide its move (DecideMove), with the hand, the dealer's up-card and
    whether it may double, and nothing a player may not see.
  - The player records its decision (MoveDecided: hit, stand or double).
  - The player-to-table translator (policy-player-table) turns the decision
    into Hit, Stand or DoubleDown at the table.

  Each translator names its target itself, from the event it handles: the
  seat's player from TurnStarted, the table from MoveDecided.

  In these scenarios a driver seats each player directly: it requests the
  seat and confirms it itself, with no buy-in, so no wallet funds are held
  or spent (ledger rule L3 does not apply to such a table).

  Background:
    Given table "Main" with bets from 10 to 100 and buy-ins from 100 to 1000
    And no buy-in process manager is deployed

  # ==========================================================================
  # Seating without a buy-in
  # ==========================================================================

  @EU-1600
  Scenario: A driver seats a player by confirming the seat itself
    When a driver requests seat 0 of table "Main" for "Alice" with 500
    And the driver confirms that seat with ConfirmSeat
    Then "Alice" sits at seat 0 of table "Main" with a stack of 500
    And no wallet funds are held or spent

  # ==========================================================================
  # One turn, translated each way
  # ==========================================================================

  @EU-1601
  Scenario: The table-to-player translator asks the seat's player to decide
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And "Alice" has bet 20 at seat 0
    And the shoe begins "2♣ 9♦ 4♣ 7♠"
    And the round has been dealt
    When the table-to-player translator handles seat 0's TurnStarted
    Then player "Alice" is asked to decide a move for seat 0 of round 1 at table "Main"
    And the request holds 2♣ 4♣ for a hard 6 against the dealer's 9♦, may double, with a stack of 480 and a wager of 20
    And the request is addressed to "Alice"'s player root, as the TurnStarted names it
    And the request holds no hole card

  @EU-1602
  Scenario: The player records its decision
    Given player "Alice" has never decided a move
    When player "Alice" is asked to decide a move for seat 0 of round 1 at table "Main" holding 2♣ 4♣ against the dealer's 9♦
    Then player "Alice" records one MoveDecided for seat 0 of round 1 at table "Main"
    And its action is hit, stand or double down
    And player "Alice" has made 1 decision over 1 hand

  @EU-1603
  Scenario Outline: The player-to-table translator turns a decision into the table's command
    Given player "Alice" recorded MoveDecided <action> for seat 0 of round 1 at table "Main"
    When the player-to-table translator handles it
    Then table "Main" is asked to <command> at seat 0
    And the command is addressed to table "Main", as the MoveDecided names it

    Examples:
      | action      | command     |
      | hit         | Hit         |
      | stand       | Stand       |
      | double down | DoubleDown  |

  @EU-1604
  Scenario: A decision with no action is a player bug
    Given player "Alice" recorded MoveDecided with no action for seat 0 of round 1 at table "Main"
    When the player-to-table translator handles it
    Then no command is sent to table "Main"
    And the MoveDecided is dead-lettered and an alert is raised

  @EU-1605
  Scenario: A redelivered turn asks the player once
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And "Alice" has bet 20 at seat 0
    And the shoe begins "2♣ 9♦ 4♣ 7♠"
    And the round has been dealt
    When seat 0's TurnStarted is delivered to the table-to-player translator twice
    Then player "Alice" records one MoveDecided for that turn

  # ==========================================================================
  # The loop: the turn comes back until the hand is finished
  # ==========================================================================

  @EU-1606
  Scenario: A player hits until it stands, then the round settles
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And player "Alice" hits below 12 and stands on 12 or more
    And "Alice" has bet 20 at seat 0
    And the shoe begins "2♣ 9♦ 4♣ 7♠ 3♥ 5♦ 10♠"
    When the round is dealt
    Then player "Alice" decides hit on a hard 6, and seat 0 is dealt 3♥ for a hard 9
    And player "Alice" decides hit on a hard 9, and seat 0 is dealt 5♦ for a hard 14
    And player "Alice" decides stand on a hard 14, and seat 0 stands on 14
    And round 1 is settled
    And player "Alice" has made 3 decisions over 1 hand

  @EU-1607
  Scenario: A player that busts is not asked again
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And player "Alice" always hits
    And "Alice" has bet 20 at seat 0
    And the shoe begins "10♣ 9♦ 4♣ 7♠ K♥"
    When the round is dealt
    Then player "Alice" decides hit on a hard 14, and seat 0 is dealt K♥ and busts with 24
    And player "Alice" is not asked again in round 1
    And round 1 is settled

  @EU-1608
  Scenario: A double finishes the hand with one card
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And player "Alice" doubles down whenever it may
    And "Alice" has bet 20 at seat 0
    And the shoe begins "6♣ 9♦ 5♣ 7♠ K♥"
    When the round is dealt
    Then player "Alice" decides double down on a hard 11, and seat 0 is dealt K♥ for 21 on a wager of 40
    And player "Alice" is not asked again in round 1
    And round 1 is settled

  @EU-1609
  Scenario: The turn reaches each seat's own player in seat order
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And "Bob" sits at seat 1 of table "Main" with a stack of 500
    And players "Alice" and "Bob" always stand
    And "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "2♣ 3♣ 9♦ 4♣ 5♣ 7♠"
    When the round is dealt
    Then player "Alice" is asked first, for seat 0, and player "Bob" next, for seat 1
    And round 1 is settled
