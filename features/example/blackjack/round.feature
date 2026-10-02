# Allocated: EU-1470 .. EU-1519
Feature: Playing a round
  A round runs entirely inside the table: players bet, the table deals, each
  player in turn hits, stands or doubles, then the dealer plays and every bet
  is settled. Nothing outside the table takes part, so the action that
  finishes the last hand also plays the dealer and settles the round in the
  same step.

  Why this matters:
  - the dealer's play is fixed by the house rules, so outcomes are never a
    matter of judgement
  - payouts are exact: even money for a win, three to two for a blackjack,
    the wager back for a push
  - after every step the table's chips still add up (ledger rule L2)

  "The shoe begins" lists the next cards to be dealt; the rest of the shoe
  follows in fresh-deck order with those cards taken out, so the shoe is
  always complete and the table never needs to reshuffle unless a scenario
  says so.

  Cards are written rank then suit: A, 2..10, J, Q, K and ♣ ♦ ♥ ♠.

  Background:
    Given table "Main" with bets from 10 to 100 where "Alice" sits at seat 0 and "Bob" at seat 1, each with a stack of 500

  # ==========================================================================
  # Betting
  # ==========================================================================
  # Rule: AHR-5

  @EU-1470
  Scenario: A bet within the limits moves chips from the stack to the wager
    When "Alice" bets 20 at seat 0
    Then seat 0 has a wager of 20 and a stack of 480
    And the table "Main" ledger balances

  @EU-1471
  Scenario Outline: A bet must be even and within the table limits
    When "Alice" bets <amount> at seat 0
    Then the bet is refused because <reason>

    Examples:
      | amount | reason                            |
      | 8      | it is outside the limits 10 to 100 |
      | 102    | it is outside the limits 10 to 100 |
      | 15     | it is not an even amount          |

  @EU-1472
  Scenario: A seat can bet only once per round
    Given "Alice" has bet 20 at seat 0
    When "Alice" bets 20 at seat 0
    Then the bet is refused because seat 0 has already bet this round
    And seat 0 has a wager of 20 and a stack of 480

  @EU-1473
  Scenario: A bet cannot exceed the stack
    Given "Bob" has 30 chips left
    When "Bob" bets 40 at seat 1
    Then the bet is refused because the stack is too small

  @EU-1474
  Scenario: An empty seat cannot bet
    When someone bets 20 at seat 2
    Then the bet is refused because seat 2 is not occupied

  @EU-1475
  Scenario: No bets are taken once the cards are out
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "2♣ 9♦ 4♣ 7♠"
    And the round has been dealt
    When "Bob" bets 20 at seat 1
    Then the bet is refused because a round is in progress

  @EU-1476
  Scenario: A round cannot be dealt without bets
    When the round is dealt
    Then dealing is refused because nobody has bet

  # ==========================================================================
  # Dealing
  # ==========================================================================
  # Rule: AHR-6

  @EU-1477
  Scenario: Cards go to each seat in order, then the dealer, twice
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "2♣ 3♣ 9♦ 4♣ 5♣ 7♠"
    When the round is dealt
    Then round 1 is dealt with:
      | seat | cards | total |
      | 0    | 2♣ 4♣ | 6     |
      | 1    | 3♣ 5♣ | 8     |
    And the dealer shows 9♦ with the hole card 7♠ face down
    And it is seat 0's turn

  @EU-1478
  Scenario: A seat without a bet is dealt no cards
    Given "Bob" has bet 20 at seat 1
    And the shoe begins "5♣ 9♦ 6♣ 7♠"
    When the round is dealt
    Then round 1 is dealt with:
      | seat | cards | total |
      | 1    | 5♣ 6♣ | 11    |
    And seat 0 is dealt no cards
    And it is seat 1's turn

  # ==========================================================================
  # Card values
  # ==========================================================================
  # Rule: AHR-2

  @EU-1479
  Scenario Outline: An ace counts eleven unless that would bust the hand
    When a hand holds <cards>
    Then the hand is worth <total>, <kind>

    Examples:
      | cards     | total | kind      |
      | K♣ Q♦     | 20    | hard      |
      | A♣ 6♣     | 17    | soft      |
      | A♣ A♦     | 12    | soft      |
      | A♣ 6♣ 10♥ | 17    | hard      |
      | A♣ A♦ 9♥  | 21    | soft      |
      | A♣ K♦     | 21    | blackjack |
      | 7♣ 4♦ K♥  | 21    | hard      |

  @EU-1480
  Scenario: A soft hand turns hard instead of busting
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "A♣ 9♦ 6♣ 7♠ 10♥"
    And the round has been dealt
    When "Alice" hits at seat 0
    Then seat 0 is dealt 10♥ for a hard 17
    And it is seat 0's turn

  # ==========================================================================
  # Player turns
  # ==========================================================================
  # Rule: AHR-9

  @EU-1481
  Scenario: A player blackjack is never asked to act
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "A♠ 9♣ 8♦ K♠ 7♣ 9♥"
    When the round is dealt
    Then seat 0 holds a blackjack
    And it is seat 1's turn

  @EU-1482
  Scenario: Only the seat on turn may act
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "2♣ 3♣ 9♦ 4♣ 5♣ 7♠"
    And the round has been dealt
    When "Bob" hits at seat 1
    Then the action is refused because it is not seat 1's turn

  # Rule: AHR-10

  @EU-1483
  Scenario: Hitting below 21 keeps the turn
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "2♣ 3♣ 9♦ 4♣ 5♣ 7♠ 6♥"
    And the round has been dealt
    When "Alice" hits at seat 0
    Then seat 0 is dealt 6♥ for a hard 12
    And it is seat 0's turn

  @EU-1484
  Scenario: Busting ends the hand and passes the turn
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "10♣ 3♣ 9♦ 6♣ 5♣ 7♠ K♥"
    And the round has been dealt
    When "Alice" hits at seat 0
    Then seat 0 is dealt K♥ and busts with 26
    And it is seat 1's turn

  @EU-1485
  Scenario: Standing passes the turn
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "2♣ 3♣ 9♦ 4♣ 5♣ 7♠"
    And the round has been dealt
    When "Alice" stands at seat 0
    Then seat 0 stands on 6
    And it is seat 1's turn

  @EU-1486
  Scenario: Doubling doubles the wager, deals one card and ends the hand
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "6♣ 3♣ 9♦ 5♣ 5♦ 7♠ K♥"
    And the round has been dealt
    When "Alice" doubles down at seat 0
    Then seat 0 is dealt K♥ for 21 on a wager of 40
    And seat 0 has a wager of 40 and a stack of 460
    And it is seat 1's turn
    And the table "Main" ledger balances

  @EU-1487
  Scenario: Doubling is only allowed on the first two cards
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "2♣ 3♣ 9♦ 4♣ 5♣ 7♠ 6♥"
    And the round has been dealt
    And "Alice" has hit at seat 0
    When "Alice" doubles down at seat 0
    Then the action is refused because doubling is only allowed on the first two cards

  @EU-1488
  Scenario: Doubling needs a stack that covers the wager
    Given "Bob" has 30 chips left
    And "Bob" has bet 20 at seat 1
    And the shoe begins "5♣ 9♦ 6♣ 7♠"
    And the round has been dealt
    When "Bob" doubles down at seat 1
    Then the action is refused because the stack is too small

  @EU-1489
  Scenario: Nobody can act between rounds
    When "Alice" hits at seat 0
    Then the action is refused because no round is in progress

  # ==========================================================================
  # Dealer play
  # ==========================================================================
  # Rule: AHR-11

  @EU-1490
  Scenario: The dealer stands on a soft 17
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "10♣ A♦ 9♥ 6♠"
    And the round has been dealt
    When "Alice" stands at seat 0
    Then the dealer reveals 6♠ and stands on a soft 17 without drawing

  @EU-1491
  Scenario: The dealer draws while below 17
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "10♣ 10♦ 8♥ 6♠ 5♥"
    And the round has been dealt
    When "Alice" stands at seat 0
    Then the dealer reveals 6♠, draws 5♥ and stands on 21

  @EU-1492
  Scenario: The dealer does not draw when no hand is left to beat
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "A♠ 10♣ 9♦ K♠ 6♣ 7♠ K♥"
    And the round has been dealt
    When "Bob" hits at seat 1
    Then seat 1 is dealt K♥ and busts with 26
    And the dealer reveals 7♠ and stands on 16 without drawing

  # Rule: AHR-7

  @EU-1493
  Scenario: A dealer blackjack settles the round at the deal
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "10♣ 9♣ A♦ 8♥ 9♥ K♠"
    When the round is dealt
    Then the dealer reveals K♠ for a blackjack
    And round 1 is settled with:
      | seat | wager | outcome | returned | stack after |
      | 0    | 20    | lose    | 0        | 480         |
      | 1    | 20    | lose    | 0        | 480         |
    And the house wins 40

  @EU-1494
  Scenario: A dealer showing a ten without blackjack lets play go on
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "10♣ 10♦ 8♥ 6♠"
    When the round is dealt
    Then it is seat 0's turn

  @EU-1495
  Scenario: A player blackjack against a dealer blackjack is a push
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "A♣ A♦ K♣ Q♠"
    When the round is dealt
    Then round 1 is settled with:
      | seat | wager | outcome | returned | stack after |
      | 0    | 20    | push    | 20       | 500         |

  # ==========================================================================
  # Settlement
  # ==========================================================================
  # Rule: AHR-8

  @EU-1496
  Scenario: A player blackjack is paid three to two at once
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "A♣ 9♦ K♣ 7♠"
    When the round is dealt
    Then the dealer reveals 7♠ and stands on 16 without drawing
    And round 1 is settled with:
      | seat | wager | outcome   | returned | stack after |
      | 0    | 20    | blackjack | 50       | 530         |
    And the house loses 30

  # Rule: AHR-12

  @EU-1497
  Scenario Outline: Standing hands are paid by comparing with the dealer
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "<shoe>"
    And the round has been dealt
    When "Alice" stands at seat 0
    Then round 1 is settled with:
      | seat | wager | outcome   | returned   | stack after |
      | 0    | 20    | <outcome> | <returned> | <stack>     |
    And the table "Main" ledger balances

    Examples:
      | shoe           | outcome | returned | stack |
      | 10♣ 10♦ 9♥ 7♠  | win     | 40       | 520   |
      | 10♣ 10♦ 8♥ 8♠  | push    | 20       | 500   |
      | 10♣ 10♦ 7♥ 8♠  | lose    | 0        | 480   |
      | 10♣ 10♦ 2♥ 6♠ K♥ | win   | 40       | 520   |

  @EU-1498
  Scenario: A busted hand loses even when the dealer busts too
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "10♣ 10♥ 10♦ 6♥ 2♥ 6♠ K♣ K♥"
    And the round has been dealt
    And "Alice" has hit at seat 0
    When "Bob" stands at seat 1
    Then the dealer reveals 6♠, draws K♥ and busts with 26
    And round 1 is settled with:
      | seat | wager | outcome | returned | stack after |
      | 0    | 20    | lose    | 0        | 480         |
      | 1    | 20    | win     | 40       | 520         |
    And the house breaks even

  @EU-1499
  Scenario: A doubled hand is paid on the doubled wager
    Given "Alice" has bet 20 at seat 0
    And "Bob" has bet 20 at seat 1
    And the shoe begins "6♣ 3♣ 9♦ 5♣ 5♦ 7♠ K♥ 2♥"
    And the round has been dealt
    And "Alice" has doubled down at seat 0
    When "Bob" stands at seat 1
    Then the dealer reveals 7♠, draws 2♥ and stands on 18
    And round 1 is settled with:
      | seat | wager | outcome | returned | stack after |
      | 0    | 40    | win     | 80       | 540         |
      | 1    | 20    | lose    | 0        | 480         |
    And the house loses 20
    And the table "Main" ledger balances

  @EU-1500
  Scenario: The last action plays the dealer and settles in the same step
    Given "Alice" has bet 20 at seat 0
    And the shoe begins "10♣ 10♦ 9♥ 7♠"
    And the round has been dealt
    When "Alice" stands at seat 0
    Then the table records, as one step, that seat 0 stood, the dealer played and round 1 was settled
    And the table is ready for the next round's bets

  @EU-1501
  Scenario: The next round is numbered after the last
    Given round 1 has been played and settled at table "Main"
    When "Alice" bets 20 at seat 0
    Then the bet is for round 2

  # ==========================================================================
  # Reshuffling
  # ==========================================================================
  # Rule: AHR-4

  @EU-1502
  Scenario Outline: The shoe is replaced before a round that could run it out
    # A hand totalling 21 or less never holds more than 11 cards, so the
    # table needs 11 cards for each wagered seat and 11 for the dealer.
    Given table "Main"'s first shoe was shuffled from seed 42 and has <left> cards left
    And <bettors> players have bet 20
    When the round is dealt
    Then <outcome>

    Examples:
      | bettors | left | outcome                                                                     |
      | 1       | 21   | shoe 2 is shuffled from seed 13679457532755275413 before the cards are dealt |
      | 1       | 22   | the round is dealt from shoe 1                                              |
      | 2       | 32   | shoe 2 is shuffled from seed 13679457532755275413 before the cards are dealt |
      | 2       | 33   | the round is dealt from shoe 1                                              |

  @EU-1503
  Scenario: A replacement shoe deals in the order its seed decides
    Given table "Main"'s first shoe was shuffled from seed 1 and has 10 cards left
    And "Alice" has bet 20 at seat 0
    When the round is dealt
    Then shoe 2 is shuffled from seed 10451216379200822465 before the cards are dealt
    And seat 0 is dealt the first and third cards of that shoe

  # ==========================================================================
  # The table explains its own chips (L2)
  # ==========================================================================
  # Rule: L2

  @EU-1504
  Scenario Outline: Every round keeps the table's chips in balance
    Given table "Main"'s first shoe was shuffled from seed <seed>
    And "Alice" has bet 20 at seat 0
    And "Bob" has bet 30 at seat 1
    When the round is played with every player standing as soon as it is their turn
    Then round 1 is settled
    And the table "Main" ledger balanced after every step

    Examples:
      | seed |
      | 1    |
      | 2    |
      | 3    |
      | 4    |
      | 5    |
      | 6    |
      | 7    |
      | 8    |
      | 9    |
      | 10   |
      | 11   |
      | 42   |
