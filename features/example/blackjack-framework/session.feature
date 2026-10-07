# Allocated: EU-1580 .. EU-1589
Feature: A whole session in one process
  Every component of the example — wallet, table, buy-in process, the four
  translators and the ledger — wired together in one process and driven
  through real sessions. This is where the money rules are checked across
  both sides at once.

  Why this matters:
  - every transfer between a wallet and a table is recorded once on each
    side: a seat with its spent buy-in, chips added with their settled
    top-up, a cash-out with its credit (ledger rule L3)
  - when the session is quiet, everything in wallets, on tables and won by
    the house equals deposits minus withdrawals (ledger rule L4)
  - refusals unwind completely, leaving nothing held anywhere

  Background:
    Given all example components are running in one process
    And table "Main" with 3 seats, 1 deck, bets from 10 to 100 and buy-ins from 100 to 1000 was created with shoe seed 2

  @EU-1580
  Scenario: A two-player session from deposit to cash-out balances
    Given "Alice" and "Bob" are registered and have each deposited 1000
    When the session is played:
      | step                                                      |
      | "Alice" buys in at seat 0 of "Main" for 500               |
      | "Bob" buys in at seat 1 of "Main" for 500                 |
      | "Alice" tops up 100 at "Main"                             |
      | "Alice" bets 20 and "Bob" bets 30                         |
      | the round is dealt and every player stands on their turn  |
      | "Alice" and "Bob" leave "Main"                            |
    Then round 1 was settled with "Alice" winning 20 and "Bob" winning 30
    And "Alice" has a bankroll of 1020 and "Bob" has a bankroll of 1030
    And table "Main" has a house result of -50 and no one seated
    And every transfer between a wallet and table "Main" was recorded once on each side
    And the ledger reports the money as balanced
    And the ledger's totals match a recount of every wallet and table

  @EU-1581
  Scenario: Delivering every message twice records each transfer once
    Given "Alice" is registered and has deposited 1000
    And every message between components is delivered twice
    When the session is played:
      | step                                          |
      | "Alice" buys in at seat 0 of "Main" for 500   |
      | "Alice" tops up 100 at "Main"                 |
      | "Alice" leaves "Main"                         |
    Then "Alice" has a bankroll of 1000
    And every transfer between a wallet and table "Main" was recorded once on each side
    And the ledger reports the money as balanced

  @EU-1582
  Scenario: A buy-in the wallet cannot fund leaves nothing behind
    Given "Carol" is registered and has deposited 300
    When "Carol" buys in at seat 2 of "Main" for 500
    Then the buy-in fails because the funds are not available
    And seat 2 at table "Main" is free
    And "Carol" has a bankroll of 300 with 300 available
    And the ledger reports the money as balanced

  @EU-1583
  Scenario: A top-up refused during a round leaves nothing held
    Given "Alice" is registered and has deposited 1000
    And "Alice" has bought in at seat 0 of "Main" for 500
    And "Alice" has bet 20 and the round has been dealt
    When "Alice" tops up 100 at "Main"
    Then the top-up is refused because a wager is in play
    And "Alice" has a bankroll of 500 with 500 available
    And "Alice" has a stack of 480 at table "Main"
    And no chips were added at table "Main"
    And the ledger reports nothing in flight

  @EU-1584
  Scenario: Two buy-ins for one player seat them once and release the other
    Given "Alice" is registered and has deposited 1000
    And "Alice" has asked for seat 0 of "Main" for 400 and seat 1 of "Main" for 400, and both seats and both holds are in place
    When both buy-ins carry on, seat 0's first
    Then "Alice" is seated at seat 0 of table "Main" with a stack of 400
    And seat 1 at table "Main" is free
    And "Alice" has a bankroll of 600 with 600 available
    And every transfer between a wallet and table "Main" was recorded once on each side
    And the ledger reports the money as balanced
