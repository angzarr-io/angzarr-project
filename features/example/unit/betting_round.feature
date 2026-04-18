# Allocated: EU-0900 .. EU-0930
Feature: Betting round iteration logic
  The betting-round iteration must visit every active player after an
  intervening raise, regardless of earlier folds, and must terminate once
  all active bets are matched or the last aggressor has gone all-in.

  Why this matters:
  - A skipped player is a silent correctness bug: they lose the right to act
    mid-hand, which can cascade into incorrect pot settlement.
  - An infinite loop around an all-in aggressor blocks progression of the
    hand forever.

  These scenarios exercise ``BettingRoundTester`` + ``MockPlayer`` fixtures
  that mirror the real ``betting_round()`` driver from ``run_game.py``.

  # ==========================================================================
  # Correct Iteration After a Raise
  # ==========================================================================
  # A raise mid-round reopens action for every un-folded player behind it.
  # The iteration must return to seats that have not yet matched the new bet
  # (including seats that acted earlier, like the blinds).

  @EU-0900
  Scenario: Every seat acts after a preflop raise
    # Six-handed game, UTG at seat 3.
    # Dave (3) folds, Eve (4) folds, Frank (5) raises to 48, Alice (0) folds,
    # Bob (seat 1, SB) CALLS, Carol (seat 2, BB) CALLS. Round ends back at
    # the raiser. The earlier buggy implementation skipped Bob.
    Given a 6-player table with big_blind 10
    And blinds posted: "Bob" seat 1 amount 5 and "Carol" seat 2 amount 10
    And scripted actions:
      | action | amount |
      | FOLD   | 0      |
      | FOLD   | 0      |
      | RAISE  | 48     |
      | FOLD   | 0      |
      | CALL   | 43     |
      | CALL   | 38     |
    When I run a preflop betting round starting at seat 3
    Then the seats asked to act are [3, 4, 5, 0, 1, 2]

  @EU-0901
  Scenario: Small blind must act after a preflop raise
    # Simpler assertion than EU-0900: Bob (seat 1 SB) MUST appear in the
    # seats asked to act after Frank's raise.
    Given a 6-player table with big_blind 10
    And blinds posted: "Bob" seat 1 amount 5 and "Carol" seat 2 amount 10
    And scripted actions:
      | action | amount |
      | FOLD   | 0      |
      | FOLD   | 0      |
      | RAISE  | 48     |
      | FOLD   | 0      |
      | CALL   | 43     |
      | CALL   | 38     |
    When I run a preflop betting round starting at seat 3
    Then seat 1 is asked to act after seat 5

  @EU-0902
  Scenario: Raiser is not asked again when everyone only calls
    # Frank raises; Alice folds; Bob and Carol call. Frank must NOT be asked
    # to act a second time.
    Given a 6-player table with big_blind 10
    And blinds posted: "Bob" seat 1 amount 5 and "Carol" seat 2 amount 10
    And scripted actions:
      | action | amount |
      | FOLD   | 0      |
      | FOLD   | 0      |
      | RAISE  | 48     |
      | FOLD   | 0      |
      | CALL   | 43     |
      | CALL   | 38     |
      | FOLD   | 0      |
    When I run a preflop betting round starting at seat 3
    Then seat 5 is asked to act exactly 1 time

  # ==========================================================================
  # All-In Aggressor Termination
  # ==========================================================================
  # When the last raiser's raise is an all-in, they leave the active set.
  # The termination check must treat the aggressor as absent so the round
  # ends once the remaining players have called.

  @EU-0903
  Scenario: Round terminates after calls against an all-in aggressor
    # Four-handed; Eve (seat 2, stack 27) raises all-in to 27; Frank, Bob,
    # Dave call. The buggy implementation kept asking Frank after Eve's seat
    # left the active set.
    Given a table with players:
      | name  | seat | stack |
      | Bob   | 0    | 1000  |
      | Dave  | 1    | 1000  |
      | Eve   | 2    | 27    |
      | Frank | 3    | 1000  |
    And big_blind 10
    And blinds posted: "Bob" seat 0 amount 5 and "Dave" seat 1 amount 10
    And scripted actions:
      | action | amount |
      | RAISE  | 27     |
      | CALL   | 27     |
      | CALL   | 22     |
      | CALL   | 17     |
    When I run a preflop betting round starting at seat 2
    Then the seats asked to act are [2, 3, 0, 1]
    And seat 2 is all-in
    And seat 2 has stack 0
