# Allocated: EU-0800 .. EU-0865
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
    Then the result is a angzarr_client.proto.examples.TournamentCreated event
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
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "name is required"

  @EU-0803
  Scenario: Cannot create tournament with non-positive buy_in
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 0 starting_stack 1000 max_players 100 min_players 10
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "buy_in must be positive"

  @EU-0804
  Scenario: Cannot create tournament with non-positive starting_stack
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 0 max_players 100 min_players 10
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "starting_stack must be positive"

  @EU-0805
  Scenario: Cannot create tournament with min_players below 2
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 1
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "min_players must be at least 2"

  @EU-0806
  Scenario: Cannot create tournament with min_players exceeding max_players
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 5 min_players 10
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "MIN_PLAYERS_EXCEEDS_MAX"
    And the rejection field "lhs" equals "10"
    And the rejection field "rhs" equals "5"

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
    Then the result is a angzarr_client.proto.examples.RegistrationOpened event

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
    Then the result is a angzarr_client.proto.examples.RegistrationClosed event

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
    Then the result is a angzarr_client.proto.examples.TournamentPlayerEnrolled event
    And the tournament event has player_root "player1"
    And the tournament event has fee_paid 100

  @EU-0813
  Scenario: Enrollment rejected with empty player_root
    Given a tournament with registration open
    When I handle an EnrollPlayer command for player "" reservation ""
    Then the result is a angzarr_client.proto.examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "player_root"

  @EU-0814
  Scenario: Enrollment rejected when registration is not open
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle an EnrollPlayer command for player "player1" reservation ""
    Then the result is a angzarr_client.proto.examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  @EU-0815
  Scenario: Enrollment rejected when tournament is full
    Given a tournament with max_players 2 and min_players 2 and registration open
    And a player "p1" enrolled
    And a player "p2" enrolled
    When I handle an EnrollPlayer command for player "p3" reservation ""
    Then the result is a angzarr_client.proto.examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "full"

  @EU-0816
  Scenario: Enrollment rejected for duplicate player
    Given a tournament with registration open
    And a player "player1" enrolled
    When I handle an EnrollPlayer command for player "player1" reservation ""
    Then the result is a angzarr_client.proto.examples.TournamentEnrollmentRejected event
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
    Then the result is a angzarr_client.proto.examples.RebuyDenied event
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
    Then the result is a angzarr_client.proto.examples.TournamentStarted event
    And the tournament event has total_players 2

  @EU-0823
  Scenario: Cannot start without enough players
    Given a tournament with min_players 2 and max_players 10 and registration open
    And a player "p1" enrolled
    When I handle a StartTournament command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Not enough players"

  # ==========================================================================
  # EnrollPlayer — Non-existent Tournament
  # ==========================================================================

  @EU-0824
  Scenario: EnrollPlayer rejects when the tournament does not exist
    Given no prior events for the tournament aggregate
    When I handle an EnrollPlayer command for player "p1" reservation ""
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Tournament does not exist"

  # ==========================================================================
  # AdvanceBlindLevel — Success and Not-Running Rejection
  # ==========================================================================

  @EU-0825
  Scenario: AdvanceBlindLevel on a running tournament emits BlindLevelAdvanced
    Given a running tournament with a two-level blind structure
    When I handle an AdvanceBlindLevel command
    Then the result is a angzarr_client.proto.examples.BlindLevelAdvanced event
    And the tournament event has blind level 2
    And the tournament event has small_blind 50
    And the tournament event has ante 10

  @EU-0826
  Scenario: AdvanceBlindLevel rejects when tournament is not running
    Given a tournament with registration open
    When I handle an AdvanceBlindLevel command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not running"

  # IDs renumbered to EU-0855/0856; the original numbers collided with the
  # Pause/Resume scenarios further down. EU-0842's comment block has been
  # updated to reference the new ID.
  @EU-0855
  Scenario: AdvanceBlindLevel rejects when blind structure is exhausted
    # current_level is at the final defined level (2); advancing past it would
    # write a BlindLevelAdvanced event with level 3 the structure does not
    # define. Reject so the operator decides explicitly (extend the structure
    # or end the tournament).
    Given a running tournament at the final defined blind level
    When I handle an AdvanceBlindLevel command
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "BLIND_STRUCTURE_EXHAUSTED"
    And the rejection field "current" equals "2"
    And the rejection field "max_value" equals "2"

  @EU-0856
  Scenario: AdvanceBlindLevel rejects when no blind structure is defined
    # Empty structure folds into BLIND_STRUCTURE_EXHAUSTED with max=0.
    Given a running tournament with no blind structure
    When I handle an AdvanceBlindLevel command
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "BLIND_STRUCTURE_EXHAUSTED"
    And the rejection field "max_value" equals "0"

  # ==========================================================================
  # EliminatePlayer — Success and Unregistered Rejection
  # ==========================================================================

  @EU-0827
  Scenario: EliminatePlayer emits PlayerEliminated with the supplied hand_root
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle an EliminatePlayer command for player "p0" with hand_root "hand-01"
    Then the result is a angzarr_client.proto.examples.PlayerEliminated event
    And the tournament event has hand_root "hand-01"

  @EU-0828
  Scenario: EliminatePlayer rejects when the player is not registered
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle an EliminatePlayer command for player "ghost"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not registered"

  # ==========================================================================
  # PauseTournament — Success and Already-Paused Rejection
  # ==========================================================================

  @EU-0829
  Scenario: PauseTournament on a running tournament emits TournamentPaused
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle a PauseTournament command with reason "dinner break"
    Then the result is a angzarr_client.proto.examples.TournamentPaused event
    And the tournament event has reason "dinner break"

  @EU-0830
  Scenario: PauseTournament rejects when tournament is already paused
    Given a paused tournament
    When I handle a PauseTournament command with reason "again"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already paused"

  # ==========================================================================
  # ResumeTournament — Success
  # ==========================================================================

  @EU-0831
  Scenario: ResumeTournament on a paused tournament emits TournamentResumed
    Given a paused tournament
    When I handle a ResumeTournament command
    Then the result is a angzarr_client.proto.examples.TournamentResumed event

  # ==========================================================================
  # OpenRegistration — Running-Tournament Rejection
  # ==========================================================================

  @EU-0832
  Scenario: OpenRegistration rejects when tournament is running
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle an OpenRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "running tournament"

  # ==========================================================================
  # CloseRegistration — total_registrations count
  # ==========================================================================

  @EU-0833
  Scenario: CloseRegistration emits RegistrationClosed with the registered count
    Given a tournament with registration open
    And a player "p1" enrolled
    When I handle a CloseRegistration command
    Then the result is a angzarr_client.proto.examples.RegistrationClosed event
    And the tournament event has total_registrations 1

  # ==========================================================================
  # ProcessRebuy — Success, Missing Tournament, Disabled Rebuys
  # ==========================================================================

  @EU-0834
  Scenario: ProcessRebuy emits RebuyProcessed for an enrolled player with rebuys enabled
    Given a running tournament with rebuys enabled and 1 enrolled player
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyProcessed event
    And the tournament event has rebuy_cost 100
    And the tournament event has chips_added 1000
    And the tournament event has rebuy_count 1

  @EU-0835
  Scenario: ProcessRebuy rejects when the tournament does not exist
    Given no prior events for the tournament aggregate
    When I handle a ProcessRebuy command for player "p0"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "does not exist"

  @EU-0836
  Scenario: ProcessRebuy emits RebuyDenied when rebuys are not enabled
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyDenied event
    And the tournament event has reason containing "not enabled"

  # ==========================================================================
  # ProcessRebuy — Config Threshold Variations
  # ==========================================================================
  # can_rebuy() combines state (running) with config (enabled / cutoff_level /
  # max_rebuys) — each threshold gets its own denial/allow scenario.

  @EU-0837
  Scenario: ProcessRebuy emits RebuyDenied when rebuys are disabled in config
    Given a running tournament with rebuys disabled and 1 enrolled player
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyDenied event
    And the tournament event has reason containing "not enabled"

  @EU-0838
  Scenario: ProcessRebuy emits RebuyDenied when current level is past the cutoff
    Given a running tournament with rebuy cutoff 2 and 1 enrolled player at level 5
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyDenied event
    And the tournament event has reason containing "closed"

  @EU-0839
  Scenario: ProcessRebuy emits RebuyDenied when player has reached max rebuys
    Given a running tournament with max_rebuys 2 and player "p0" who has used 2 rebuys
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyDenied event
    And the tournament event has reason containing "Maximum"

  @EU-0840
  Scenario: ProcessRebuy succeeds when rebuy_level_cutoff is 0 (cutoff check disabled)
    Given a running tournament with rebuy cutoff 0 and 1 enrolled player at level 99
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyProcessed event
    And the tournament event has rebuy_count 1

  @EU-0841
  Scenario: ProcessRebuy succeeds when max_rebuys is 0 (unlimited rebuys)
    Given a running tournament with max_rebuys 0 and player "p0" who has used 100 rebuys
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.RebuyProcessed event

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # Tournament state is rebuilt by replaying all events in order. These
  # scenarios exercise each apply_* function: identity, lifecycle transitions,
  # no-ops (closed/rejected/denied), and cumulative updates (pool/level/remaining).

  @EU-0842
  Scenario: Rebuild state from TournamentCreated sets identity and initial level
    # blind_structure is preserved as supplied — when the create event omits
    # one, the rebuilt state has no levels and AdvanceBlindLevel rejects with
    # BLIND_STRUCTURE_EXHAUSTED (see EU-0856).
    Given a TournamentCreated event for "Spring Classic" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    When I rebuild the tournament state
    Then the tournament state has tournament_id "tournament_Spring Classic"
    And the tournament state has name "Spring Classic"
    And the tournament state has status "Created"
    And the tournament state has buy_in 500
    And the tournament state has starting_stack 10000
    And the tournament state has max_players 9
    And the tournament state has min_players 2
    And the tournament state has current_level 1
    And the tournament state has blind_structure count 0

  @EU-0843
  Scenario: Rebuild state after RegistrationOpened transitions status
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    When I rebuild the tournament state
    Then the tournament state has status "RegistrationOpen"

  @EU-0844
  Scenario: Rebuild state after RegistrationClosed leaves pool and count unchanged
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    And a TournamentPlayerEnrolled event for player "p1" with fee_paid 500
    And a RegistrationClosed event
    When I rebuild the tournament state
    Then the tournament state has status "RegistrationOpen"
    And the tournament state has total_prize_pool 500
    And the tournament state has registered_players count 1
    And the tournament state has players_remaining 1

  @EU-0845
  Scenario: Rebuild state after TournamentPlayerEnrolled adds registration and grows pool
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    And a TournamentPlayerEnrolled event for player "p1" with fee_paid 500
    When I rebuild the tournament state
    Then the tournament state has registered_players count 1
    And the tournament state has total_prize_pool 500
    And the tournament state has players_remaining 1
    And the tournament state has rebuys_used 0 for player "p1"

  @EU-0846
  Scenario: Rebuild state after TournamentEnrollmentRejected leaves pool and count unchanged
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    And a TournamentPlayerEnrolled event for player "p1" with fee_paid 500
    And a TournamentEnrollmentRejected event for player "p2" with reason "full"
    When I rebuild the tournament state
    Then the tournament state has total_prize_pool 500
    And the tournament state has registered_players count 1
    And the tournament state has players_remaining 1

  @EU-0847
  Scenario: Rebuild state after RebuyProcessed for unknown player still grows pool
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RebuyProcessed event for player "ghost" with rebuy_cost 77 rebuy_count 1
    When I rebuild the tournament state
    Then the tournament state has total_prize_pool 77
    And the tournament state has registered_players count 0

  @EU-0848
  Scenario: Rebuild state after RebuyDenied is a no-op
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    And a TournamentPlayerEnrolled event for player "p1" with fee_paid 500
    And a RebuyDenied event for player "p1" with reason "max_reached"
    When I rebuild the tournament state
    Then the tournament state has total_prize_pool 500
    And the tournament state has registered_players count 1

  @EU-0849
  Scenario: Rebuild state after BlindLevelAdvanced updates current_level
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a BlindLevelAdvanced event to level 7
    When I rebuild the tournament state
    Then the tournament state has current_level 7

  @EU-0850
  Scenario: Rebuild state after PlayerEliminated removes entry and decrements remaining
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    And a TournamentPlayerEnrolled event for player "p1" with fee_paid 500
    And a TournamentPlayerEnrolled event for player "p2" with fee_paid 500
    And a PlayerEliminated event for player "p1"
    When I rebuild the tournament state
    Then the tournament state has registered_players count 1
    And the tournament state has players_remaining 1
    And the tournament state has no registered player "p1"

  @EU-0851
  Scenario: Rebuild state after TournamentPaused transitions to Paused
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a TournamentPaused event
    When I rebuild the tournament state
    Then the tournament state has status "Paused"

  @EU-0852
  Scenario: Rebuild state after TournamentResumed transitions to Running
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a TournamentPaused event
    And a TournamentResumed event
    When I rebuild the tournament state
    Then the tournament state has status "Running"

  @EU-0853
  Scenario: Rebuild state after TournamentCompleted transitions to Completed
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a TournamentCompleted event
    When I rebuild the tournament state
    Then the tournament state has status "Completed"

  @EU-0854
  Scenario: Rebuild state with two RebuyProcessed events accumulates rebuys_used and prize pool
    Given a TournamentCreated event for "Spring" with buy_in 500 starting_stack 10000 max_players 9 min_players 2
    And a RegistrationOpened event
    And a TournamentPlayerEnrolled event for player "p1" with fee_paid 500
    And a RebuyProcessed event for player "p1" with rebuy_cost 100 rebuy_count 1
    And a RebuyProcessed event for player "p1" with rebuy_cost 150 rebuy_count 2
    When I rebuild the tournament state
    Then the tournament state has total_prize_pool 750
    And the tournament state has rebuys_used 2 for player "p1"

  # ==========================================================================
  # Late Registration
  # ==========================================================================
  # Real tournaments (TDA Rule 30) keep registration open for several blind
  # levels into running play. The previously implicit rule "TournamentStarted
  # closes registration" was a real-rule violation: registration must remain
  # open until either the configured cutoff level or an explicit
  # CloseRegistration. These scenarios pin the late-registration surface.

  @EU-0857
  Scenario: EnrollPlayer succeeds against a Running tournament when registration is still open
    # Tournament starts with min_players=2 enrolled. A third player registers
    # AFTER the start while registration is still open. They are enrolled and
    # added to the prize pool.
    Given a running tournament with registration open and 2 enrolled players
    When I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.TournamentPlayerEnrolled event
    And the tournament event has player_root "p3"
    And the tournament event has fee_paid 100
    And the tournament state has registered_players count 3
    And the tournament state has players_remaining 3

  @EU-0858
  Scenario: Late-registered player receives the configured starting stack
    # Late entries get the FULL starting stack regardless of how much is
    # already in play (TDA Rule 30 — late registrants do not receive a
    # discounted stack). Pin starting_stack on enrollment.
    Given a running tournament with starting_stack 1500, registration open, and 2 enrolled players
    When I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.TournamentPlayerEnrolled event
    And the tournament event has starting_stack 1500

  @EU-0859
  Scenario: Registration auto-closes when the cutoff level is reached
    # Tournaments configure a registration_cutoff_level. When the tournament
    # advances to a level past the cutoff, registration auto-closes and a
    # subsequent enrollment is rejected with the "not open" reason — same
    # rejection path as an explicit CloseRegistration.
    Given a running tournament with registration_cutoff_level 3 at level 4 and 2 enrolled players
    When I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  @EU-0860
  Scenario: Explicit CloseRegistration during a running tournament prevents further enrollment
    # Operators can close registration manually (e.g. after announcing the
    # late-reg deadline). Enrollments after that are rejected even though
    # the tournament is still running.
    Given a running tournament with 2 enrolled players
    When I handle a CloseRegistration command
    And I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  # ==========================================================================
  # Multi-place Payout
  # ==========================================================================
  # Real tournaments (TDA Rule 14, WSOP standard) pay multiple finishing
  # positions on a published payout schedule. The proto's TournamentResult
  # already carries (position, player_root, payout) — these scenarios pin
  # the distribution. The payout schedule is supplied to CompleteTournament
  # (or pre-configured at create time); the aggregate verifies payouts sum
  # to total_prize_pool.

  @EU-0861
  Scenario: CompleteTournament emits results for the top-N finishers per the payout schedule
    # 9-player $500 buy-in. Pool = 4500. Schedule pays top 3 at 50/30/20.
    Given a running tournament "Spring" with total_prize_pool 4500 and 9 enrolled players
    And a payout_structure paying positions 1,2,3 at percentages 50,30,20
    And finishing order "p1,p2,p3,p4,p5,p6,p7,p8,p9"
    When I handle a CompleteTournament command with winner "p1"
    Then the result is a angzarr_client.proto.examples.TournamentCompleted event
    And the tournament event has winner_root "p1"
    And the tournament event has 3 results
    And TournamentResult 0 has position 1 player_root "p1" payout 2250
    And TournamentResult 1 has position 2 player_root "p2" payout 1350
    And TournamentResult 2 has position 3 player_root "p3" payout 900

  @EU-0862
  Scenario: Sum of payouts equals total_prize_pool
    # The aggregate must reject a TournamentCompleted whose payouts do not
    # sum to the prize pool. This guards the chip ledger from drift when
    # the payout schedule and pool are out of sync.
    Given a running tournament "Spring" with total_prize_pool 1000 and 5 enrolled players
    And a payout_structure paying positions 1,2 at percentages 50,30
    When I handle a CompleteTournament command with winner "p1" and finishing order "p1,p2,p3,p4,p5"
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "PAYOUTS_DO_NOT_SUM_TO_POOL"
    And the rejection field "got" equals "800"
    And the rejection field "bound" equals "1000"

  @EU-0863
  Scenario: Bubble — the player eliminated immediately before the money receives no payout
    # 10-player tournament paying top 3. The 4th-place finisher is the
    # "bubble" — they are recorded in finishing order but get no payout
    # entry. Only positions 1..3 appear in TournamentResult.
    Given a running tournament "Spring" with total_prize_pool 1000 and 10 enrolled players
    And a payout_structure paying positions 1,2,3 at percentages 50,30,20
    And finishing order "p1,p2,p3,p4,p5,p6,p7,p8,p9,p10"
    When I handle a CompleteTournament command with winner "p1"
    Then the result is a angzarr_client.proto.examples.TournamentCompleted event
    And the tournament event has 3 results
    And no TournamentResult has player_root "p4"

  @EU-0864
  Scenario: Heads-up split when the payout schedule pays first and second equally
    # Some tournaments allow a heads-up "chop" — payouts to top 2 at
    # configurable percentages (e.g. 50/50 if both stacks are equal at the
    # heads-up start). The aggregate just enforces the schedule it is given.
    Given a running tournament "Spring" with total_prize_pool 1000 and 2 enrolled players
    And a payout_structure paying positions 1,2 at percentages 50,50
    And finishing order "p1,p2"
    When I handle a CompleteTournament command with winner "p1"
    Then the result is a angzarr_client.proto.examples.TournamentCompleted event
    And the tournament event has 2 results
    And TournamentResult 0 has position 1 player_root "p1" payout 500
    And TournamentResult 1 has position 2 player_root "p2" payout 500

  @EU-0865
  Scenario: CompleteTournament rejects when the supplied finishing order is shorter than the paid positions
    # Schedule pays top 3 but only 2 finishing positions are supplied.
    # Reject so the operator decides explicitly (extend the order or trim
    # the schedule).
    Given a running tournament "Spring" with total_prize_pool 1000 and 5 enrolled players
    And a payout_structure paying positions 1,2,3 at percentages 50,30,20
    And finishing order "p1,p2"
    When I handle a CompleteTournament command with winner "p1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "FINISHING_ORDER_SHORTER_THAN_PAYOUT_POSITIONS"
    And the rejection field "got" equals "2"
    And the rejection field "bound" equals "3"
