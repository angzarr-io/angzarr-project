# Allocated: EU-1000 .. EU-1030 (in use: 1000..1007, 1010..1013)
Feature: Minimum raise tracking arithmetic
  At every point in a hand, the minimum legal raise size depends on the
  previous bet/raise on this street. These scenarios pin down the
  arithmetic so the table and the player agree on what counts as a legal
  raise.

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  # Every scenario in this file expresses one or both of:
  #   TDA Rule 43 (2024) — "A raise must be at least equal to the largest
  #     prior full bet or raise of the current betting round." (See also
  #     TDA Rule 43 examples in the Illustration Addendum.)
  #   TDA Rule 47A (2024) — short all-in does not reopen betting; on a new
  #     street, the minimum bet is the BB and the minimum raise is the
  #     prior bet/raise on THAT street.
  # See features/example/RULES.md for the full rule cross-reference.

  # ==========================================================================
  # Initial State — After Blinds Are Posted — TDA Rule 43
  # ==========================================================================
  # Rule: TDA Rule 43 (2024) — initial min raise is the BB amount.

  @EU-1000
  Scenario: Initial min raise equals the big blind
    # After the blinds are posted, the first raise must be to at least
    # twice the big blind.
    Given the current bet is 10 and the last raise increment was 10
    When I compute the next legal raise minimum
    Then the minimum raise-to amount is 20

  # ==========================================================================
  # Single Raise — TDA Rule 43
  # ==========================================================================
  # Rule: TDA Rule 43 (2024) — the last raise increment tracks the largest
  # additional action; subsequent raises must equal or exceed it.

  @EU-1001
  Scenario: A raise updates the last raise increment when larger
    # Raising to 30 from a current bet of 10 is a 20-chip increment.
    Given the current bet is 10 and the last raise increment was 10
    When a player raises to 30
    Then the last raise increment is 20
    And the current bet is 30
    And the minimum raise-to amount is 50

  @EU-1002
  Scenario: A re-raise updates the last raise increment when larger
    Given the current bet is 10 and the last raise increment was 10
    When a player raises to 30
    And a player raises to 80
    Then the last raise increment is 50
    And the current bet is 80
    And the minimum raise-to amount is 130

  @EU-1003
  Scenario: Escalating re-raises track the largest increment
    # Initial BB=10. UTG raises to 30 (+20). SB re-raises to 90 (+60).
    # BB re-raises to 210 (+120). Next min raise is 210 + 120 = 330.
    Given the current bet is 10 and the last raise increment was 10
    When a player raises to 30
    And a player raises to 90
    And a player raises to 210
    Then the last raise increment is 120
    And the current bet is 210
    And the minimum raise-to amount is 330

  # ==========================================================================
  # Non-Raise Actions — TDA Rule 43
  # ==========================================================================
  # Rule: TDA Rule 43 (2024) — calls and below-increment raises do not
  # decrease the tracked increment.

  @EU-1004
  Scenario: A call does not affect the last raise increment
    Given the current bet is 30 and the last raise increment was 20
    When a player calls 30
    Then the last raise increment is 20
    And the current bet is 30
    And the minimum raise-to amount is 50

  @EU-1005
  Scenario: A smaller raise does not decrease the last raise increment
    # A below-increment raise never shrinks the tracked increment.
    Given the current bet is 100 and the last raise increment was 50
    When a below-increment raise of 30 is applied
    Then the last raise increment is 50
    And the minimum raise-to amount is 150

  # ==========================================================================
  # Cross-Round Reset — TDA Rule 47A "current betting round"
  # ==========================================================================
  # Rule: TDA Rule 47A (2024) — "the minimum raise is always the last full
  #       valid bet or raise of the round." The phrase "of the round"
  #       (i.e. the current street) means the increment resets between
  #       streets — preflop's increment does not carry over to the flop.
  # Rule: TDA Rule 43 (2024) — "A raise must be at least equal to the
  #       largest prior full bet or raise of the current betting round."
  #       (See Rule 43 examples in the Illustration Addendum confirming
  #       "current round" = "current street".)
  # Rule: WSOP §VIII NO-LIMIT (2025) — "The minimum bet is equal to the
  #       amount of the Big Blind" (per street).
  # The minimum bet on a NEW street is the big blind; the minimum raise
  # is the size of the previous bet/raise *on that street*. Both reset
  # between streets.

  @EU-1006
  Scenario: A new betting round resets the last raise increment to the big blind
    # Preflop ended with a large raise increment. At the start of the flop,
    # both the current bet and the raise increment reset so that a flop bet
    # of any amount at or above the big blind is legal.
    Given the current bet is 140, the last raise increment was 140, and the big blind is 10
    When a new betting round begins
    Then the current bet is 0
    And the last raise increment is 10

  @EU-1010
  Scenario: First bet on a new street establishes the new last raise increment
    # A flop bet of 25 establishes the increment at 25 (the size of the bet
    # itself, since the current bet was 0). The next raise must be at least
    # 25 more — i.e. raise-to 50.
    Given the current bet is 0 and the last raise increment is 10 on a new street
    When a player bets 25
    Then the last raise increment is 25
    And the current bet is 25
    And the minimum raise-to amount is 50

  @EU-1011
  Scenario: A flop bet smaller than the prior preflop increment is allowed
    # Preflop was BB=10, raised to 60, reraised to 200 (the raise increment
    # was 140 by the end of preflop). On the flop the minimum bet is the
    # big blind (10), NOT 140. A bet of 25 is legal.
    Given preflop ended with a last raise increment of 140 and big blind 10
    When a new betting round begins
    And a player bets 25
    Then the bet is accepted
    And the last raise increment is 25
    And the minimum raise-to amount is 50

  @EU-1012
  Scenario: The minimum bet on a new street is the big blind
    # A bet below the big blind is rejected (real poker NLHE convention).
    # At BB=10, a flop bet of 5 is illegal even though the current bet is 0.
    Given the current bet is 0 and the last raise increment is 10 on a new street with big blind 10
    When a player attempts to bet 5
    Then the bet is refused because it is below the minimum bet of 10

  @EU-1013
  Scenario: After a check-around, the last raise increment stays at the big blind
    # Checks don't change the increment. Going into the next street, the
    # increment is still the big blind.
    Given the current bet is 0 and the last raise increment is 10 on a new street with big blind 10
    When all active players check
    And the next betting round begins
    Then the last raise increment is 10

  # ==========================================================================
  # All-In Short Raise — TDA Rule 47A
  # ==========================================================================
  # Rule: TDA Rule 47A (2024) — "An all-in wager … totaling less than a full
  # bet or raise will not reopen betting for players who have already
  # acted."

  @EU-1007
  Scenario: An all-in for less than the min raise is allowed but does not reopen
    # If a player's stack can't cover the full minimum, they may go all-in
    # for less. This is allowed; it does not update the tracked increment
    # because it doesn't reopen action for earlier bettors.
    Given the current bet is 30 and the last raise increment was 20
    When a player goes all-in to 40
    Then the all-in amount is less than the minimum raise-to amount
