# Allocated: EU-0800 .. EU-0865, EU-1151, EU-1160 .. EU-1162,
#            EU-1190 .. EU-1192, EU-1310 .. EU-1317,
#            EU-1370 .. EU-1376 (TDA RP / WSOP gap scenarios)
# DOC: Unit scenarios for the Tournament aggregate (tournament/agg/handlers.py).

Feature: Tournament aggregate logic
  The Tournament aggregate manages tournament lifecycle, player enrollment,
  rebuys, eliminations, and pause/resume transitions. It's the source of
  truth for who is registered, how many chips are in play, and which
  tournament phase (created / registration / running / paused / completed)
  is currently active.

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  #   TDA       = Poker Tournament Directors Association Rules, 2024 v1.0
  #               (Oct 9, 2024). Canonical at https://www.pokertda.com/.
  #               Rule numbers refer to the longform document.
  #   TDA-RP    = TDA Recommended Procedures (longform addendum).
  #   WSOP      = World Series of Poker Official Tournament Rules, 2025.
  #               Canonical at https://www.wsop.com/.
  # See angzarr docs site or features/example/RULES.md for the full
  # cross-reference between scenarios and rule sources.

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
  # Rule: WSOP §I-1, §I-2 (2025) — tournament event configuration: buy-in,
  #       starting stack, structure sheet defines payout / blind structure.
  # (Framework: configuration validation. The min/max_players bounds are
  # universal poker requirements — at least 2 to deal a hand.)
  # Tournaments are created with core configuration: name, buy-in, stacks,
  # and player bounds. Validation rules reject empty names, non-positive
  # amounts, and min/max_player inconsistencies.

  @EU-0800
  Scenario: Create a tournament successfully
    Given no prior events for the tournament aggregate
    When I handle a CreateTournament command with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    Then the result is a angzarr_client.proto.examples.v1.TournamentCreated event
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
  # Rule: WSOP §I-12 (2025) — late registration closes at end of level
  #       specified on the structure sheet.
  # Rule: TDA Rule 8 (2024) — late registrants get full stacks; details
  #       per the late-registration scenarios further down.
  # (Framework: state-machine transitions for registration lifecycle.)
  # Registration must be explicitly opened before players can enroll, and can
  # be closed before the tournament starts. Both transitions gate on the
  # current registration status.

  @EU-0807
  Scenario: Open registration successfully
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle an OpenRegistration command
    Then the result is a angzarr_client.proto.examples.v1.RegistrationOpened event

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
    Then the result is a angzarr_client.proto.examples.v1.RegistrationClosed event

  @EU-0811
  Scenario: Cannot close registration that is not open
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle a CloseRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not open"

  # ==========================================================================
  # Player Enrollment
  # ==========================================================================
  # Rule: WSOP §I-1, §I-3 (2025) — registration via in-person or online
  #       methods; participant pays buy-in to enter prize pool.
  # Rule: WSOP §I-2, §I-7 (2025) — capacity controls + entry refusal at
  #       host discretion (mapped here to "tournament full" rejection).
  # Successful enrollment emits TournamentPlayerEnrolled with the buy-in as
  # fee_paid. Guard failures (empty player_root, registration closed, full
  # tournament, duplicate player) emit TournamentEnrollmentRejected instead
  # so the PM sees the outcome on the event stream.

  @EU-0812
  Scenario: Enroll a player successfully
    Given a tournament with registration open
    When I handle an EnrollPlayer command for player "player1" reservation "res1"
    Then the result is a angzarr_client.proto.examples.v1.TournamentPlayerEnrolled event
    And the tournament event has player_root "player1"
    And the tournament event has fee_paid 100

  @EU-0813
  Scenario: Enrollment rejected with empty player_root
    Given a tournament with registration open
    When I handle an EnrollPlayer command for player "" reservation ""
    Then the result is a angzarr_client.proto.examples.v1.TournamentEnrollmentRejected event
    And the tournament event has reason containing "player_root"

  @EU-0814
  Scenario: Enrollment rejected when registration is not open
    Given a TournamentCreated event with name "Test Tournament" buy_in 100 starting_stack 1000 max_players 100 min_players 10
    When I handle an EnrollPlayer command for player "player1" reservation ""
    Then the result is a angzarr_client.proto.examples.v1.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  @EU-0815
  Scenario: Enrollment rejected when tournament is full
    Given a tournament with max_players 2 and min_players 2 and registration open
    And a player "p1" enrolled
    And a player "p2" enrolled
    When I handle an EnrollPlayer command for player "p3" reservation ""
    Then the result is a angzarr_client.proto.examples.v1.TournamentEnrollmentRejected event
    And the tournament event has reason containing "full"

  @EU-0816
  Scenario: Enrollment rejected for duplicate player
    Given a tournament with registration open
    And a player "player1" enrolled
    When I handle an EnrollPlayer command for player "player1" reservation ""
    Then the result is a angzarr_client.proto.examples.v1.TournamentEnrollmentRejected event
    And the tournament event has reason containing "already registered"

  # ==========================================================================
  # Rebuy Processing
  # ==========================================================================
  # Rule: TDA Rule 27 (2024) — rebuy mechanics: declared rebuy plays
  #       chips behind; player must complete the rebuy.
  # Rule: WSOP §I-13 (2025) — re-entry events: zero chips required;
  #       re-entrants get a full starting stack.
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
    Then the result is a angzarr_client.proto.examples.v1.RebuyDenied event
    And the tournament event has reason containing "not registered"

  # ==========================================================================
  # Player Elimination
  # ==========================================================================
  # Rule: WSOP §I-13 (2025) — re-entry events allow eliminated players to
  #       re-enter with a fresh stack; per Rule 8B their forfeited chips
  #       are removed from play (codified at EU-1151).
  # (Framework: lifecycle gate — only running tournaments can record
  # eliminations. The bust-into-money tiebreak rules are codified in the
  # hand-for-hand and payout sections.)
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
  # Rule: WSOP §I-122 (2025) — play may be suspended and resumed; dinner
  #       breaks are listed on structure sheets.
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
  # Rule: WSOP §IX Flop Games (2025) — minimum 2 players to deal a hand.
  # Start requires open registration plus at least min_players enrolled.

  @EU-0822
  Scenario: Start tournament with enough players
    Given a tournament with min_players 2 and max_players 10 and registration open
    And a player "p1" enrolled
    And a player "p2" enrolled
    When I handle a StartTournament command
    Then the result is a angzarr_client.proto.examples.v1.TournamentStarted event
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
  # (Framework: pre-condition gate. Rules covered by Player Enrollment
  # section above.)

  @EU-0824
  Scenario: EnrollPlayer rejects when the tournament does not exist
    Given no prior events for the tournament aggregate
    When I handle an EnrollPlayer command for player "p1" reservation ""
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Tournament does not exist"

  # ==========================================================================
  # AdvanceBlindLevel — Success and Not-Running Rejection
  # ==========================================================================
  # Rule: TDA Rule 23 (2024) — new level applies to next hand; level
  #       changes are explicit transitions (covered at EU-1210, EU-1211).
  # Rule: TDA RP-11 (2024) — antes do not reduce as play progresses.

  @EU-0825
  Scenario: AdvanceBlindLevel on a running tournament emits BlindLevelAdvanced
    Given a running tournament with a two-level blind structure
    When I handle an AdvanceBlindLevel command
    Then the result is a angzarr_client.proto.examples.v1.BlindLevelAdvanced event
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
  # (Framework: PlayerEliminated event captures the hand that knocked
  # the player out, for tournament audit and bubble-tiebreak reasoning.
  # Rules covered by Player Elimination section above.)

  @EU-0827
  Scenario: EliminatePlayer emits PlayerEliminated with the supplied hand_root
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle an EliminatePlayer command for player "p0" with hand_root "hand-01"
    Then the result is a angzarr_client.proto.examples.v1.PlayerEliminated event
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
  # (Framework: state-machine guards. Rules covered by Pause / Resume
  # section above.)

  @EU-0829
  Scenario: PauseTournament on a running tournament emits TournamentPaused
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle a PauseTournament command with reason "dinner break"
    Then the result is a angzarr_client.proto.examples.v1.TournamentPaused event
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
  # (Framework: state-machine transition. Rules covered by Pause / Resume.)

  @EU-0831
  Scenario: ResumeTournament on a paused tournament emits TournamentResumed
    Given a paused tournament
    When I handle a ResumeTournament command
    Then the result is a angzarr_client.proto.examples.v1.TournamentResumed event

  # ==========================================================================
  # OpenRegistration — Running-Tournament Rejection
  # ==========================================================================
  # (Framework: state-machine guard. Rule covered by Open / Close
  # Registration section above.)

  @EU-0832
  Scenario: OpenRegistration rejects when tournament is running
    Given a running tournament with min_players 2 and max_players 10 and 2 enrolled players
    When I handle an OpenRegistration command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "running tournament"

  # ==========================================================================
  # CloseRegistration — total_registrations count
  # ==========================================================================
  # (Framework: snapshot of registered count at registration close.)

  @EU-0833
  Scenario: CloseRegistration emits RegistrationClosed with the registered count
    Given a tournament with registration open
    And a player "p1" enrolled
    When I handle a CloseRegistration command
    Then the result is a angzarr_client.proto.examples.v1.RegistrationClosed event
    And the tournament event has total_registrations 1

  # ==========================================================================
  # ProcessRebuy — Success, Missing Tournament, Disabled Rebuys
  # ==========================================================================
  # Rule: TDA Rule 27 (2024) — rebuys; Rule covered by Rebuy Processing
  # section above. Disabled-rebuys is a per-tournament configuration
  # setting (rebuys_enabled) — when false, rebuys are denied.

  @EU-0834
  Scenario: ProcessRebuy emits RebuyProcessed for an enrolled player with rebuys enabled
    Given a running tournament with rebuys enabled and 1 enrolled player
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.v1.RebuyProcessed event
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
    Then the result is a angzarr_client.proto.examples.v1.RebuyDenied event
    And the tournament event has reason containing "not enabled"

  # ==========================================================================
  # ProcessRebuy — Config Threshold Variations
  # ==========================================================================
  # Rule: TDA Rule 27 (2024) — rebuys are subject to per-event configura-
  #       tion (cutoff level, max rebuys per player). The structure sheet
  #       defines these per WSOP §I-13.
  # can_rebuy() combines state (running) with config (enabled / cutoff_level /
  # max_rebuys) — each threshold gets its own denial/allow scenario.

  @EU-0837
  Scenario: ProcessRebuy emits RebuyDenied when rebuys are disabled in config
    Given a running tournament with rebuys disabled and 1 enrolled player
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.v1.RebuyDenied event
    And the tournament event has reason containing "not enabled"

  @EU-0838
  Scenario: ProcessRebuy emits RebuyDenied when current level is past the cutoff
    Given a running tournament with rebuy cutoff 2 and 1 enrolled player at level 5
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.v1.RebuyDenied event
    And the tournament event has reason containing "closed"

  @EU-0839
  Scenario: ProcessRebuy emits RebuyDenied when player has reached max rebuys
    Given a running tournament with max_rebuys 2 and player "p0" who has used 2 rebuys
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.v1.RebuyDenied event
    And the tournament event has reason containing "Maximum"

  @EU-0840
  Scenario: ProcessRebuy succeeds when rebuy_level_cutoff is 0 (cutoff check disabled)
    Given a running tournament with rebuy cutoff 0 and 1 enrolled player at level 99
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.v1.RebuyProcessed event
    And the tournament event has rebuy_count 1

  @EU-0841
  Scenario: ProcessRebuy succeeds when max_rebuys is 0 (unlimited rebuys)
    Given a running tournament with max_rebuys 0 and player "p0" who has used 100 rebuys
    When I handle a ProcessRebuy command for player "p0"
    Then the result is a angzarr_client.proto.examples.v1.RebuyProcessed event

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # (Framework: event-replay correctness. Pins the projection of each
  # event type into tournament state. Rules driving the events are
  # codified in the sections above; this section pins that they replay
  # consistently from any event prefix.)
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
  # Rule: TDA Rule 8A (2024) — "Alternates, players registering late, and
  #       re-entries will be sold full stacks. They will randomly draw a
  #       seat and table … and are dealt in except between the small
  #       blind and button."
  # Rule: WSOP §I-12, §I-14 (2025) — late registration closes at end of
  #       structure-defined level; late registrants get full stack.
  # Real tournaments keep registration open for several blind levels into
  # running play. The previously implicit rule "TournamentStarted closes
  # registration" was a real-rule violation: registration must remain
  # open until either the configured cutoff level or an explicit
  # CloseRegistration. These scenarios pin the late-registration surface.

  @EU-0857
  Scenario: EnrollPlayer succeeds against a Running tournament when registration is still open
    # Tournament starts with min_players=2 enrolled. A third player registers
    # AFTER the start while registration is still open. They are enrolled and
    # added to the prize pool.
    Given a running tournament with registration open and 2 enrolled players
    When I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.v1.TournamentPlayerEnrolled event
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
    Then the result is a angzarr_client.proto.examples.v1.TournamentPlayerEnrolled event
    And the tournament event has starting_stack 1500

  @EU-0859
  Scenario: Registration auto-closes when the cutoff level is reached
    # Tournaments configure a registration_cutoff_level. When the tournament
    # advances to a level past the cutoff, registration auto-closes and a
    # subsequent enrollment is rejected with the "not open" reason — same
    # rejection path as an explicit CloseRegistration.
    Given a running tournament with registration_cutoff_level 3 at level 4 and 2 enrolled players
    When I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.v1.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  @EU-0860
  Scenario: Explicit CloseRegistration during a running tournament prevents further enrollment
    # Operators can close registration manually (e.g. after announcing the
    # late-reg deadline). Enrollments after that are rejected even though
    # the tournament is still running.
    Given a running tournament with 2 enrolled players
    When I handle a CloseRegistration command
    And I handle an EnrollPlayer command for player "p3" reservation "res-3"
    Then the result is a angzarr_client.proto.examples.v1.TournamentEnrollmentRejected event
    And the tournament event has reason containing "not open"

  # ==========================================================================
  # Multi-place Payout
  # ==========================================================================
  # Rule: WSOP §III-31 (2025) — "Prize structures depend on the number of
  #       entrants and type of Event. Prizes are paid out as posted."
  # Rule: WSOP §III-37 (2025) — schedule cannot be modified once awarded.
  # Tournaments pay multiple finishing positions on a published payout
  # schedule. The proto's TournamentResult already carries (position,
  # player_root, payout) — these scenarios pin the distribution. The
  # payout schedule is supplied to CompleteTournament (or pre-configured
  # at create time); the aggregate verifies payouts sum to total_prize_pool.

  @EU-0861
  Scenario: CompleteTournament emits results for the top-N finishers per the payout schedule
    # 9-player $500 buy-in. Pool = 4500. Schedule pays top 3 at 50/30/20.
    Given a running tournament "Spring" with total_prize_pool 4500 and 9 enrolled players
    And a payout_structure paying positions 1,2,3 at percentages 50,30,20
    And finishing order "p1,p2,p3,p4,p5,p6,p7,p8,p9"
    When I handle a CompleteTournament command with winner "p1"
    Then the result is a angzarr_client.proto.examples.v1.TournamentCompleted event
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
    Then the result is a angzarr_client.proto.examples.v1.TournamentCompleted event
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
    Then the result is a angzarr_client.proto.examples.v1.TournamentCompleted event
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

  # ==========================================================================
  # Re-Entry Forfeited Chips — TDA Rule 8B
  # ==========================================================================
  # Real poker (TDA Rule 8B): "In re-entry events, if a player is permitted
  # to forfeit chips and buy a new stack, the forfeited chips will be
  # removed from play." This protects the chip-ledger conservation: a
  # re-entry adds a fresh starting stack to the player's seat AND removes
  # the prior (forfeited) stack from total_chips_in_play. Without this, a
  # re-entry would silently inflate the chip economy.

  @EU-1151
  Scenario: Re-entry removes the player's prior forfeited chips from total_chips_in_play
    # Rule: TDA Rule 8B (2024) — re-entry forfeited chips removed from play.
    # Tournament with starting_stack=1500. player-A has been eliminated
    # earlier with 0 chips (busted) AND a separate scenario where they
    # forfeit 200 chips to re-enter. Total chips in play before the re-entry
    # is 6000 (4 players * 1500 starting). After the re-entry: 6000 - 200
    # forfeited + 1500 fresh = 7300.
    Given a running tournament "Reentry" with starting_stack 1500 and 4 enrolled players
    And total_chips_in_play is 6000
    And player "Alice" has 200 chips remaining and elects to re-enter
    When I handle a ReEntryPlayer command for player "Alice" forfeiting 200 chips
    Then the result is a angzarr_client.proto.examples.v1.PlayerReEntered event
    And the tournament event has chips_forfeited 200
    And the tournament event has chips_added 1500
    And total_chips_in_play is 7300

  # ==========================================================================
  # Chip Race / Color-Up — TDA Rule 24
  # ==========================================================================
  # Real poker (TDA Rule 24): "At scheduled color-ups, chips will be raced
  # off starting in seat 1, with a maximum of one chip awarded to a player.
  # Players can't be raced out of play: a player losing their last chip(s)
  # in a race will get 1 chip of the lowest denomination still in play."
  # The cluster-tier @wip scenario EA-0011 covers the cluster integration;
  # these unit scenarios pin the aggregate-level invariants.

  @EU-1160
  Scenario: Chip race awards at most one chip to any single player
    # Rule: TDA Rule 24A (2024) — "max of one chip awarded to a player".
    # Three players each have 75 chips of denomination 25 (3 chips each).
    # Race retires denomination 25 in favour of denomination 100. Each
    # player keeps 3*25 = 75; integer-divides to 0 chips of denomination
    # 100; each is eligible for the race. The race awards at most ONE
    # chip per player.
    Given a running tournament "Race" with 3 active players
    And every active player has exactly 75 chips of denomination 25
    When I handle an AdvanceBlindLevel command with chip-race retiring 25 to 100
    Then the result is a angzarr_client.proto.examples.v1.ColorUpCompleted event
    And no player received more than 1 chip from the race

  @EU-1161
  Scenario: Chip race cannot eliminate a player — single-chip rescue applies
    # Rule: TDA Rule 24A (2024) — "Players can't be raced out of play: a
    #       player losing their last chip(s) in a race will get 1 chip of
    #       the lowest denomination still in play."
    # player-A has 25 chips total (one chip of denom 25), about to be raced
    # off entirely. The race must give them at least 1 chip of the lowest
    # remaining denomination (100) so they remain in play.
    Given a running tournament "Race" with 3 active players
    And player "Alice" has exactly 25 chips of denomination 25 and nothing else
    When I handle an AdvanceBlindLevel command with chip-race retiring 25 to 100
    Then the result is a angzarr_client.proto.examples.v1.ColorUpCompleted event
    And player "Alice" stack is at least 100

  @EU-1162
  Scenario: Total chips in play is conserved by the chip race (modulo rescue clause)
    # Rule: TDA Rule 24C (2024) — "Chips of removed denominations that do
    #       not fully total at least the smallest denomination still in
    #       play will be removed without compensation." The rescue clause
    #       (24A) is the only legal chip-creation path during a race.
    # 3 players. Total chips before race = 6000. Race retires denom 25 to
    # denom 100. After race: total_chips_in_play differs from before only
    # by the rescue clause and by removed odd-denomination chips that
    # didn't qualify; the difference must be auditable.
    Given a running tournament "Race" with total_chips_in_play 6000
    When I handle an AdvanceBlindLevel command with chip-race retiring 25 to 100
    Then the result is a angzarr_client.proto.examples.v1.ColorUpCompleted event
    And the event has chips_added_by_rescue and chips_removed_by_race
    And total_chips_in_play after race equals 6000 + chips_added_by_rescue - chips_removed_by_race

  # ==========================================================================
  # Hand-for-Hand — TDA RP-8
  # ==========================================================================
  # Real poker (TDA RP-8): on the bubble, all active tables play one hand
  # synchronously and pause until every table completes the hand. The
  # cluster-tier @wip EA-0013 covers the multi-table integration; these
  # unit scenarios pin the tournament-aggregate-level rules:
  #   - simultaneous bust on the same hand-for-hand hand split the next
  #     bubble payout (RP-8A);
  #   - the level clock deducts at most 3 minutes per H4H hand (RP-8B);
  #   - clock reduction is applied per-hand, not in batches (RP-8C).

  @EU-1190
  Scenario: Two players bust on the same hand-for-hand hand share the next bubble payout
    # Rule: TDA RP-8A (2024) — "If enough players bust on the current hand
    #       to break into the money, the busting players will be eligible
    #       for a share of the place(s) paid on the current hand."
    # 4-player tournament paying top 3 (50/30/20). Two players bust
    # simultaneously on the H4H hand: by RP-8A they share the 3rd-place
    # payout (the lowest paid position). Each gets half of position-3.
    Given a running tournament "Bubble" with total_prize_pool 1000 and 4 enrolled players
    And a payout_structure paying positions 1,2,3 at percentages 50,30,20
    And hand-for-hand is active
    And finishing order "Alice,Bob,Carol,Dave"
    When players "Carol,Dave" both bust on the same hand-for-hand hand
    And I handle a CompleteTournament command with winner "Alice"
    Then the result is a angzarr_client.proto.examples.v1.TournamentCompleted event
    And the tournament event has 4 results
    And TournamentResult 0 has position 1 player_root "Alice" payout 500
    And TournamentResult 1 has position 2 player_root "Bob" payout 300
    # 3rd place is split 50/50 between the two simultaneous busts
    And TournamentResult 2 has position 3 player_root "Carol" payout 100
    And TournamentResult 3 has position 3 player_root "Dave" payout 100

  @EU-1191
  Scenario: Hand-for-hand deducts at most 3 minutes per hand from the level clock
    # Rule: TDA RP-8B (2024) — "During H4H play, a maximum of 3 minutes per
    #       hand will be deducted from the clock."
    # An H4H hand that takes longer than 3 minutes still only deducts 3
    # minutes from the level clock — the level cannot be drained faster
    # than the H4H pacing rule allows.
    Given a running tournament "Bubble" with hand-for-hand active and level_seconds_remaining 600
    When a hand-for-hand hand takes 5 minutes of real time to complete
    Then the level_seconds_remaining after the hand equals 420

  @EU-1192
  Scenario: Hand-for-hand clock reduction is applied per-hand, not in batches
    # Rule: TDA RP-8C (2024) — "Whenever possible the clock should be
    #       reduced by 2-minutes each hand not after 'batches' of multiple
    #       hands."
    # Two H4H hands complete back-to-back. The clock must show a 2-minute
    # deduction after the first hand and another 2-minute deduction after
    # the second — not a single 4-minute deduction at the end.
    Given a running tournament "Bubble" with hand-for-hand active and level_seconds_remaining 600
    When the first hand-for-hand hand completes
    Then the level_seconds_remaining is 480
    When the second hand-for-hand hand completes
    Then the level_seconds_remaining is 360

  # ==========================================================================
  # Penalty System — TDA Rule 71 / WSOP Rule 113
  # ==========================================================================
  # Real poker (TDA Rule 71): "Enforcement options include but are not
  # limited to verbal warnings, one or more 'missed hand' or 'missed round'
  # penalties, and disqualification. For missed rounds, the offender will
  # miss one hand for every player (including him or her) at the table when
  # the penalty is given multiplied by the number of penalty rounds."
  # WSOP Rule 113 mirrors with a 4-round maximum.

  @EU-1310
  Scenario Outline: Penalty types — verbal warning, missed-hand, missed-round, disqualification
    # Rule: TDA Rule 71A (2024) — penalty options.
    # Rule: WSOP Rule 113 (2025) — penalty hierarchy.
    Given a running tournament "Spring" with min_players 6, max_players 9, and 6 enrolled players
    And player "Alice" is at a table with 6 active players
    When I handle an IssuePenalty command for player "Alice" with type "<type>" rounds <rounds>
    Then the result is a angzarr_client.proto.examples.v1.PenaltyIssued event
    And the penalty event has type "<type>"
    And the penalty event has missed_hands <missed>

    Examples:
      | type           | rounds | missed |
      | VERBAL_WARNING | 0      | 0      |
      | MISSED_HAND    | 0      | 1      |
      | MISSED_ROUND   | 1      | 6      |
      | MISSED_ROUND   | 2      | 12     |
      | DISQUALIFIED   | 0      | 0      |

  @EU-1311
  Scenario: Player on penalty has cards dealt then killed; blinds and antes are still posted
    # Rule: TDA Rule 71C (2024) — "Players on penalty must be away from the
    #       table. Cards are dealt to their seats, their blinds and antes
    #       posted, their hands are killed after the initial deal."
    Given a running tournament "Spring" with min_players 2 and max_players 9 and 2 enrolled players
    And player "Alice" is on a 1-round MISSED_ROUND penalty
    And the next hand at Alice's table has SB at Alice's seat
    When I handle a StartHand command at Alice's table
    Then the result is a angzarr_client.proto.examples.v1.HandStarted event
    And player "Alice" had her SB posted from her stack
    And player "Alice" hand is killed after the initial deal
    And player "Alice" remains on penalty with rounds_remaining decremented by 1

  @EU-1312
  Scenario: Disqualified player chips are removed from play
    # Rule: TDA Rule 71D (2024) — "Chips of a disqualified player shall be
    #       removed from play."
    # Rule: WSOP Rule 114 (2025) — same.
    Given a running tournament "Spring" with min_players 2 and max_players 9 and 4 enrolled players
    And player "Alice" has stack 1500 and tournament total_chips_in_play is 6000
    When I handle a DisqualifyPlayer command for player "Alice" with reason "collusion"
    Then the result is a angzarr_client.proto.examples.v1.PlayerDisqualified event
    And the disqualification event has chips_forfeited 1500
    And total_chips_in_play is 4500
    And player "Alice" is no longer in registered_players

  # ==========================================================================
  # Late Registration First-Hand Position — WSOP Rule 14
  # ==========================================================================
  # Real poker (WSOP Rule 14): "Late registrants will either begin play at
  # the start of the subsequent level or be randomly seated at tables where
  # Participants have already been eliminated. All late registrants will
  # start the Event with a full chip stack. Late registrants do not have
  # to post to begin play but must assume first available starting position
  # at the table, even if that means assuming the button, small blind, or
  # big blind during the first hand."

  @EU-1313
  Scenario: Late-reg player can be dealt the button on their first hand without missing the hand
    # Rule: WSOP Rule 14 (2025) — late registrant assumes first available
    #       starting position even if it's the button.
    Given a running tournament "Spring" with registration open and 8 enrolled players
    And the dealer button at "Spring-1" is about to advance to a vacated seat 5
    When player "Alice" late-registers and is seated at "Spring-1" seat 5
    Then the result is a angzarr_client.proto.examples.v1.TournamentPlayerEnrolled event
    When I handle a StartHand command at "Spring-1"
    Then the result is a angzarr_client.proto.examples.v1.HandStarted event
    And the dealer_position is seat 5
    And player "Alice" is dealt in for that hand

  # ==========================================================================
  # No-Show Policy — WSOP Rule 16
  # ==========================================================================
  # Real poker (WSOP Rule 16): "Any Participant who has not taken a hand by
  # the start of the level after the first official break will be considered
  # a 'no show.' These Participants will have their chips removed from play
  # and will not be eligible to participate in that Event."

  @EU-1314
  Scenario: No-show player after the first-break deadline has their chips removed
    # Rule: WSOP Rule 16 (2025) — no-show chip removal.
    Given a running tournament "Spring" with starting_stack 1500
    And player "Alice" enrolled but never took a hand before the first break ended
    And the new level after the first break has begun
    When the no-show deadline for "Spring" expires
    Then a angzarr_client.proto.examples.v1.NoShowDetected event is emitted for player "Alice"
    And player "Alice" chips are removed from total_chips_in_play
    And player "Alice" buy-in 500 is held in safekeeping
    And player "Alice" is not in players_remaining

  # ==========================================================================
  # Absent Player Blind Progression at Heads-Up — WSOP Rule 36
  # ==========================================================================
  # Real poker (WSOP Rule 36): "After five minutes has elapsed, if there is
  # only one Participant present at the table, the button will advance one
  # position every two minutes and the Participant will be awarded the
  # small blind and the big blind."

  @EU-1315
  Scenario: Heads-up with one player absent — button advances every 2 minutes and lone player banks blinds
    # Rule: WSOP Rule 36 (2025) — heads-up absent-opponent blind progression.
    Given a running tournament "HU-Final" in heads-up between "Alice" and "Bob"
    And player "Bob" has been absent from the table for 5 minutes
    When 2 minutes elapses with player "Bob" still absent
    Then a angzarr_client.proto.examples.v1.AbsentBlindAdvanced event is emitted
    And the dealer button advances by 1 position
    And player "Alice" stack is increased by SB + BB
    And player "Bob" stack is decreased by SB + BB

  # ==========================================================================
  # Re-Draws at Table Thresholds — WSOP Rule 67c
  # ==========================================================================
  # Real poker (WSOP Rule 67c): "There will be a re-draw for seat
  # assignments when play reaches three tables, again at two tables, and
  # for the final table seat assignments for Events that have 100 or more
  # Participants."

  @EU-1316
  Scenario Outline: Seat redraw is triggered at 3 tables, 2 tables, and final table for 100+ events
    # Rule: WSOP Rule 67c (2025) — redraw thresholds.
    Given a running tournament "Worlds" with original_field 250 and <tables_remaining> tables remaining
    When the field collapses to <tables_remaining> table(s)
    Then a angzarr_client.proto.examples.v1.SeatRedrawTriggered event is emitted
    And the redraw event has trigger "<trigger>"

    Examples:
      | tables_remaining | trigger              |
      | 3                | THREE_TABLES         |
      | 2                | TWO_TABLES           |
      | 1                | FINAL_TABLE          |

  # ==========================================================================
  # Same-Hand Multi-Bust at Same Table — WSOP Rule 126b
  # ==========================================================================
  # Real poker (WSOP Rule 126b): "If two or more Participants are eliminated
  # during the same hand at the same table, the Participant(s) who began
  # the hand with the highest chip count will receive the higher place
  # finish." TDA RP-8A handles the simultaneous-bust-at-different-tables
  # case (EU-1190); this scenario pins the same-table case.

  @EU-1317
  Scenario: Two players bust at the same table on the same hand — higher pre-hand stack gets higher place
    # Rule: WSOP Rule 126b (2025) — same-table tiebreak by pre-hand chip count.
    # 4-player tournament paying top 3 (50/30/20). Hand-for-hand active.
    # Carol started the hand with 800 chips. Dave started with 600. Both
    # bust on the same hand. By WSOP-126b, Carol > Dave: Carol gets 3rd
    # place (the paid bubble) and Dave gets 4th (no payout).
    Given a running tournament "Bubble" with total_prize_pool 1000 and 4 enrolled players
    And a payout_structure paying positions 1,2,3 at percentages 50,30,20
    And hand-for-hand is active
    And the current hand started with stacks: Alice 2000, Bob 1600, Carol 800, Dave 600
    And finishing order "Alice,Bob,Carol,Dave"
    When players "Carol,Dave" both bust on the same hand at the same table
    And I handle a CompleteTournament command with winner "Alice"
    Then the result is a angzarr_client.proto.examples.v1.TournamentCompleted event
    And TournamentResult 2 has position 3 player_root "Carol" payout 200
    And no TournamentResult has player_root "Dave" with non-zero payout
    # Carol's higher pre-hand stack (800 > 600) earns her the higher finish
    And TournamentResult tiebreak_reason for position 3 is "PRE_HAND_STACK"

  # ==========================================================================
  # Player Absent on Breaking Table — TDA RP-16
  # ==========================================================================
  # Real poker (TDA RP-16): "If a player is absent on a breaking table,
  # the player should be moved to a new table with whatever chips were on
  # the broken table; the missed-blinds clock continues at the new table."

  @EU-1370
  Scenario: Absent player from a broken table is moved with their chips intact
    # Rule: TDA RP-16 (2024) — absent player on a breaking table.
    Given a tournament with table "T1" being broken and player "Eve" absent at "T1"
    And player "Eve" had 1850 in chips on "T1"
    And open seats exist at table "T2" and "T3"
    When the breaking-table coordinator reseats absent "Eve"
    Then a PlayerMovedTables event is emitted for "Eve" with from_table "T1"
    And player "Eve" stack at the new table equals 1850
    And player "Eve" missed-blinds clock continues at the new table

  # ==========================================================================
  # Mixed-Game Rotation Order — TDA RP-18
  # ==========================================================================
  # Real poker (TDA RP-18): in HORSE the rotation order is fixed —
  # H(old'em) → O(maha Hi/Lo) → R(azz) → S(even Card Stud) →
  # E(ight or Better Stud Hi/Lo). One full orbit (button completes the
  # table) before transitioning to the next variant.

  @EU-1371
  Scenario: HORSE rotation cycles H → O → R → S → E in fixed order
    # Rule: TDA RP-18 (2024) — fixed mixed-game rotation order.
    Given a HORSE tournament with 5 active players starting on Texas Hold'em
    When one full orbit of Texas Hold'em completes (button returns to seat 0)
    Then the variant transitions to Omaha Hi/Lo
    When one full orbit of Omaha Hi/Lo completes
    Then the variant transitions to Razz
    When one full orbit of Razz completes
    Then the variant transitions to Seven Card Stud
    When one full orbit of Seven Card Stud completes
    Then the variant transitions to Seven Card Stud Hi/Lo 8 or Better
    When one full orbit of Seven Card Stud Hi/Lo 8 or Better completes
    Then the variant transitions back to Texas Hold'em

  # ==========================================================================
  # Bounty Tournaments — TDA RP-22 + WSOP Rule 39
  # ==========================================================================
  # Real poker (TDA RP-22 / WSOP Rule 39): in bounty events, knocking out
  # a player triggers a bounty payout to the eliminator. When the last two
  # players go all-in and one busts, the bounty goes to the player with
  # the higher pre-hand stack (TDA RP-22 + WSOP Rule 39).

  @EU-1372
  Scenario: Bounty tournament — eliminator collects bounty on knockout
    # Rule: TDA RP-22 (2024) — bounty payout on knockout.
    # Rule: WSOP Rule 39 (2025) — bounty markers.
    Given a bounty tournament with bounty_per_knockout 100
    And player "Alice" eliminates player "Bob" by winning the showdown
    When the elimination is processed
    Then a BountyAwarded event is emitted with eliminator "Alice" knocked_out "Bob" amount 100
    And player "Alice" bounty_total increases by 100

  @EU-1373
  Scenario: Bounty tournament — last-two simultaneous bust splits to higher pre-hand stack
    # Rule: TDA RP-22 (2024) — simultaneous-bust tiebreak by pre-hand stack.
    Given a bounty tournament with bounty_per_knockout 200
    And exactly 2 players left "Alice" stack 500 and "Bob" stack 400 pre-hand
    When both players go all-in and lose at the same showdown (split-pot push not applicable)
    And the higher pre-hand stack is "Alice" (500 > 400)
    Then a BountyAwarded event is emitted with eliminator "Alice" knocked_out "Bob" amount 200
    And no bounty is awarded for "Alice"

  # ==========================================================================
  # Soft Play & End-of-Day — WSOP Rule 118 + TDA Rule 23
  # ==========================================================================
  # Real poker (WSOP Rule 118): soft play between players results in
  # forfeiture of chips and possible disqualification. (WSOP Rule 125):
  # at end-of-day, hands in progress complete, then bagging begins.

  @EU-1374
  Scenario: Soft-play DQ removes the offending player's chips from play
    # Rule: WSOP Rule 118 (2025) — "Soft play will result in penalties
    #       that may include forfeiture of chips and/or disqualification."
    # Rule: TDA Rule 71D (2024) — DQ chips removed from play.
    Given a running tournament with player "Carol" reported for soft play with player "Dave"
    When the floor disqualifies player "Carol" for soft play
    Then a PlayerDisqualified event is emitted with player "Carol" reason "SOFT_PLAY"
    And player "Carol" chips are removed from total_chips_in_play

  @EU-1375
  Scenario: End-of-day stop time pauses the tournament after the in-progress hand finishes
    # Rule: WSOP Rule 125 (2025) — "Prior to the end of each day's play,
    #       Personnel will determine between 7-13 minutes left in last
    #       level when to stop new hands; in-progress hands complete and
    #       bagging begins."
    Given a running tournament at minute 53 of the final scheduled level (60 min levels)
    And a hand is currently in progress
    When the floor issues a StopNewHands command
    Then a NewHandsHalted event is emitted with effective_at "AFTER_CURRENT_HAND"
    And the in-progress hand is allowed to complete normally
    When the in-progress hand completes
    Then the tournament transitions to BAGGING_AND_TAGGING
    And no new StartHand command is accepted until the next day's resume

  @EU-1376
  Scenario: Tournament resume on Day 2 restores stacks and seat assignments from bag-and-tag
    # Rule: WSOP Rule 122 (2025) — "Play on Day 2 and beyond may be
    #       suspended prior to the end of scheduled play and will resume
    #       the following day with stacks and seats as bagged."
    Given a tournament that completed Day 1 with bag-and-tag for 18 surviving players
    And a BagAndTagComplete event recorded each player's stack and seat
    When the floor issues a ResumeTournament command for Day 2
    Then a TournamentResumed event is emitted
    And every player's starting stack equals their Day 1 bagged stack
    And every player's seat assignment matches the Day 2 redraw if 100+ event, else bagged seat
