# Allocated: EU-1000 .. EU-1030 (in use: 1000..1007, 1010..1013)
Feature: Minimum raise tracking arithmetic
  Client-side tracking of ``last_raise_increment`` must match the server's
  ``min_raise``. If they drift, the client will submit raises that the
  server rejects with messages like ``Raise must be at least N``.

  These scenarios exercise the raise-tracking arithmetic in isolation:
  pure math with no handlers, no state machine, no protocol. Think of
  this as a spec document for the client's raise-computation helpers.

  # ==========================================================================
  # Initial State — After Blinds Are Posted
  # ==========================================================================

  @EU-1000
  Scenario: Initial min raise equals the big blind
    # After SB/BB are posted, current_bet == BB and last_raise_increment == BB.
    # The first raise must therefore be TO at least 2 * BB.
    Given current_bet is 10 and last_raise_increment is 10
    When I compute the min_raise_to
    Then min_raise_to is 20

  # ==========================================================================
  # Single Raise
  # ==========================================================================

  @EU-1001
  Scenario: A raise updates last_raise_increment when larger
    # Raising TO 30 from a current_bet of 10 is a +20 increment.
    # The client tracks ``last_raise_increment = max(old, new_increment)``.
    Given current_bet is 10 and last_raise_increment is 10
    When a player raises to 30
    Then last_raise_increment is 20
    And current_bet is 30
    And min_raise_to is 50

  @EU-1002
  Scenario: A re-raise updates last_raise_increment when larger
    Given current_bet is 10 and last_raise_increment is 10
    When a player raises to 30
    And a player raises to 80
    Then last_raise_increment is 50
    And current_bet is 80
    And min_raise_to is 130

  @EU-1003
  Scenario: Escalating re-raises track the largest increment
    # Initial BB=10. UTG raises to 30 (+20). SB re-raises to 90 (+60).
    # BB re-raises to 210 (+120). Next min raise is 210 + 120 = 330.
    Given current_bet is 10 and last_raise_increment is 10
    When a player raises to 30
    And a player raises to 90
    And a player raises to 210
    Then last_raise_increment is 120
    And current_bet is 210
    And min_raise_to is 330

  # ==========================================================================
  # Non-Raise Actions
  # ==========================================================================

  @EU-1004
  Scenario: A call does not affect last_raise_increment
    Given current_bet is 30 and last_raise_increment is 20
    When a player calls 30
    Then last_raise_increment is 20
    And current_bet is 30
    And min_raise_to is 50

  @EU-1005
  Scenario: A smaller raise does not decrease last_raise_increment
    # Server uses max(), so a below-increment raise (also rejected at the
    # handler) never shrinks the tracked increment.
    Given current_bet is 100 and last_raise_increment is 50
    When a below-increment raise of increment 30 is applied
    Then last_raise_increment is 50
    And min_raise_to is 150

  # ==========================================================================
  # Cross-Round Reset
  # ==========================================================================
  # Real poker (NLHE / WSOP / standard cardroom): the minimum bet on a NEW
  # street is the big blind, and the minimum raise is the size of the
  # previous bet/raise *on that street*. Both reset between streets. The
  # legacy implementation that carried last_raise_increment across streets
  # produced spurious "Raise must be at least N" rejections after a large
  # preflop raise, which is not how real poker is played.

  @EU-1006
  Scenario: A new betting round resets last_raise_increment to the big blind
    # Preflop produced last_raise_increment=140. At the start of the flop,
    # current_bet resets to 0 (existing behaviour) AND last_raise_increment
    # resets to the BB amount, so a flop bet of 25 is legal at BB=10.
    Given current_bet is 140 and last_raise_increment is 140 and big_blind is 10
    When a new betting round begins
    Then current_bet is 0
    And last_raise_increment is 10

  @EU-1010
  Scenario: First bet on a new street establishes the new last_raise_increment
    # A flop bet of 25 sets last_raise_increment=25 (the size of the bet
    # itself, since current_bet was 0). The next raise must be at least 25
    # more — i.e. raise-to 50.
    Given current_bet is 0 and last_raise_increment is 10 on a new street
    When a player bets 25
    Then last_raise_increment is 25
    And current_bet is 25
    And min_raise_to is 50

  @EU-1011
  Scenario: A flop bet smaller than the prior preflop increment is allowed
    # Preflop was BB=10, raised to 60, reraised to 200 (last_raise_increment
    # was 140 by end of preflop). On the flop the minimum bet is BB (10),
    # NOT 140. A bet of 25 is legal.
    Given preflop ended with last_raise_increment 140 and big_blind 10
    When a new betting round begins
    And a player bets 25
    Then the bet is accepted
    And last_raise_increment is 25
    And min_raise_to is 50

  @EU-1012
  Scenario: The minimum bet on a new street is the big blind
    # A bet below BB is rejected (real poker NLHE convention). At BB=10,
    # a flop bet of 5 is illegal even though current_bet is 0. After the
    # per-street reset (EU-1006), last_raise_increment == BB, so the
    # existing BET_BELOW_MIN_RAISE rejection covers this case directly.
    Given current_bet is 0 and last_raise_increment is 10 on a new street with big_blind 10
    When a player attempts to bet 5
    Then the bet is rejected with code "BET_BELOW_MIN_RAISE"
    And the rejection field "got" equals "5"
    And the rejection field "bound" equals "10"

  @EU-1013
  Scenario: After a check-around, last_raise_increment stays at the big blind
    # Checks don't change last_raise_increment. Going into the next street,
    # the increment is still BB.
    Given current_bet is 0 and last_raise_increment is 10 on a new street with big_blind 10
    When all active players check
    And the next betting round begins
    Then last_raise_increment is 10

  # ==========================================================================
  # All-In Short Raise
  # ==========================================================================

  @EU-1007
  Scenario: An all-in for less than the min raise is allowed but does not reopen
    # If a player's stack can't cover the full minimum, they may go all-in
    # for less. This is allowed by the server; it does NOT update
    # last_raise_increment (tested by the broader suite) because it doesn't
    # reopen action for earlier bettors.
    Given current_bet is 30 and last_raise_increment is 20
    When a player goes all-in to 40
    Then the all-in amount is less than min_raise_to
