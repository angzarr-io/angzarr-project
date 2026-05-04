# Allocated: EU-0100 .. EU-0120, EU-0531 .. EU-0567, EU-0570 .. EU-0574, EU-0575 .. EU-0578
Feature: Table aggregate logic
  The Table aggregate manages a poker table session: configuration, player
  seating, and hand lifecycle. It's the orchestration layer between players
  (who have money) and hands (where money changes ownership).

  Why this aggregate exists:
  - Tables have configuration (blinds, limits) that hands inherit
  - Player seating is table-scoped, not hand-scoped
  - Dealer button and hand numbering track across multiple hands
  - Players join/leave tables, not individual hands

  What breaks if this is wrong:
  - Players could be double-seated at the same table
  - Hands could start with insufficient players
  - Dealer button wouldn't advance correctly

  Patterns enabled by this aggregate:
  - Cross-aggregate coordination: Table emits HandStarted, triggering saga to
    create Hand aggregate. Same pattern applies to order→fulfillment, auction→bid.
  - Slot/capacity management: Seats are exclusive resources with validation.
    Same pattern applies to parking spots, meeting room bookings, flight seats.
  - Child aggregate lifecycle: Table spawns hands, tracks their completion,
    updates state. Same pattern applies to project→tasks, tournament→matches.

  Why poker exercises these patterns well:
  - Seat occupancy is binary and obvious: seat 3 either has a player or doesn't
  - Hand lifecycle has clear start/end: HandStarted→HandEnded, easy to verify
  - Configuration inheritance is explicit: blinds flow from table to hand
  - Concurrent state is visible: 2 players at seats 0,3 while seats 1,2 empty

  # ==========================================================================
  # Table Creation
  # ==========================================================================
  # Tables are created with game configuration. Once created, the table
  # exists until closed (future feature). Duplicate creation is rejected.

  @EU-0100
  Scenario: Create a Texas Hold'em table
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Main Table" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 200        | 1000       | 9           |
    Then the result is a angzarr_client.proto.examples.TableCreated event
    And the table event has table_name "Main Table"
    And the table event has game_variant "TEXAS_HOLDEM"
    And the table event has small_blind 5
    And the table event has big_blind 10

  @EU-0101
  Scenario: Create a Five Card Draw table
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Draw Table" and variant "FIVE_CARD_DRAW":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 10          | 20        | 400        | 2000       | 6           |
    Then the result is a angzarr_client.proto.examples.TableCreated event
    And the table event has game_variant "FIVE_CARD_DRAW"

  @EU-0102
  Scenario: Cannot create table twice
    Given a TableCreated event for "Main Table"
    When I handle a CreateTable command with name "Another Table" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 200        | 1000       | 9           |
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already exists"

  # ==========================================================================
  # Player Seating
  # ==========================================================================
  # Players join with a buy-in (chips for play). The table tracks occupied
  # seats. Players can request a specific seat or take any available one.
  # Join failures don't affect the player's bankroll - no funds reserved yet.

  @EU-0103
  Scenario: Player joins table at preferred seat
    Given a TableCreated event for "Main Table"
    When I handle a JoinTable command for player "player-1" at seat 3 with buy-in 500
    Then the result is a angzarr_client.proto.examples.PlayerJoined event
    And the table event has seat_position 3
    And the table event has buy_in_amount 500

  @EU-0104
  Scenario: Player joins table at any seat
    Given a TableCreated event for "Main Table"
    When I handle a JoinTable command for player "player-1" at seat -1 with buy-in 500
    Then the result is a angzarr_client.proto.examples.PlayerJoined event
    And the table event has seat_position 0

  @EU-0105
  Scenario: Cannot join occupied seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 3
    When I handle a JoinTable command for player "player-2" at seat 3 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "SEAT_OCCUPIED"
    And the rejection field "seat" equals "3"

  @EU-0106
  Scenario: Cannot join table twice
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 3
    When I handle a JoinTable command for player "player-1" at seat 5 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already seated"

  @EU-0107
  Scenario: Cannot join with insufficient buy-in
    Given a TableCreated event for "Main Table" with min_buy_in 200
    When I handle a JoinTable command for player "player-1" at seat 0 with buy-in 100
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "BUY_IN_BELOW_MIN"
    And the rejection field "got" equals "100"
    And the rejection field "bound" equals "200"

  @EU-0108
  Scenario: Cannot join full table
    Given a TableCreated event for "Main Table" with max_players 2
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    When I handle a JoinTable command for player "player-3" at seat -1 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Table is full"

  # ==========================================================================
  # Player Departure
  # ==========================================================================
  # Players leave with their remaining stack (may differ from buy-in).
  # Departure during an active hand is forbidden - the player must wait
  # for the hand to complete. This prevents mid-hand bailouts.

  @EU-0109
  Scenario: Player leaves table
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 3 with stack 500
    When I handle a LeaveTable command for player "player-1"
    Then the result is a angzarr_client.proto.examples.PlayerLeft event
    And the table event has chips_cashed_out 500

  @EU-0110
  Scenario: Cannot leave during hand
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a HandStarted event for hand 1
    When I handle a LeaveTable command for player "player-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "during a hand"

  @EU-0111
  Scenario: Cannot leave table not joined
    Given a TableCreated event for "Main Table"
    When I handle a LeaveTable command for player "player-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not seated"

  # ==========================================================================
  # Hand Lifecycle - Start
  # ==========================================================================
  # Starting a hand captures the current player stacks and advances the
  # dealer button. The HandStarted event triggers the hand-table-saga to
  # deal cards in the hand domain.

  @EU-0112
  Scenario: Start a new hand
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0 with stack 500
    And a PlayerJoined event for player "player-2" at seat 1 with stack 500
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the table event has hand_number 1
    And the table event has 2 active_players

  @EU-0113
  Scenario: Dealer button advances each hand
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a HandStarted event for hand 1 with dealer at seat 0
    And a HandEnded event for hand 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the table event has hand_number 2
    And the table event has dealer_position 1

  @EU-0114
  Scenario: Cannot start hand with fewer than 2 players
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    When I handle a StartHand command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Not enough players"

  @EU-0115
  Scenario: Cannot start hand while one is in progress
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a HandStarted event for hand 1
    When I handle a StartHand command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already in progress"

  # ==========================================================================
  # Hand Lifecycle - End
  # ==========================================================================
  # Ending a hand applies stack changes (wins/losses) to seated players.
  # The HandEnded event triggers the hand-player-saga to update player
  # bankrolls in the player domain.

  @EU-0116
  Scenario: End hand and update stacks
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0 with stack 500
    And a PlayerJoined event for player "player-2" at seat 1 with stack 500
    And a HandStarted event for hand 1
    When I handle an EndHand command with winner "player-1" winning 50
    Then the result is a angzarr_client.proto.examples.HandEnded event
    And player "player-1" stack change is 50

  @EU-0117
  Scenario: Cannot end hand not in progress
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    When I handle an EndHand command with winner "player-1" winning 50
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "No hand in progress"

  @EU-0118
  Scenario: End hand updates player stacks with wins and losses
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0 with stack 500
    And a PlayerJoined event for player "player-2" at seat 1 with stack 500
    And a HandStarted event for hand 1
    When I handle an EndHand command with results:
      | player   | change |
      | player-1 | 150    |
      | player-2 | -150   |
    Then the result is a angzarr_client.proto.examples.HandEnded event
    And player "player-1" stack change is 150
    And player "player-2" stack change is -150

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # Table state is rebuilt by replaying events. This verifies that joining,
  # leaving, and hand events correctly update seated players and table status.

  @EU-0119
  Scenario: Rebuild state with multiple players
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0 with stack 500
    And a PlayerJoined event for player "player-2" at seat 3 with stack 800
    When I rebuild the table state
    Then the table state has 2 players
    And the table state has seat 0 occupied by "player-1"
    And the table state has seat 3 occupied by "player-2"
    And the table state has status "waiting"

  @EU-0120
  Scenario: Rebuild state during hand
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a HandStarted event for hand 1
    When I rebuild the table state
    Then the table state has status "in_hand"
    And the table state has hand_count 1

  # ==========================================================================
  # Create Validation (Phase 2 — test_table.py)
  # ==========================================================================
  # Configuration must be sane before accepting players. Blinds, buy-in
  # bounds, and max_players are validated synchronously. These checks match
  # the Go implementation for cross-language consistency.

  @EU-0531
  Scenario: CreateTable rejects non-positive min_buy_in
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 0          | 1000       | 6           |
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "MIN_BUY_IN_MUST_BE_POSITIVE"
    And the rejection field "value" equals "0"

  @EU-0531
  Scenario: CreateTable rejects max_buy_in below min_buy_in
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 500        | 100        | 6           |
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "MAX_BUY_IN_MUST_EXCEED_MIN_BUY_IN"
    And the rejection field "lhs" equals "100"
    And the rejection field "rhs" equals "500"

  @EU-0531
  Scenario: CreateTable rejects non-positive small_blind
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 0           | 10        | 100        | 1000       | 6           |
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "SMALL_BLIND_MUST_BE_POSITIVE"
    And the rejection field "value" equals "0"

  @EU-0531
  Scenario: CreateTable rejects big_blind below small_blind
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 20          | 10        | 100        | 1000       | 6           |
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "BIG_BLIND_MUST_EXCEED_SMALL_BLIND"
    And the rejection field "lhs" equals "10"
    And the rejection field "rhs" equals "20"

  @EU-0531
  Scenario: CreateTable rejects zero big_blind
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 0         | 100        | 1000       | 6           |
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "BIG_BLIND_MUST_EXCEED_SMALL_BLIND"
    And the rejection field "lhs" equals "0"
    And the rejection field "rhs" equals "5"

  @EU-0531
  Scenario: CreateTable rejects max_players below 2
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 1           |
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "MAX_PLAYERS_OUT_OF_RANGE"
    And the rejection field "got" equals "1"

  @EU-0531
  Scenario: CreateTable rejects max_players above 10
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "Test" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 11          |
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "MAX_PLAYERS_OUT_OF_RANGE"
    And the rejection field "got" equals "11"

  @EU-0532
  Scenario: CreateTable requires a table_name
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 6           |
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "table_name"

  # ==========================================================================
  # Join Validation (Phase 2)
  # ==========================================================================
  # Joining requires an existing table, a player_root, and a buy-in that
  # fits within the configured bounds. Preferred-seat occupancy is checked
  # before the any-seat fallback.

  @EU-0533
  Scenario: JoinTable rejects when buy-in exceeds max
    Given a TableCreated event for "Main Table"
    When I handle a JoinTable command for player "player-1" at seat 0 with buy-in 5000
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "BUY_IN_ABOVE_MAX"
    And the rejection field "got" equals "5000"
    And the rejection field "bound" equals "1000"

  @EU-0534
  Scenario: JoinTable rejects when table does not exist
    Given no prior events for the table aggregate
    When I handle a JoinTable command for player "player-1" at seat 0 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "does not exist"

  @EU-0535
  Scenario: JoinTable requires a player_root
    Given a TableCreated event for "Main Table"
    When I handle a JoinTable command for player "" at seat 0 with buy-in 500
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "player_root"

  @EU-0536
  Scenario: JoinTable rejects occupied preferred seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 3
    When I handle a JoinTable command for player "player-2" at seat 3 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "SEAT_OCCUPIED"
    And the rejection field "seat" equals "3"

  # ==========================================================================
  # Leave Validation (Phase 2)
  # ==========================================================================

  @EU-0537
  Scenario: LeaveTable rejects when table does not exist
    Given no prior events for the table aggregate
    When I handle a LeaveTable command for player "player-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "does not exist"

  @EU-0538
  Scenario: LeaveTable requires a player_root
    Given a TableCreated event for "Main Table"
    When I handle a LeaveTable command for player ""
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "player_root"

  # ==========================================================================
  # Hand Lifecycle Validation (Phase 2)
  # ==========================================================================

  @EU-0539
  Scenario: StartHand rejects when table does not exist
    Given no prior events for the table aggregate
    When I handle a StartHand command
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "does not exist"

  @EU-0540
  Scenario: EndHand rejects when table does not exist
    Given no prior events for the table aggregate
    When I handle an EndHand command with winner "player-1" winning 50
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "does not exist"

  @EU-0541
  Scenario: EndHand rejects mismatched hand_root
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a HandStarted event for hand 1
    When I handle an EndHand command with mismatched hand_root
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Hand root mismatch"

  @EU-0542
  Scenario: EndHand transitions status back to waiting
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    When I start a hand and end it with winner "player-1" winning 100
    Then the table state has status "waiting"
    And the table state has current_hand_root empty

  @EU-0543
  Scenario: StartHand in heads-up: dealer posts small blind
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the small_blind_position equals the dealer_position

  @EU-0544
  Scenario: StartHand with 3 players: SB is left of dealer
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a PlayerJoined event for player "player-3" at seat 2
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the small_blind_position differs from the dealer_position

  # ==========================================================================
  # State Accessors (Phase 2)
  # ==========================================================================

  @EU-0545
  Scenario: Table id is derived from the table name
    Given a TableCreated event for "High Stakes"
    When I rebuild the table state
    Then the table state has table_id "table_High Stakes"

  @EU-0546
  Scenario: is_full becomes true when max_players reached
    Given a TableCreated event for "Main Table" with max_players 2
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    When I rebuild the table state
    Then the table state is full

  @EU-0547
  Scenario: active_player_count excludes sitting-out players
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a PlayerSatOut event for player "player-1"
    When I rebuild the table state
    Then the table state has 2 players
    And the table state has 1 active_players

  # ==========================================================================
  # Event Replay (Phase 2)
  # ==========================================================================

  @EU-0548
  Scenario: PlayerSatIn restores a sat-out player to active
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerSatOut event for player "player-1"
    And a PlayerSatIn event for player "player-1"
    When I rebuild the table state
    Then the table state has 1 active_players

  @EU-0549
  Scenario: ChipsAdded updates the player stack via re-buy
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0 with stack 500
    And a ChipsAdded event for player "player-1" with new_stack 800
    When I rebuild the table state
    Then the table state seat 0 has stack 800

  # ==========================================================================
  # Cross-language Consistency (Phase 2)
  # ==========================================================================

  @EU-0550
  Scenario: Seat 0 is an explicit valid preferred seat
    Given a TableCreated event for "Main Table"
    When I handle a JoinTable command for player "player-1" at seat 0 with buy-in 500
    Then the result is a angzarr_client.proto.examples.PlayerJoined event
    And the table event has seat_position 0

  @EU-0551
  Scenario: Negative preferred_seat picks the next available seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    When I handle a JoinTable command for player "player-2" at seat -1 with buy-in 500
    Then the result is a angzarr_client.proto.examples.PlayerJoined event
    And the table event has seat_position 1

  # ==========================================================================
  # Full Lifecycle (Phase 2)
  # ==========================================================================

  @EU-0552
  Scenario: Full create/join/start/end/leave lifecycle
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0 with stack 500
    And a PlayerJoined event for player "player-2" at seat 1 with stack 500
    When I start a hand and end it with winner "player-1" winning 100
    Then the table state has status "waiting"

  # ==========================================================================
  # SeatPlayer Orchestration Command (Phase 2 — test_orchestration.py)
  # ==========================================================================
  # SeatPlayer is the PM-orchestrated seating flow. Unlike JoinTable, a
  # rejection becomes a SeatingRejected event (not an exception) so the PM
  # can compensate by releasing the buy-in reservation.

  @EU-0553
  Scenario: SeatPlayer emits PlayerSeated on success
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 500
    Then the result is a angzarr_client.proto.examples.PlayerSeated event
    And the seating event has seat_position 0
    And the seating event has stack 500

  @EU-0554
  Scenario: SeatPlayer emits SeatingRejected when amount is below minimum
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 100
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "at least"

  @EU-0555
  Scenario: SeatPlayer emits SeatingRejected when amount exceeds maximum
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 5000
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "above maximum"

  @EU-0556
  Scenario: SeatPlayer emits SeatingRejected when requested seat is occupied
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-b" at seat 0
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 500
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "occupied"

  @EU-0557
  Scenario: SeatPlayer emits SeatingRejected when player is already seated
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-a" at seat 1
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 2 amount 500
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "already seated"

  @EU-0558
  Scenario: SeatPlayer with seat -1 picks the next available seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-b" at seat 0
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat -1 amount 500
    Then the result is a angzarr_client.proto.examples.PlayerSeated event
    And the seating event has seat_position 1

  @EU-0559
  Scenario: SeatPlayer with seat -1 rejects when table is full
    Given a TableCreated event for "Main Table" with max_players 2
    And a PlayerJoined event for player "player-b" at seat 0
    And a PlayerJoined event for player "player-c" at seat 1
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat -1 amount 500
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "full"

  # ==========================================================================
  # AddRebuyChips Orchestration Command (Phase 2)
  # ==========================================================================
  # AddRebuyChips tops up a seated player's stack. Unlike SeatPlayer this
  # handler raises — the rebuy PM has already reserved the funds, so the
  # command should never reach the table if preconditions fail.

  @EU-0560
  Scenario: AddRebuyChips emits RebuyChipsAdded with new stack
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-a" at seat 2 with stack 500
    When I handle an AddRebuyChips command for player "player-a" reservation "res-001" seat 2 amount 1000
    Then the result is a angzarr_client.proto.examples.RebuyChipsAdded event
    And the rebuy event has amount 1000
    And the rebuy event has new_stack 1500
    And the rebuy event has seat 2

  @EU-0561
  Scenario: AddRebuyChips rejects when the player is not seated
    Given a TableCreated event for "Main Table"
    When I handle an AddRebuyChips command for player "player-a" reservation "res-001" seat 2 amount 1000
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not seated"

  @EU-0562
  Scenario: AddRebuyChips rejects when seat does not match
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-a" at seat 2 with stack 500
    When I handle an AddRebuyChips command for player "player-a" reservation "res-001" seat 3 amount 1000
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "mismatch"

  @EU-0563
  Scenario: AddRebuyChips rejects a non-positive amount
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-a" at seat 2 with stack 500
    When I handle an AddRebuyChips command for player "player-a" reservation "res-001" seat 2 amount 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "positive"

  # ==========================================================================
  # SeatPlayer / AddRebuyChips — Guard Rejections
  # ==========================================================================
  # SeatPlayer raises a CommandRejectedError only when the table does not
  # exist; all other validation failures become SeatingRejected events so
  # the PM can compensate. AddRebuyChips rejects at the command level for
  # the "no table" and "no player_root" cases since the rebuy PM has already
  # reserved the funds.

  @EU-0570
  Scenario: SeatPlayer rejects when the table does not exist
    Given no prior events for the table aggregate
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Table does not exist"

  @EU-0571
  Scenario: SeatPlayer emits SeatingRejected when player_root is empty
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "" reservation "res-001" seat 0 amount 500
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "player_root"

  @EU-0572
  Scenario: SeatPlayer emits SeatingRejected when seat is out of range
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat -5 amount 500
    Then the result is a angzarr_client.proto.examples.SeatingRejected event
    And the seating rejection reason contains "Invalid seat"

  @EU-0573
  Scenario: AddRebuyChips rejects when the table does not exist
    Given no prior events for the table aggregate
    When I handle an AddRebuyChips command for player "player-a" reservation "res-001" seat 0 amount 100
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Table does not exist"

  @EU-0574
  Scenario: AddRebuyChips rejects when player_root is empty
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-a" at seat 2 with stack 500
    When I handle an AddRebuyChips command for player "" reservation "res-001" seat 2 amount 100
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "player_root"

  # ==========================================================================
  # Dead Button Rule (button advancement after eliminations)
  # ==========================================================================
  # Real poker (TDA Rule 6, Robert's Rules §6): when a player in or near the
  # blind position is eliminated between hands, the button advances using
  # the "dead button" rule rather than naive +1. The intent: every player
  # gets the BB exactly once per orbit. Specifically:
  #   - If the player who would be the new BB is gone, the BB moves to the
  #     next active seat clockwise; the button itself "freezes" or moves to
  #     a vacant seat ("dead button") so the orbit does not double-blind
  #     anyone.
  #   - The previous SB seat is never the BB on the next hand (no player
  #     pays the BB twice in a row).
  # The simple "advance to next *seated* seat" rule (current implementation)
  # violates this when the BB busts.

  @EU-0575
  Scenario: BB busts — button stays put, BB skips to the next active seat (dead button)
    # Pre-elimination: dealer at seat 0 (player-A), SB at 1 (player-B),
    # BB at 2 (player-C). player-C busts at end of hand. Next hand:
    #   - The dealer button stays on seat 0 (dead button — there is no
    #     player at seat 2 to be SB on the following hand if it advanced).
    #   - SB is the next active seat clockwise of the dead button: seat 3.
    #   - BB is the next active seat after SB.
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-A" at seat 0
    And a PlayerJoined event for player "player-B" at seat 1
    And a PlayerJoined event for player "player-D" at seat 3
    And a HandStarted event for hand 1 with dealer at seat 0
    And a HandEnded event for hand 1
    And player "player-C" busted at seat 2 during hand 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the table event has dealer_position 0
    And the small_blind_position is seat 3
    And the big_blind_position is seat 0

  @EU-0576
  Scenario: SB busts — BB stays in place, button advances normally
    # Dealer 0, SB 1 (player-B), BB 2 (player-C). player-B busts.
    # Next hand: button → 1 is dead (no player), so dealer advances to the
    # *next active* seat... but the BB still must not double-blind. By the
    # dead-button rule, the player who was BB last hand (player-C) becomes
    # SB this hand, and BB moves to the next active seat (seat 3).
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-A" at seat 0
    And a PlayerJoined event for player "player-C" at seat 2
    And a PlayerJoined event for player "player-D" at seat 3
    And a HandStarted event for hand 1 with dealer at seat 0
    And a HandEnded event for hand 1
    And player "player-B" busted at seat 1 during hand 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the small_blind_position is seat 2
    And the big_blind_position is seat 3

  @EU-0577
  Scenario: Three players collapse to heads-up — dealer becomes SB and acts first preflop
    # 3-handed: dealer 0, SB 1, BB 2. player-B (SB seat 1) busts during
    # hand 1. Heads-up next hand: by TDA Rule 6 the dealer is the SB and
    # acts first preflop (matches EU-0543). The dead-button mechanics
    # collapse cleanly when the table reaches heads-up.
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-A" at seat 0
    And a PlayerJoined event for player "player-C" at seat 2
    And a HandStarted event for hand 1 with dealer at seat 0
    And a HandEnded event for hand 1
    And player "player-B" busted at seat 1 during hand 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the small_blind_position equals the dealer_position
    And the dealer_position is seat 0
    And the big_blind_position is seat 2

  @EU-0578
  Scenario: No player pays the big blind twice in a row across an elimination
    # The orbit invariant: a player who was BB on hand N is NEVER BB on
    # hand N+1 even if eliminations would naively produce that. This
    # scenario constructs the elimination pattern that breaks naive +1
    # advancement and asserts the BB seat changes occupant.
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-A" at seat 0
    And a PlayerJoined event for player "player-D" at seat 3
    And a HandStarted event for hand 1 with dealer at seat 0
    And big_blind_position on hand 1 was player "player-D"
    And a HandEnded event for hand 1
    And player "player-C" busted at seat 2 during hand 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the player at the big_blind_position is not "player-D"
