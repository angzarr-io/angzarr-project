# Allocated: EU-0100 .. EU-0120, EU-0531 .. EU-0567, EU-0570 .. EU-0574
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
    Then the result is a examples.TableCreated event
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
    Then the result is a examples.TableCreated event
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
    Then the result is a examples.PlayerJoined event
    And the table event has seat_position 3
    And the table event has buy_in_amount 500

  @EU-0104
  Scenario: Player joins table at any seat
    Given a TableCreated event for "Main Table"
    When I handle a JoinTable command for player "player-1" at seat -1 with buy-in 500
    Then the result is a examples.PlayerJoined event
    And the table event has seat_position 0

  @EU-0105
  Scenario: Cannot join occupied seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 3
    When I handle a JoinTable command for player "player-2" at seat 3 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Seat is occupied"

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
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "Buy-in must be at least"

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
    Then the result is a examples.PlayerLeft event
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
    Then the result is a examples.HandStarted event
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
    Then the result is a examples.HandStarted event
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
    Then the result is a examples.HandEnded event
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
    Then the result is a examples.HandEnded event
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
  Scenario Outline: CreateTable rejects invalid configuration
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "<name>" and variant "TEXAS_HOLDEM":
      | small_blind   | big_blind   | min_buy_in   | max_buy_in   | max_players   |
      | <small_blind> | <big_blind> | <min_buy_in> | <max_buy_in> | <max_players> |
    Then the command fails with status "<status>"
    And the error message contains "<message>"

    Examples:
      | name | small_blind | big_blind | min_buy_in | max_buy_in | max_players | status              | message                      |
      | Test | 5           | 10        | 0          | 1000       | 6           | INVALID_ARGUMENT    | min_buy_in must be positive  |
      | Test | 5           | 10        | 500        | 100        | 6           | FAILED_PRECONDITION | max_buy_in must be >= min_buy_in |
      | Test | 0           | 10        | 100        | 1000       | 6           | INVALID_ARGUMENT    | small_blind                  |
      | Test | 20          | 10        | 100        | 1000       | 6           | FAILED_PRECONDITION | big_blind must be >=         |
      | Test | 5           | 0         | 100        | 1000       | 6           | FAILED_PRECONDITION | big_blind must be >= small_blind |
      | Test | 5           | 10        | 100        | 1000       | 1           | FAILED_PRECONDITION | max_players must be 2-10     |
      | Test | 5           | 10        | 100        | 1000       | 11          | FAILED_PRECONDITION | max_players must be 2-10     |

  @EU-0532
  Scenario: CreateTable requires a table_name
    Given no prior events for the table aggregate
    When I handle a CreateTable command with name "" and variant "TEXAS_HOLDEM":
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 6           |
    Then the command fails with status "FAILED_PRECONDITION"
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
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "cannot exceed"

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
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "player_root"

  @EU-0536
  Scenario: JoinTable rejects occupied preferred seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 3
    When I handle a JoinTable command for player "player-2" at seat 3 with buy-in 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Seat is occupied"

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
    Then the command fails with status "FAILED_PRECONDITION"
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
    Then the result is a examples.HandStarted event
    And the small_blind_position equals the dealer_position

  @EU-0544
  Scenario: StartHand with 3 players: SB is left of dealer
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    And a PlayerJoined event for player "player-2" at seat 1
    And a PlayerJoined event for player "player-3" at seat 2
    When I handle a StartHand command
    Then the result is a examples.HandStarted event
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
    Then the result is a examples.PlayerJoined event
    And the table event has seat_position 0

  @EU-0551
  Scenario: Negative preferred_seat picks the next available seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-1" at seat 0
    When I handle a JoinTable command for player "player-2" at seat -1 with buy-in 500
    Then the result is a examples.PlayerJoined event
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
    Then the result is a examples.PlayerSeated event
    And the seating event has seat_position 0
    And the seating event has stack 500

  @EU-0554
  Scenario: SeatPlayer emits SeatingRejected when amount is below minimum
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 100
    Then the result is a examples.SeatingRejected event
    And the seating rejection reason contains "at least"

  @EU-0555
  Scenario: SeatPlayer emits SeatingRejected when amount exceeds maximum
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 5000
    Then the result is a examples.SeatingRejected event
    And the seating rejection reason contains "above maximum"

  @EU-0556
  Scenario: SeatPlayer emits SeatingRejected when requested seat is occupied
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-b" at seat 0
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 0 amount 500
    Then the result is a examples.SeatingRejected event
    And the seating rejection reason contains "occupied"

  @EU-0557
  Scenario: SeatPlayer emits SeatingRejected when player is already seated
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-a" at seat 1
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat 2 amount 500
    Then the result is a examples.SeatingRejected event
    And the seating rejection reason contains "already seated"

  @EU-0558
  Scenario: SeatPlayer with seat -1 picks the next available seat
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-b" at seat 0
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat -1 amount 500
    Then the result is a examples.PlayerSeated event
    And the seating event has seat_position 1

  @EU-0559
  Scenario: SeatPlayer with seat -1 rejects when table is full
    Given a TableCreated event for "Main Table" with max_players 2
    And a PlayerJoined event for player "player-b" at seat 0
    And a PlayerJoined event for player "player-c" at seat 1
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat -1 amount 500
    Then the result is a examples.SeatingRejected event
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
    Then the result is a examples.RebuyChipsAdded event
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
    Then the result is a examples.SeatingRejected event
    And the seating rejection reason contains "player_root"

  @EU-0572
  Scenario: SeatPlayer emits SeatingRejected when seat is out of range
    Given a TableCreated event for "Main Table"
    When I handle a SeatPlayer command for player "player-a" reservation "res-001" seat -5 amount 500
    Then the result is a examples.SeatingRejected event
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
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "player_root"
