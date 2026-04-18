# Allocated: EU-1000 .. EU-1030
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
  # Cross-Round Persistence
  # ==========================================================================

  @EU-1006
  Scenario: A new betting round does not reset last_raise_increment
    # At the start of a post-flop round, current_bet resets to 0 but
    # last_raise_increment persists. A subsequent bet that exceeds the old
    # increment will grow it; a smaller bet will not shrink it.
    Given current_bet is 0 and last_raise_increment is 20
    When a player bets 25 on a new round
    Then last_raise_increment is 25

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
