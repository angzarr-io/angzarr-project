# Allocated: EU-1000 .. EU-1030 (in use: 1000..1007, 1010..1013)
Feature: Minimum raise tracking observable on TurnAssigned
  After each blind / action, the cluster emits TurnAssigned for the
  next-to-act seat with two raise-tracking fields:
    * ``amount_to_call``  — the absolute call level (== state.current_bet)
    * ``min_raise``       — the minimum legal raise increment
                            (== state.last_raise_increment)
  These two fields encode everything raise_tracking arithmetic needs to
  expose. ``min_raise_to`` (the absolute amount the next raise must
  reach) is the sum of the two.

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  # TDA Rule 43 (2024) — "A raise must be at least equal to the largest
  #   prior full bet or raise of the current betting round."
  # TDA Rule 47A (2024) — short all-in does not reopen betting; on a new
  #   street, the minimum bet is the BB and the minimum raise is the prior
  #   bet/raise on THAT street.

  # ==========================================================================
  # Initial State — After Blinds Are Posted — TDA Rule 43
  # ==========================================================================

  # Rule: TDA Rule 43 (2024) — a raise must be at least the largest prior full bet or raise of the current betting round
  @EU-1000
  @wip
  Scenario: After BB posts, the next actor faces a call of BB and a min raise of BB
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    Then the latest TurnAssigned has amount_to_call 10
    And the latest TurnAssigned has min_raise 10

  # ==========================================================================
  # Single Raise — TDA Rule 43
  # ==========================================================================

  @EU-1001
  @wip
  Scenario: A raise updates amount_to_call and min_raise to the raise increment
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 30
    Then the latest TurnAssigned has amount_to_call 30
    And the latest TurnAssigned has min_raise 20

  @EU-1002
  @wip
  Scenario: A re-raise updates min_raise to the larger increment
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 30
    And seat 1 raises to 80
    Then the latest TurnAssigned has amount_to_call 80
    And the latest TurnAssigned has min_raise 50

  @EU-1003
  @wip
  Scenario: Escalating re-raises track the largest increment
    Given a 4-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 3 raises to 30
    And seat 0 raises to 90
    And seat 1 raises to 210
    Then the latest TurnAssigned has amount_to_call 210
    And the latest TurnAssigned has min_raise 120

  # ==========================================================================
  # Non-Raise Actions — TDA Rule 43
  # ==========================================================================

  @EU-1004
  @wip
  Scenario: A call does not change min_raise
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 30
    And seat 1 calls
    Then the latest TurnAssigned has amount_to_call 30
    And the latest TurnAssigned has min_raise 20

  @EU-1005
  @wip
  Scenario: A below-min raise is rejected with BET_BELOW_MIN_RAISE / RAISE_BELOW_MIN
    # The cluster enforces the min raise; a raise smaller than the current
    # increment is rejected (it never shrinks the tracked increment).
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 30
    And seat 1 attempts to raise to 35
    Then the raise is refused because it is below the minimum

  # ==========================================================================
  # Cross-Round Reset — TDA Rule 47A
  # ==========================================================================
  # min_raise resets to the big blind on each new street.

  # Rule: TDA Rule 47A (2024) — on a new street the min raise resets to the prior bet/raise on that street; a short all-in does not reopen betting
  @EU-1006
  @wip
  Scenario: A new betting round resets min_raise to the big blind
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 150
    And seat 1 calls
    And seat 2 calls
    And the flop is dealt
    Then the latest TurnAssigned has amount_to_call 0
    And the latest TurnAssigned has min_raise 10

  @EU-1010
  @wip
  Scenario: First bet on a new street establishes the new min_raise
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 calls
    And seat 1 calls
    And seat 2 checks
    And the flop is dealt
    And seat 1 bets 25
    Then the latest TurnAssigned has amount_to_call 25
    And the latest TurnAssigned has min_raise 25

  @EU-1011
  @wip
  Scenario: A flop bet smaller than the prior preflop increment is allowed
    # Preflop raise increment was 140; on the flop the min increment resets
    # to BB. A flop bet of 25 is therefore legal.
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 150
    And seat 1 calls
    And seat 2 calls
    And the flop is dealt
    And seat 1 bets 25
    Then the latest TurnAssigned has amount_to_call 25
    And the latest TurnAssigned has min_raise 25

  @EU-1012
  @wip
  Scenario: A flop bet below the big blind is rejected
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 calls
    And seat 1 calls
    And seat 2 checks
    And the flop is dealt
    And seat 1 attempts to bet 5
    Then the bet is refused because it is below the minimum raise

  @EU-1013
  @wip
  Scenario: After a check-around, min_raise on the next street is still the big blind
    Given a 3-handed Texas Hold'em hand with big_blind 10
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 calls
    And seat 1 calls
    And seat 2 checks
    And the flop is dealt
    And seat 1 checks
    And seat 2 checks
    And seat 0 checks
    And the turn is dealt
    Then the latest TurnAssigned has amount_to_call 0
    And the latest TurnAssigned has min_raise 10

  # ==========================================================================
  # All-In Short Raise — TDA Rule 47A
  # ==========================================================================

  @EU-1007
  @wip
  Scenario: An all-in for less than the min raise updates current_bet but does not increase min_raise
    # Short all-in raises current_bet to the all-in level but does NOT
    # update min_raise — earlier bettors do not have action reopened.
    # Seat 1 has a 45-chip short stack: SB=5 posted leaves 40 behind, so
    # the subsequent ALL_IN puts in 40 (bringing seat 1's
    # bet_this_round to 45, current_bet to 45 once they're all-in).
    Given a 3-handed Texas Hold'em hand with big_blind 10 and stacks 10000, 45, 10000
    When SB at seat 1 and BB at seat 2 post blinds
    And seat 0 raises to 30
    And seat 1 goes all-in to 40
    Then the latest TurnAssigned has amount_to_call 45
    And the latest TurnAssigned has min_raise 20
