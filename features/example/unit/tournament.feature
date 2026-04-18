# Allocated: EU-0800 .. EU-0830
# DOC: Unit scenarios for the Tournament aggregate (tournament/agg/handlers.py).

Feature: Tournament aggregate logic
  The Tournament aggregate manages tournament lifecycle, player enrollment,
  rebuys, eliminations, and pause/resume transitions. It's the source of
  truth for who is registered, how many chips are in play, and which
  tournament phase (created / registration / running / paused / completed)
  is currently active.

  # Why this aggregate exists:
  # - Tournaments have a strict lifecycle with guard-gated transitions
  #   (create -> open registration -> close -> run -> pause/resume -> complete)
  # - Enrollment has capacity and duplicate-prevention rules
  # - Rebuys and eliminations are only valid while the tournament is running
  # - Start requires a minimum number of registered players
  #
  # What breaks if this is wrong:
  # - Players could register in tournaments that are closed or full
  # - A tournament could start without enough participants
  # - Rebuys could be processed after the cutoff
  # - Pause/resume could flip state at the wrong time
  #
  # Patterns enabled by this aggregate:
  # - Lifecycle state machine: Each transition validates the current status
  #   before emitting an event. Same pattern applies to order workflow,
  #   subscription billing, and publication approval flows.
  # - Capacity + duplicate checks: Enrollment rules mirror waitlist and
  #   seat-reservation systems across any bounded-resource domain.
  # - Rejection-as-event: Bad enrollments emit TournamentEnrollmentRejected
  #   (a domain event) rather than raising, so the PM sees the outcome on
  #   the event stream. Rebuys follow the same shape with RebuyDenied.
  #
  # Why poker exercises these patterns well:
  # - Tournaments have clear, hard gates (registration open/closed, running)
  # - Capacity (max_players) and minimum start threshold (min_players) are
  #   obvious and easy to verify
  # - Rebuy rules combine state (running) with configuration (level cutoff,
  #   max rebuys) in a way that exercises both guards cleanly

  # ==========================================================================
  # Tournament Creation
  # ==========================================================================
  # Tournaments are created with core configuration: name, buy-in, stacks,
  # and player bounds. Validation rules reject empty names, non-positive
  # amounts, and min/max_player inconsistencies.

  @EU-0800
  Scenario: Create a tournament successfully
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    Then the result is a examples.TournamentCreated event
    And the tournament event has name "Test Tournament"
    And the tournament event has buy_in 100
    And the tournament event has starting_stack 1000

  @EU-0801
  Scenario: Cannot create tournament twice
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already exists"

  @EU-0802
  Scenario: Cannot create tournament with empty name
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "name is required"

  @EU-0803
  Scenario: Cannot create tournament with non-positive buy_in
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 0 starting_stack 1000 max_players 100 min_players 10
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "buy_in must be positive"

  @EU-0804
  Scenario: Cannot create tournament with non-positive starting_stack
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 0 max_players 100 min_players 10
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "starting_stack must be positive"

  @EU-0805
  Scenario: Cannot create tournament with min_players below 2
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 1
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "min_players must be at least 2"

  @EU-0806
  Scenario: Cannot create tournament with min_players exceeding max_players
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 5 min_players 10
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "min_players cannot exceed"

  # ==========================================================================
  # Open / Close Registration
  # ==========================================================================
  # Registration must be explicitly opened before players can enroll, and can
  # be closed before the tournament starts. Both transitions gate on the
  # current registration status.

  @EU-0807
  Scenario: Open registration successfully
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle an OpenRegistration command
    Then the result is a examples.RegistrationOpened event

  @EU-0808
  Scenario: Cannot open registration for nonexistent tournament
    Given no prior events for the tournament aggregate
    When I handle an OpenRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "does not exist"

  @EU-0809
  Scenario: Cannot open registration that is already open
    Given a tournament with registration open
    When I handle an OpenRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already open"

  @EU-0810
  Scenario: Close registration successfully
    Given a tournament with registration open
    When I handle a CloseRegistration command
    Then the result is a examples.RegistrationClosed event

  @EU-0811
  Scenario: Cannot close registration that is not open
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle a CloseRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not open"

  # ==========================================================================
  # Player Enrollment
  # ==========================================================================
  # Successful enrollment emits TournamentPlayerEnrolled with the buy-in as
  # fee_paid. Guard failures (empty player_root, registration closed, full
  # tournament, duplicate player) emit TournamentEnrollmentRejected instead
  # so the PM sees the outcome on the event stream.

  @EU-0812
  Scenario: Enroll a player successfully
    Given a tournament with registration open
    When I handle an EnrollPlayer command for player "player1" reservation "res1"
    Then the result is a examples.TournamentPlayerEnrolled event
    And the tournament event has player_root "player1"
    And the tournament event has fee_paid 100

  @EU-0813
  Scenario: Enrollment rejected with empty player_root
    Given a tournament with registration open
    When I handle an EnrollPlayer command for player "" reservation ""
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "player_root"

  @EU-0814
  Scenario: Enrollment rejected when registration is not open
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle an EnrollPlayer command for player "player1" reservation ""
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  @EU-0815
  Scenario: Enrollment rejected when tournament is full
    Given a tournament with max_players 2 and min_players 2 and registration open
    And a player "p1" enrolled
    And a player "p2" enrolled
    When I handle an EnrollPlayer command for player "p3" reservation ""
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "full"

  @EU-0816
  Scenario: Enrollment rejected for duplicate player
    Given a tournament with registration open
    And a player "player1" enrolled
    When I handle an EnrollPlayer command for player "player1" reservation ""
    Then the result is a examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "already registered"

  # ==========================================================================
  # Rebuy Processing
  # ==========================================================================
  # Rebuys only work while the tournament is running. Unregistered players
  # get a RebuyDenied event on the stream rather than a raised error.

  @EU-0817
  Scenario: Rebuy rejected when tournament is not running
    Given a tournament with registration open
    When I handle a ProcessRebuy command for player "p1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  @EU-0818
  Scenario: Rebuy denied for unregistered player
    Given a running tournament with min_players 2 and max_players 10 and 10 enrolled players
    When I handle a ProcessRebuy command for player "unknown"
    Then the result is a examples.RebuyDenied event
    And the tournament event has reason containing "not registered"

  # ==========================================================================
  # Player Elimination
  # ==========================================================================
  # Elimination requires the tournament to be running. Eliminating before
  # start is a guard-raised error.

  @EU-0819
  Scenario: Eliminate rejected when tournament is not running
    Given a tournament with registration open
    When I handle an EliminatePlayer command for player "p1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  # ==========================================================================
  # Pause / Resume
  # ==========================================================================
  # Pause gates on running; Resume gates on paused. Each transition asserts
  # that the tournament is in the expected prior phase.

  @EU-0820
  Scenario: Pause rejected when tournament is not running
    Given a tournament with registration open
    When I handle a PauseTournament command with reason "break"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  @EU-0821
  Scenario: Resume rejected when tournament is not paused
    Given a tournament with registration open
    When I handle a ResumeTournament command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not paused"

  # ==========================================================================
  # Start Tournament
  # ==========================================================================
  # Start requires open registration plus at least min_players enrolled.

  @EU-0822
  Scenario: Start tournament with enough players
    Given a tournament with min_players 2 and max_players 10 and registration open
    And a player "p1" enrolled
    And a player "p2" enrolled
    When I handle a StartTournament command
    Then the result is a examples.TournamentStarted event
    And the tournament event has total_players 2

  @EU-0823
  Scenario: Cannot start without enough players
    Given a tournament with min_players 2 and max_players 10 and registration open
    And a player "p1" enrolled
    When I handle a StartTournament command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Not enough players"
