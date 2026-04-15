Feature: Tournament aggregate logic
  The Tournament aggregate manages a tournament's lifecycle, player registrations,
  blind level progression, and player eliminations. It's the source of truth for
  tournament configuration, who is registered, and current tournament state.

  # Why this aggregate exists:
  # - Tournaments need centralized registration management (capacity, eligibility)
  # - Blind levels must advance atomically (all tables see same level)
  # - Player elimination tracking determines finish positions and payouts
  # - Rebuy eligibility is tournament-level state (window, limits, stack threshold)
  #
  # Patterns enabled by this aggregate:
  # - Registration with capacity: EnrollPlayer checks max_players and registration
  #   status atomically. Same pattern as event ticket sales, course enrollment.
  # - Phase-based lifecycle: CREATED → REGISTRATION_OPEN → RUNNING → COMPLETED.
  #   Same pattern as any multi-phase process (order fulfillment, project workflow).
  # - Rebuy validation: Tournament owns eligibility rules (window, max rebuys,
  #   stack threshold). Aggregate decides; PM coordinates across domains.

  # ==========================================================================
  # Tournament Creation
  # ==========================================================================

  Scenario: Create a new tournament
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Sunday Million" buy-in 1000 and starting-stack 10000
    Then the result is a examples.TournamentCreated event
    And the tournament event has name "Sunday Million"
    And the tournament event has buy_in 1000
    And the tournament event has starting_stack 10000

  Scenario: Cannot create tournament twice
    Given a TournamentCreated event for "Sunday Million"
    When I handle a CreateTournament command with name "Sunday Million 2" buy-in 500 and starting-stack 5000
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already exists"

  Scenario: Cannot create tournament with invalid buy-in
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Free Roll" buy-in 0 and starting-stack 5000
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "positive"

  Scenario: Cannot create tournament with invalid starting stack
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Micro" buy-in 10 and starting-stack 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "positive"

  Scenario: Cannot create tournament with max_players less than 2
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Solo" buy-in 100 starting-stack 5000 and max-players 1
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "max_players"

  # ==========================================================================
  # Registration Management
  # ==========================================================================

  Scenario: Open registration for tournament
    Given a TournamentCreated event for "Sunday Million"
    When I handle an OpenRegistration command
    Then the result is a examples.RegistrationOpened event

  Scenario: Cannot open registration twice
    Given a TournamentCreated event for "Sunday Million"
    And a RegistrationOpened event
    When I handle an OpenRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already open"

  Scenario: Cannot open registration for running tournament
    Given a TournamentCreated event for "Sunday Million"
    And a RegistrationOpened event
    And a RegistrationClosed event
    And a TournamentStarted event
    When I handle an OpenRegistration command
    Then the command fails with status "FAILED_PRECONDITION"

  Scenario: Close registration
    Given a TournamentCreated event for "Sunday Million"
    And a RegistrationOpened event
    And 3 players enrolled
    When I handle a CloseRegistration command
    Then the result is a examples.RegistrationClosed event
    And the tournament event has total_registrations 3

  Scenario: Cannot close registration that is not open
    Given a TournamentCreated event for "Sunday Million"
    When I handle a CloseRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not open"

  # ==========================================================================
  # Player Enrollment (sent by Registration PM)
  # ==========================================================================

  Scenario: Enroll player in tournament
    Given a TournamentCreated event for "Sunday Million" with max-players 100
    And a RegistrationOpened event
    When I handle an EnrollPlayer command for player "player-1"
    Then the result is a examples.TournamentPlayerEnrolled event
    And the tournament event has fee_paid 1000
    And the tournament event has starting_stack 10000
    And the tournament event has registration_number 1

  Scenario: Second player gets registration number 2
    Given a TournamentCreated event for "Sunday Million" with max-players 100
    And a RegistrationOpened event
    And 1 player enrolled
    When I handle an EnrollPlayer command for player "player-2"
    Then the result is a examples.TournamentPlayerEnrolled event
    And the tournament event has registration_number 2

  Scenario: Cannot enroll when registration closed
    Given a TournamentCreated event for "Sunday Million"
    When I handle an EnrollPlayer command for player "player-1"
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason "closed"

  Scenario: Cannot enroll when tournament full
    Given a TournamentCreated event for "Heads Up" with max-players 2
    And a RegistrationOpened event
    And 2 players enrolled
    When I handle an EnrollPlayer command for player "player-3"
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason "full"

  Scenario: Cannot enroll same player twice
    Given a TournamentCreated event for "Sunday Million" with max-players 100
    And a RegistrationOpened event
    And player "player-1" enrolled
    When I handle an EnrollPlayer command for player "player-1"
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason "already_registered"

  # ==========================================================================
  # Rebuy Processing (sent by Rebuy PM)
  # ==========================================================================

  Scenario: Process rebuy for eligible player
    Given a running tournament with rebuys enabled max 3 cutoff level 4
    And the current blind level is 2
    And player "player-1" enrolled with 0 rebuys used
    When I handle a ProcessRebuy command for player "player-1"
    Then the result is a examples.RebuyProcessed event
    And the tournament event has rebuy_count 1

  Scenario: Deny rebuy when window closed
    Given a running tournament with rebuys enabled max 3 cutoff level 4
    And the current blind level is 5
    And player "player-1" enrolled with 0 rebuys used
    When I handle a ProcessRebuy command for player "player-1"
    Then the result is a examples.RebuyDenied event
    And the tournament event has reason "window_closed"

  Scenario: Deny rebuy when max reached
    Given a running tournament with rebuys enabled max 3 cutoff level 4
    And the current blind level is 2
    And player "player-1" enrolled with 3 rebuys used
    When I handle a ProcessRebuy command for player "player-1"
    Then the result is a examples.RebuyDenied event
    And the tournament event has reason "max_reached"

  Scenario: Deny rebuy for unregistered player
    Given a running tournament with rebuys enabled max 3 cutoff level 4
    When I handle a ProcessRebuy command for player "unknown-player"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not registered"

  # ==========================================================================
  # Blind Level Advancement
  # ==========================================================================

  Scenario: Advance blind level
    Given a running tournament with 3-level blind structure
    And the current blind level is 1
    When I handle an AdvanceBlindLevel command
    Then the result is a examples.BlindLevelAdvanced event
    And the tournament event has level 2

  Scenario: Cannot advance blind level when not running
    Given a TournamentCreated event for "Sunday Million"
    When I handle an AdvanceBlindLevel command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  # ==========================================================================
  # Player Elimination
  # ==========================================================================

  Scenario: Eliminate a player
    Given a running tournament with 5 players remaining
    And player "player-3" enrolled
    When I handle an EliminatePlayer command for player "player-3"
    Then the result is a examples.PlayerEliminated event
    And the tournament event has finish_position 5

  Scenario: Cannot eliminate unregistered player
    Given a running tournament with 5 players remaining
    When I handle an EliminatePlayer command for player "unknown"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not registered"

  Scenario: Cannot eliminate when not running
    Given a TournamentCreated event for "Sunday Million"
    When I handle an EliminatePlayer command for player "player-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  # ==========================================================================
  # Pause / Resume
  # ==========================================================================

  Scenario: Pause a running tournament
    Given a running tournament
    When I handle a PauseTournament command with reason "Dinner break"
    Then the result is a examples.TournamentPaused event
    And the tournament event has reason "Dinner break"

  Scenario: Resume a paused tournament
    Given a running tournament
    And a TournamentPaused event
    When I handle a ResumeTournament command
    Then the result is a examples.TournamentResumed event

  Scenario: Cannot pause when not running
    Given a TournamentCreated event for "Sunday Million"
    When I handle a PauseTournament command with reason "break"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================

  Scenario: Rebuild tournament state with registrations and eliminations
    Given a TournamentCreated event for "Sunday Million" with max-players 100
    And a RegistrationOpened event
    And 5 players enrolled
    And a RegistrationClosed event
    And a TournamentStarted event
    And player at position 1 eliminated
    When I rebuild the tournament state
    Then the tournament state has status "RUNNING"
    And the tournament state has 5 registered players
    And the tournament state has 4 players remaining
    And the tournament state has prize pool 5000
