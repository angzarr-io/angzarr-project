# Allocated: EU-0100 .. EU-0120, EU-0531 .. EU-0567, EU-0570 .. EU-0574,
#            EU-0575 .. EU-0578, EU-1180 .. EU-1188
Feature: Table aggregate logic
  The Table aggregate manages a poker table session: configuration, player
  seating, and hand lifecycle. It's the orchestration layer between players
  (who have money) and hands (where money changes ownership).

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  #   TDA       = Poker Tournament Directors Association Rules, 2024 v1.0
  #               (Oct 9, 2024). Canonical at https://www.pokertda.com/.
  #               Rule numbers refer to the longform document.
  #   TDA-RP    = TDA Recommended Procedures (longform addendum).
  #   Robert's  = Robert's Rules of Poker, Bob Ciaffone v11.
  # See angzarr docs site or features/example/RULES.md for the full
  # cross-reference between scenarios and rule sources.

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
  # Rule: WSOP §IX (2025) — variant choice, max-handed configuration (2-10
  #       for flop games, 7 for Big-O, 8 for stud, 6/7/8 for short-deck).
  # (Framework: configuration validation — blinds, buy-in bounds, max
  # players. The non-poker side of table creation is event-sourcing
  # idempotency: cannot create the same table twice.)
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
  # Rule: TDA Rule 7 (2024) / WSOP Rule 34/65 (2025) — random seat
  #       assignment in tournament events (cash play allows preferred seat).
  # Rule: WSOP §I-13 (2025) — re-entry: zero chips remaining required.
  # Rule: TDA Rule 8A / WSOP §I-14 (2025) — late entrants get full stack.
  # (Framework: seat occupancy is enforced; one player per seat at most.
  # Buy-in bounds enforce per-table min/max chip configuration.)
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
  # Rule: TDA Rule 31 (2024) — players with action pending must remain at
  #       the table; mid-hand departure is incompatible with protecting
  #       the hand and following the action.
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
  # Rule: TDA Rule 32 (2024) — tournament play uses a dead button.
  # Rule: TDA Rule 34B (2024) — heads-up: SB is the button, dealt last,
  #       acts first preflop and last on subsequent betting rounds.
  # Rule: WSOP §IX Flop Games (2025) — minimum 2 players to deal.
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
  # (Framework: stack reconciliation between hand outcome and table seat
  # state. The poker rules driving the WIN/LOSS amounts are codified in
  # the Hand aggregate — see hand.feature side-pots, antes, and
  # showdown sections.)
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
  # (Framework: event-replay correctness. Not a poker rule — pins that
  # the rules above produce a consistent rebuilt state from any prefix
  # of the table's event stream.)
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
  # (Framework: input validation for table configuration. Bounds are
  # WSOP/TDA-derived — small_blind/big_blind sanity, max_players ≤ 10
  # for flop games per WSOP §IX, but the validation logic itself is
  # framework, not a poker rule.)
  # Rule: WSOP §IX Flop Games (2025) — 2-10 player range.
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
  # (Framework: input validation for join requests. Buy-in min/max enforce
  # the per-table economics; seat occupancy enforces the universal poker
  # constraint that one seat = at most one player.)
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
  # (Framework: input validation for leave requests.)

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
  # Rule: TDA Rule 32 + 34B (2024) — dead button + heads-up button = SB,
  #       carried over from the Hand Lifecycle - Start section above.
  # (Framework: pre-condition gates for StartHand / EndHand.)

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
  # (Framework: state-projection accessors. table_id derivation, is_full
  # check, sit-in/sit-out tracking. Sitting-out is a simulable conse-
  # quence of TDA Rule 30 — players away from table can be marked
  # sitting out so blinds skip them or are paid into the pot.)

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
  # (Framework: event-replay applier correctness — PlayerSatIn,
  # ChipsAdded, etc. project into table state.)

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
  # (Framework: scenarios that pin behavior identically across language
  # implementations — seat 0 is valid, negative preferred_seat picks
  # next available.)

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
  # (Framework: end-to-end create → join → start hand → end hand → leave
  # round-trip on a single aggregate. Exercises the rule sections above
  # in sequence.)

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
  # Rule: TDA Rule 7 / WSOP Rule 34 (2025) — random tournament seating.
  # (Framework: PM-orchestrated seat assignment. Rejections become
  # SeatingRejected events so the PM can compensate by releasing the
  # buy-in reservation. The rules driving rejections — buy-in bounds,
  # seat occupancy, table fullness — are inherited from Player Seating
  # and Join Validation sections above.)
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
  # Rule: TDA Rule 27 (2024) — re-buys allowed during running tournament;
  #       declared rebuy plays chips behind.
  # (Framework: PM-orchestrated chip top-up. Raises rather than emitting
  # an event because the rebuy PM has already reserved funds — pre-
  # conditions cannot fail at this stage.)
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
  # (Framework: command-level guard rejections vs event-level rejections.
  # Documents the dual-mode rejection strategy: table-existence checks
  # raise; everything else emits a rejection event for PM compensation.)
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
  # Rule: TDA Rule 32 (2024) — "Tournament play will use a dead button."
  # Rule: TDA Rule 34B (2024) — "Heads-up, the small blind is the button …
  #       Starting heads-up play, the button may need to be adjusted to
  #       ensure no player has the big blind twice in a row."
  # When a player in or near the blind position is eliminated between
  # hands, the button advances using the "dead button" rule rather than
  # naive +1. The intent: every player gets the BB exactly once per
  # orbit. Specifically:
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
  Scenario: Three players collapse to heads-up — button advances, dealer is SB
    # 3-handed: dealer 0, SB 1, BB 2. player-B (SB seat 1) busts during
    # hand 1. Heads-up next hand: TDA Rule 6 says the button alternates
    # — so the button moves clockwise to the next active player. With
    # seat 1 vacated, the next active seat after the prior dealer (0)
    # is seat 2. Player-C is now dealer (and SB by the heads-up rule);
    # player-A is BB. This satisfies the orbit invariant that BB does
    # not repeat the same occupant on consecutive hands (also tested
    # in EU-0578).
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "player-A" at seat 0
    And a PlayerJoined event for player "player-C" at seat 2
    And a HandStarted event for hand 1 with dealer at seat 0
    And a HandEnded event for hand 1
    And player "player-B" busted at seat 1 during hand 1
    When I handle a StartHand command
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the small_blind_position equals the dealer_position
    And the dealer_position is seat 2
    And the big_blind_position is seat 0

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

  # ==========================================================================
  # Table Balancing — TDA Rule 11A
  # ==========================================================================
  # Real poker (TDA Rule 11A): "To balance in flop and mixed-games, the
  # player to be big blind next moves to the worst position, including
  # single big blind if available, even if that means the seat is big
  # blind twice. Worst position is never the small blind." The cluster-
  # tier @wip EA-0012 covers the multi-table cluster integration; this
  # unit scenario pins the deterministic per-table algorithm.

  @EU-1180 @wip
  Scenario: Balancing moves the BB-next player from the larger table to the worst seat at the shorter table
    # Rule: TDA Rule 11A (2024) — "the player to be big blind next moves to
    #       the worst position ... Worst position is never the small blind."
    # Source table: 4 players (Alice/Bob/Carol/Dave at seats 0/1/2/3),
    # current dealer at seat 0 (Alice). The BB-next is the player who would
    # be BB on the upcoming hand — at a 4-handed table with dealer 0 that's
    # seat 3 (Dave). Dave is the player who must move.
    # Destination table: short table with 2 players, dealer about to be at
    # seat 0. The "worst position" — never the small blind — is the seat
    # immediately to the right of the would-be small blind, i.e. the BB
    # position (or single-BB if the source table has SB filled).
    Given a TableCreated event for "Source"
    And a PlayerJoined event for player "Alice" at seat 0
    And a PlayerJoined event for player "Bob" at seat 1
    And a PlayerJoined event for player "Carol" at seat 2
    And a PlayerJoined event for player "Dave" at seat 3
    And the source table has the dealer button at seat 0
    And a TableCreated event for "Dest"
    And a PlayerJoined event for player "Eve" at seat 0 of "Dest"
    And a PlayerJoined event for player "Frank" at seat 1 of "Dest"
    When I handle a BalanceTables command moving from "Source" to "Dest"
    Then the result is a angzarr_client.proto.examples.PlayerMovedBetweenTables event
    And the moved player is "Dave"
    And the moved player's destination seat at "Dest" is the BB position (not the SB position)

  @EU-1181 @wip
  Scenario: Final-table combination — 9-handed event collapses 2 tables of 5 to one final table of 9
    # Rule: TDA RP-9 (2024) — "9 and 8-handed events will combine from two
    #       tables of five players each to a 9-handed final table."
    # Two 5-handed tables with one elimination remaining before the final
    # table. After the next bust, the remaining 9 players are seated at a
    # single final table by random redraw.
    Given a TableCreated event for "Semi-1"
    And a PlayerJoined event for player "Alice" at seat 0
    And a PlayerJoined event for player "Bob" at seat 1
    And a PlayerJoined event for player "Carol" at seat 2
    And a PlayerJoined event for player "Dave" at seat 3
    And a PlayerJoined event for player "Eve" at seat 4
    And a TableCreated event for "Semi-2"
    And a PlayerJoined event for player "Frank" at seat 0 of "Semi-2"
    And a PlayerJoined event for player "Grace" at seat 1 of "Semi-2"
    And a PlayerJoined event for player "Henry" at seat 2 of "Semi-2"
    And a PlayerJoined event for player "Ivy"   at seat 3 of "Semi-2"
    And a PlayerJoined event for player "Jack"  at seat 4 of "Semi-2"
    When I handle a CombineFinalTable command for "Final" combining "Semi-1,Semi-2"
    Then the result is a angzarr_client.proto.examples.FinalTableCombined event
    And the final table has 9 active_players
    And every original player has been reseated at "Final"
    And "Semi-1" status is "broken"
    And "Semi-2" status is "broken"

  # ==========================================================================
  # Random Seat Assignment — TDA Rule 7 / WSOP Rule 34/65
  # ==========================================================================
  # Real poker (TDA Rule 7): "Tournament and satellite seats will be randomly
  # assigned." WSOP Rule 34: "Entrants will be assigned to a table and seat
  # through a random computer selection." The current SeatPlayer flow with
  # seat=-1 picks the next *available* seat — this is fine for cash play
  # but tournament seating must be RNG-driven.

  @EU-1182 @wip
  Scenario: Tournament seat assignment is uniformly random among available seats
    # Rule: TDA Rule 7 (2024) — random correct seating.
    # Rule: WSOP Rule 34 (2025) — random computer selection.
    Given a TableCreated event for "Random-1" tagged for tournament play
    And seats 0, 2, 5, and 7 are unoccupied
    When I handle a SeatPlayer command for player "Alice" with seat -1 amount 1500 in tournament mode
    Then the result is a angzarr_client.proto.examples.PlayerSeated event
    And the seating event has seat_position drawn uniformly at random from {0, 2, 5, 7}
    And the seating event has rng_seed populated for replay determinism

  # ==========================================================================
  # Broken-Table Reseating — TDA Rule 10A
  # ==========================================================================
  # Real poker (TDA Rule 10A): "New players entering the tournament and
  # players from broken tables can get any seat including the small or big
  # blind or the button and be dealt in except between the SB and button."

  @EU-1183 @wip
  Scenario: Broken-table player can take any seat except between SB and button
    # Rule: TDA Rule 10A (2024).
    # Source table is broken; Eve (a moved player) joins the destination
    # table. The destination has dealer at seat 0 (Alice), SB seat 1 (Bob),
    # BB seat 2 (Carol), Dave at seat 3, and seats 4, 5 open. The forbidden
    # seat range is "between SB and button" — for a 6-handed table with
    # button at 0 and SB at 1, the seat between them on the same hand
    # doesn't exist; for an 8-handed table with seats 4 and 5 open AFTER
    # the button on the next deal, those are legal. The rule guards against
    # being dealt in to a position that has already received cards on the
    # current orbit.
    Given a TableCreated event for "Dest"
    And a PlayerJoined event for player "Alice" at seat 0 (button)
    And a PlayerJoined event for player "Bob" at seat 1 (SB)
    And a PlayerJoined event for player "Carol" at seat 2 (BB)
    And a PlayerJoined event for player "Dave" at seat 3
    And seats 4, 5, 6, 7 are open
    And a hand has been dealt at "Dest" with substantial action this orbit
    When I handle a SeatPlayer command for moved player "Eve" at seat 4 amount 1500
    Then the result is a angzarr_client.proto.examples.PlayerSeated event
    And player "Eve" is dealt out of the current hand
    And player "Eve" is dealt in starting the next hand

  # ==========================================================================
  # Halt Play When Short — TDA Rule 11D
  # ==========================================================================
  # Real poker (TDA Rule 11D): "Play will halt on tables 3 or more players
  # short (by elimination) than the table with the most players once the
  # blinds are impacted."

  @EU-1184 @wip
  Scenario: Play halts on a short table when 3+ behind once the blinds are impacted
    # Rule: TDA Rule 11D (2024).
    # 9-handed event. Source table A has 8 players. Short table B has 5.
    # The difference is 3, which triggers halt-play once the blinds at B
    # are impacted (i.e. when the BB hits an open seat at B).
    Given a TableCreated event for "Table-A" with 8 active players
    And a TableCreated event for "Table-B" with 5 active players
    When the next hand at "Table-B" would assign the BB to an empty seat
    Then a angzarr_client.proto.examples.TableHaltedForBalancing event is emitted for "Table-B"
    And "Table-B" status is "halted_for_balancing"

  # ==========================================================================
  # Dodging Blinds Penalty — TDA Rule 33 / WSOP Rule 86
  # ==========================================================================
  # Real poker (TDA Rule 33 + WSOP Rule 86): "A Participant who intentionally
  # dodges his or her blind(s) when moving from an existing seat must
  # forfeit both blinds (and BBA if applicable) and will receive a one (1)
  # round penalty."

  @EU-1185 @wip
  Scenario: A player who skips a blind by moving forfeits the missed blinds and earns a round penalty
    # Rule: TDA Rule 33 (2024) + WSOP Rule 86 (2025).
    Given a TableCreated event for "Main Table" with blinds 5/10
    And a PlayerJoined event for player "Alice" at seat 1
    And the next hand would post Alice's BB
    When player "Alice" requests a seat change to seat 4 to skip her blind
    Then a angzarr_client.proto.examples.BlindDodgePenalty event is emitted
    And the penalty event has player_root "Alice"
    And the penalty event has chips_forfeited 15
    And the penalty event has missed_round_count 1

  # ==========================================================================
  # Initial Button Placement — WSOP Rule 85
  # ==========================================================================
  # WSOP-specific (Rule 85): "At the start of an Event, the button will
  # begin in the seat with the first chip stack to the dealer's right."
  # Operationally: the button on hand 1 of any new table is *deterministic*
  # given the seat-occupancy list, not a coin flip.

  @EU-1186 @wip
  Scenario: Initial button placement on hand 1 starts at the seat to the dealer's right
    # Rule: WSOP Rule 85 (2025) — initial button placement.
    # Dealer position (the dealer person, not the button) is at seat 0.
    # First chip stack to the dealer's right (counter-clockwise) is the
    # highest seat number with a player. With seats 1, 3, 5 occupied,
    # the button starts at seat 5.
    Given a TableCreated event for "Main Table"
    And a PlayerJoined event for player "Alice" at seat 1
    And a PlayerJoined event for player "Bob" at seat 3
    And a PlayerJoined event for player "Carol" at seat 5
    When I handle a StartHand command for the first hand
    Then the result is a angzarr_client.proto.examples.HandStarted event
    And the table event has hand_number 1
    And the table event has dealer_position 5

  # ==========================================================================
  # Final-Table Combination Thresholds — TDA RP-9 / WSOP Rule 68
  # ==========================================================================
  # Real poker (TDA RP-9 + WSOP Rule 68): final-table combination point
  # depends on the event's max-handed configuration:
  #   9-handed event → combine to FT with 10 remaining (5+5 → 9 was EU-1181)
  #   8-handed event → combine to FT with 9 remaining (4+5 → 8)
  #   7-handed event → combine to FT with 8 remaining (4+4 → 7)
  #   6-handed event → combine to FT with 7 remaining (4+3 → 6)

  @EU-1187 @wip
  Scenario: 8-handed event combines 2 tables of 4 and 5 to a final table of 9 then 8
    # Rule: WSOP Rule 68b (2025) — 8-handed → combine at 9 remaining.
    Given an 8-handed tournament with 9 active players across "Semi-1" and "Semi-2"
    And "Semi-1" has 4 players "Alice,Bob,Carol,Dave"
    And "Semi-2" has 5 players "Eve,Frank,Grace,Henry,Ivy"
    When I handle a CombineFinalTable command for "Final" combining "Semi-1,Semi-2"
    Then the result is a angzarr_client.proto.examples.FinalTableCombined event
    And the final table has 9 active_players
    And the final table is configured as 8-handed

  @EU-1188 @wip
  Scenario: 6-handed event combines at 7 remaining
    # Rule: WSOP Rule 68d (2025) — 6-handed → combine at 7 remaining.
    Given a 6-handed tournament with 7 active players across "Semi-1" and "Semi-2"
    And "Semi-1" has 4 players "Alice,Bob,Carol,Dave"
    And "Semi-2" has 3 players "Eve,Frank,Grace"
    When I handle a CombineFinalTable command for "Final" combining "Semi-1,Semi-2"
    Then the result is a angzarr_client.proto.examples.FinalTableCombined event
    And the final table has 7 active_players
    And the final table is configured as 6-handed
