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

  # Why this aggregate exists:
  # - Tables have configuration (blinds, limits) that hands inherit
  # - Player seating is table-scoped, not hand-scoped
  # - Dealer button and hand numbering track across multiple hands
  # - Players join/leave tables, not individual hands

  # What breaks if this is wrong:
  # - Players could be double-seated at the same table
  # - Hands could start with insufficient players
  # - Dealer button wouldn't advance correctly

  # Patterns enabled by this aggregate:
  # - Cross-aggregate coordination: Table emits HandStarted, triggering saga to
    # create Hand aggregate. Same pattern applies to order→fulfillment, auction→bid.
  # - Slot/capacity management: Seats are exclusive resources with validation.
    # Same pattern applies to parking spots, meeting room bookings, flight seats.
  # - Child aggregate lifecycle: Table spawns hands, tracks their completion,
    # updates state. Same pattern applies to project→tasks, tournament→matches.

  # Why poker exercises these patterns well:
  # - Seat occupancy is binary and obvious: seat 3 either has a player or doesn't
  # - Hand lifecycle has clear start/end: HandStarted→HandEnded, easy to verify
  # - Configuration inheritance is explicit: blinds flow from table to hand
  # - Concurrent state is visible: 2 players at seats 0,3 while seats 1,2 empty

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

  @wip
  @EU-0100
  Scenario: Create a Texas Hold'em table
    Given the table has not yet been created
    When a Texas Hold'em table named "Main Table" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 200        | 1000       | 9           |
    Then the table is named "Main Table"
    And the table is configured as a Texas Hold'em game
    And the blinds are 5/10

  @wip
  @EU-0101
  Scenario: Create a Five Card Draw table
    Given the table has not yet been created
    When a Five Card Draw table named "Draw Table" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 10          | 20        | 400        | 2000       | 6           |
    Then the table is configured as a Five Card Draw game

  @wip
  @EU-0102
  Scenario: Cannot create table twice
    Given a table "Main Table" exists
    When a Texas Hold'em table named "Another Table" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 200        | 1000       | 9           |
    Then the create-table is refused because the table already exists

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

  @wip
  @EU-0103
  Scenario: Player joins table at preferred seat
    Given a table "Main Table" exists
    When player "player-1" joins the table at seat 3 with a buy-in of 500
    Then player "player-1" is seated at position 3 with a 500-chip stack

  @wip
  @EU-0104
  Scenario: Player joins table at any seat
    Given a table "Main Table" exists
    When player "player-1" joins the table at any available seat with a buy-in of 500
    Then player "player-1" is seated at position 0

  @wip
  @EU-0105
  Scenario: Cannot join occupied seat
    Given a table "Main Table" exists
    And player "player-1" is seated at position 3
    When player "player-2" joins the table at seat 3 with a buy-in of 500
    Then the join is refused because seat 3 is already occupied

  @wip
  @EU-0106
  Scenario: Cannot join table twice
    Given a table "Main Table" exists
    And player "player-1" is seated at position 3
    When player "player-1" joins the table at seat 5 with a buy-in of 500
    Then the join is refused because the player is already seated

  @wip
  @EU-0107
  Scenario: Cannot join with insufficient buy-in
    Given a table "Main Table" exists with a minimum buy-in of 200
    When player "player-1" joins the table at seat 0 with a buy-in of 100
    Then the join is refused because the buy-in of 100 is below the table minimum of 200

  @wip
  @EU-0108
  Scenario: Cannot join full table
    Given a table "Main Table" exists with a maximum of 2 players
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    When player "player-3" joins the table at any available seat with a buy-in of 500
    Then the join is refused because the table is full

  # ==========================================================================
  # Player Departure
  # ==========================================================================
  # Rule: TDA Rule 31 (2024) — players with action pending must remain at
  #       the table; mid-hand departure is incompatible with protecting
  #       the hand and following the action.
  # Players leave with their remaining stack (may differ from buy-in).
  # Departure during an active hand is forbidden - the player must wait
  # for the hand to complete. This prevents mid-hand bailouts.

  @wip
  @EU-0109
  Scenario: Player leaves table
    Given a table "Main Table" exists
    And player "player-1" is seated at position 3 with a 500-chip stack
    When player "player-1" leaves the table
    Then player "player-1" cashes out 500 chips

  @wip
  @EU-0110
  Scenario: Cannot leave during hand
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And the first hand at the table has begun
    When player "player-1" leaves the table
    Then the leave is refused because a hand is in progress

  @wip
  @EU-0111
  Scenario: Cannot leave table not joined
    Given a table "Main Table" exists
    When player "player-1" leaves the table
    Then the leave is refused because the player is not seated

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

  @wip
  @EU-0112
  Scenario: Start a new hand
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0 with a 500-chip stack
    And player "player-2" is seated at position 1 with a 500-chip stack
    When the next hand at the table begins
    Then the table is on hand number 1 with 2 active players

  @wip
  @EU-0113
  Scenario: Dealer button advances each hand
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And hand 1 was played with the dealer at seat 0 and has ended
    When the next hand at the table begins
    Then the table is on hand number 2
    And the dealer is at seat 1

  @wip
  @EU-0114
  Scenario: Cannot start hand with fewer than 2 players
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    When the next hand at the table begins
    Then the start-hand is refused because there are not enough players

  @wip
  @EU-0115
  Scenario: Cannot start hand while one is in progress
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And the first hand at the table has begun
    When the next hand at the table begins
    Then the start-hand is refused because a hand is already in progress

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

  @wip
  @EU-0116
  Scenario: End hand and update stacks
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0 with a 500-chip stack
    And player "player-2" is seated at position 1 with a 500-chip stack
    And the first hand at the table has begun
    When the hand ends with "player-1" winning 50
    Then player "player-1"'s stack change is 50

  @wip
  @EU-0117
  Scenario: Cannot end hand not in progress
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    When the hand ends with "player-1" winning 50
    Then the end-hand is refused because no hand is in progress

  @wip
  @EU-0118
  Scenario: End hand updates player stacks with wins and losses
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0 with a 500-chip stack
    And player "player-2" is seated at position 1 with a 500-chip stack
    And the first hand at the table has begun
    When the hand ends with the following results:
      | player   | change |
      | player-1 | 150    |
      | player-2 | -150   |
    Then player "player-1"'s stack change is 150
    And player "player-2"'s stack change is -150

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # (Framework: event-replay correctness. Not a poker rule — pins that
  # the rules above produce a consistent rebuilt state from any prefix
  # of the table's event stream.)
  # Table state is rebuilt by replaying events. This verifies that joining,
  # leaving, and hand events correctly update seated players and table status.

  @wip
  @EU-0119
  Scenario: Rebuild state with multiple players
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0 with a 500-chip stack
    And player "player-2" is seated at position 3 with an 800-chip stack
    Then the table has 2 seated players
    And seat 0 is occupied by "player-1"
    And seat 3 is occupied by "player-2"
    And the table is waiting for a hand to start

  @wip
  @EU-0120
  Scenario: Rebuild state during hand
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And the first hand at the table has begun
    Then a hand is in progress at the table
    And the table has played 1 hand

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

  @wip
  @EU-0531
  Scenario: CreateTable rejects non-positive min_buy_in
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 0          | 1000       | 6           |
    Then the create-table is refused because the minimum buy-in must be positive

  @wip
  @EU-0531
  Scenario: CreateTable rejects max_buy_in below min_buy_in
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 500        | 100        | 6           |
    Then the create-table is refused because the maximum buy-in of 100 must exceed the minimum buy-in of 500

  @wip
  @EU-0531
  Scenario: CreateTable rejects non-positive small_blind
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 0           | 10        | 100        | 1000       | 6           |
    Then the create-table is refused because the small blind must be positive

  @wip
  @EU-0531
  Scenario: CreateTable rejects big_blind below small_blind
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 20          | 10        | 100        | 1000       | 6           |
    Then the create-table is refused because the big blind of 10 must exceed the small blind of 20

  @wip
  @EU-0531
  Scenario: CreateTable rejects zero big_blind
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 0         | 100        | 1000       | 6           |
    Then the create-table is refused because the big blind of 0 must exceed the small blind of 5

  @wip
  @EU-0531
  Scenario: CreateTable rejects max_players below 2
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 1           |
    Then the create-table is refused because max_players of 1 is out of the allowed 2-10 range

  @wip
  @EU-0531
  Scenario: CreateTable rejects max_players above 10
    Given the table has not yet been created
    When a Texas Hold'em table named "Test" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 11          |
    Then the create-table is refused because max_players of 11 is out of the allowed 2-10 range

  @wip
  @EU-0532
  Scenario: CreateTable requires a table_name
    Given the table has not yet been created
    When a Texas Hold'em table named "" is created with:
      | small_blind | big_blind | min_buy_in | max_buy_in | max_players |
      | 5           | 10        | 100        | 1000       | 6           |
    Then the create-table is refused because a table name is required

  # ==========================================================================
  # Join Validation (Phase 2)
  # ==========================================================================
  # (Framework: input validation for join requests. Buy-in min/max enforce
  # the per-table economics; seat occupancy enforces the universal poker
  # constraint that one seat = at most one player.)
  # Joining requires an existing table, a player_root, and a buy-in that
  # fits within the configured bounds. Preferred-seat occupancy is checked
  # before the any-seat fallback.

  @wip
  @EU-0533
  Scenario: JoinTable rejects when buy-in exceeds max
    Given a table "Main Table" exists
    When player "player-1" joins the table at seat 0 with a buy-in of 5000
    Then the join is refused because the buy-in of 5000 is above the table maximum of 1000

  @wip
  @EU-0534
  Scenario: JoinTable rejects when table does not exist
    Given the table has not yet been created
    When player "player-1" joins the table at seat 0 with a buy-in of 500
    Then the join is refused because the table does not exist

  @wip
  @EU-0535
  Scenario: JoinTable requires a player_root
    Given a table "Main Table" exists
    When player "" joins the table at seat 0 with a buy-in of 500
    Then the join is refused because a player identity is required

  @wip
  @EU-0536
  Scenario: JoinTable rejects occupied preferred seat
    Given a table "Main Table" exists
    And player "player-1" is seated at position 3
    When player "player-2" joins the table at seat 3 with a buy-in of 500
    Then the join is refused because seat 3 is already occupied

  # ==========================================================================
  # Leave Validation (Phase 2)
  # ==========================================================================
  # (Framework: input validation for leave requests.)

  @wip
  @EU-0537
  Scenario: LeaveTable rejects when table does not exist
    Given the table has not yet been created
    When player "player-1" leaves the table
    Then the leave is refused because the table does not exist

  @wip
  @EU-0538
  Scenario: LeaveTable requires a player_root
    Given a table "Main Table" exists
    When player "" leaves the table
    Then the leave is refused because a player identity is required

  # ==========================================================================
  # Hand Lifecycle Validation (Phase 2)
  # ==========================================================================
  # Rule: TDA Rule 32 + 34B (2024) — dead button + heads-up button = SB,
  #       carried over from the Hand Lifecycle - Start section above.
  # (Framework: pre-condition gates for StartHand / EndHand.)

  @wip
  @EU-0539
  Scenario: StartHand rejects when table does not exist
    Given the table has not yet been created
    When the next hand at the table begins
    Then the start-hand is refused because the table does not exist

  @wip
  @EU-0540
  Scenario: EndHand rejects when table does not exist
    Given the table has not yet been created
    When the hand ends with "player-1" winning 50
    Then the end-hand is refused because the table does not exist

  @wip
  @EU-0541
  Scenario: EndHand rejects mismatched hand_root
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And the first hand at the table has begun
    When the hand ends but the hand identity does not match the one in progress
    Then the end-hand is refused because the hand identity does not match

  @wip
  @EU-0542
  Scenario: EndHand transitions status back to waiting
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    When a hand is started and then ended with "player-1" winning 100
    Then the table is waiting for a hand to start
    And no hand is currently in progress at the table

  @wip
  @EU-0543
  Scenario: StartHand in heads-up: dealer posts small blind
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    When the next hand at the table begins
    Then the dealer is the small blind for the heads-up hand

  @wip
  @EU-0544
  Scenario: StartHand with 3 players: SB is left of dealer
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And player "player-3" is seated at position 2
    When the next hand at the table begins
    Then the small blind is in a different seat from the dealer

  # ==========================================================================
  # State Accessors (Phase 2)
  # ==========================================================================
  # (Framework: state-projection accessors. table_id derivation, is_full
  # check, sit-in/sit-out tracking. Sitting-out is a simulable conse-
  # quence of TDA Rule 30 — players away from table can be marked
  # sitting out so blinds skip them or are paid into the pot.)

  @wip
  @EU-0545
  Scenario: Table id is derived from the table name
    Given a table "High Stakes" exists
    Then the table carries the identity derived from its name "High Stakes"

  @wip
  @EU-0546
  Scenario: is_full becomes true when max_players reached
    Given a table "Main Table" exists with a maximum of 2 players
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    Then the table is full

  @wip
  @EU-0547
  Scenario: active_player_count excludes sitting-out players
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-2" is seated at position 1
    And player "player-1" is sitting out
    Then the table has 2 seated players
    And 1 player is currently active at the table

  # ==========================================================================
  # Event Replay (Phase 2)
  # ==========================================================================
  # (Framework: event-replay applier correctness — PlayerSatIn,
  # ChipsAdded, etc. project into table state.)

  @wip
  @EU-0548
  Scenario: PlayerSatIn restores a sat-out player to active
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    And player "player-1" is sitting out
    And player "player-1" sits back in
    Then 1 player is currently active at the table

  @wip
  @EU-0549
  Scenario: ChipsAdded updates the player stack via re-buy
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0 with a 500-chip stack
    And player "player-1" re-buys to bring the stack to 800
    Then the player at seat 0 has an 800-chip stack

  # ==========================================================================
  # Cross-language Consistency (Phase 2)
  # ==========================================================================
  # (Framework: scenarios that pin behavior identically across language
  # implementations — seat 0 is valid, negative preferred_seat picks
  # next available.)

  @wip
  @EU-0550
  Scenario: Seat 0 is an explicit valid preferred seat
    Given a table "Main Table" exists
    When player "player-1" joins the table at seat 0 with a buy-in of 500
    Then player "player-1" is seated at position 0

  @wip
  @EU-0551
  Scenario: Negative preferred_seat picks the next available seat
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0
    When player "player-2" joins the table at any available seat with a buy-in of 500
    Then player "player-2" is seated at position 1

  # ==========================================================================
  # Full Lifecycle (Phase 2)
  # ==========================================================================
  # (Framework: end-to-end create → join → start hand → end hand → leave
  # round-trip on a single aggregate. Exercises the rule sections above
  # in sequence.)

  @wip
  @EU-0552
  Scenario: Full create/join/start/end/leave lifecycle
    Given a table "Main Table" exists
    And player "player-1" is seated at position 0 with a 500-chip stack
    And player "player-2" is seated at position 1 with a 500-chip stack
    When a hand is started and then ended with "player-1" winning 100
    Then the table is waiting for a hand to start

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

  @wip
  @EU-0553
  Scenario: SeatPlayer emits PlayerSeated on success
    Given a table "Main Table" exists
    When player "player-a" is seated at position 0 with reservation "res-001" for 500 chips
    Then player "player-a" is seated at position 0 with a 500-chip stack

  @wip
  @EU-0554
  Scenario: SeatPlayer emits SeatingRejected when amount is below minimum
    Given a table "Main Table" exists
    When player "player-a" is seated at position 0 with reservation "res-001" for 100 chips
    Then the seating is rejected because the amount is below the table minimum

  @wip
  @EU-0555
  Scenario: SeatPlayer emits SeatingRejected when amount exceeds maximum
    Given a table "Main Table" exists
    When player "player-a" is seated at position 0 with reservation "res-001" for 5000 chips
    Then the seating is rejected because the amount is above the table maximum

  @wip
  @EU-0556
  Scenario: SeatPlayer emits SeatingRejected when requested seat is occupied
    Given a table "Main Table" exists
    And player "player-b" is seated at position 0
    When player "player-a" is seated at position 0 with reservation "res-001" for 500 chips
    Then the seating is rejected because the seat is already occupied

  @wip
  @EU-0557
  Scenario: SeatPlayer emits SeatingRejected when player is already seated
    Given a table "Main Table" exists
    And player "player-a" is seated at position 1
    When player "player-a" is seated at position 2 with reservation "res-001" for 500 chips
    Then the seating is rejected because the player is already seated

  @wip
  @EU-0558
  Scenario: SeatPlayer with seat -1 picks the next available seat
    Given a table "Main Table" exists
    And player "player-b" is seated at position 0
    When player "player-a" is seated at any available seat with reservation "res-001" for 500 chips
    Then player "player-a" is seated at position 1

  @wip
  @EU-0559
  Scenario: SeatPlayer with seat -1 rejects when table is full
    Given a table "Main Table" exists with a maximum of 2 players
    And player "player-b" is seated at position 0
    And player "player-c" is seated at position 1
    When player "player-a" is seated at any available seat with reservation "res-001" for 500 chips
    Then the seating is rejected because the table is full

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

  @wip
  @EU-0560
  Scenario: AddRebuyChips emits RebuyChipsAdded with new stack
    Given a table "Main Table" exists
    And player "player-a" is seated at position 2 with a 500-chip stack
    When player "player-a" re-buys 1000 chips with reservation "res-001" at seat 2
    Then player "player-a" at seat 2 has a stack of 1500 after adding 1000 chips

  @wip
  @EU-0561
  Scenario: AddRebuyChips rejects when the player is not seated
    Given a table "Main Table" exists
    When player "player-a" re-buys 1000 chips with reservation "res-001" at seat 2
    Then the re-buy is refused because the player is not seated

  @wip
  @EU-0562
  Scenario: AddRebuyChips rejects when seat does not match
    Given a table "Main Table" exists
    And player "player-a" is seated at position 2 with a 500-chip stack
    When player "player-a" re-buys 1000 chips with reservation "res-001" at seat 3
    Then the re-buy is refused because the seat does not match the player's seat

  @wip
  @EU-0563
  Scenario: AddRebuyChips rejects a non-positive amount
    Given a table "Main Table" exists
    And player "player-a" is seated at position 2 with a 500-chip stack
    When player "player-a" re-buys 0 chips with reservation "res-001" at seat 2
    Then the re-buy is refused because the amount must be positive

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

  @wip
  @EU-0570
  Scenario: SeatPlayer rejects when the table does not exist
    Given the table has not yet been created
    When player "player-a" is seated at position 0 with reservation "res-001" for 500 chips
    Then the seat-player is refused because the table does not exist

  @wip
  @EU-0571
  Scenario: SeatPlayer emits SeatingRejected when player_root is empty
    Given a table "Main Table" exists
    When player "" is seated at position 0 with reservation "res-001" for 500 chips
    Then the seating is rejected because a player identity is required

  @wip
  @EU-0572
  Scenario: SeatPlayer emits SeatingRejected when seat is out of range
    Given a table "Main Table" exists
    When player "player-a" is seated at position -5 with reservation "res-001" for 500 chips
    Then the seating is rejected because the seat is out of range

  @wip
  @EU-0573
  Scenario: AddRebuyChips rejects when the table does not exist
    Given the table has not yet been created
    When player "player-a" re-buys 100 chips with reservation "res-001" at seat 0
    Then the re-buy is refused because the table does not exist

  @wip
  @EU-0574
  Scenario: AddRebuyChips rejects when player_root is empty
    Given a table "Main Table" exists
    And player "player-a" is seated at position 2 with a 500-chip stack
    When player "" re-buys 100 chips with reservation "res-001" at seat 2
    Then the re-buy is refused because a player identity is required

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

  @wip
  @EU-0575
  Scenario: BB busts — button stays put, BB skips to the next active seat (dead button)
    # Pre-elimination: dealer at seat 0 (player-A), SB at 1 (player-B),
    # BB at 2 (player-C). player-C busts at end of hand. Next hand:
    #   - The dealer button stays on seat 0 (dead button — there is no
    #     player at seat 2 to be SB on the following hand if it advanced).
    #   - SB is the next active seat clockwise of the dead button: seat 3.
    #   - BB is the next active seat after SB.
    Given a table "Main Table" exists
    And player "player-A" is seated at position 0
    And player "player-B" is seated at position 1
    And player "player-D" is seated at position 3
    And hand 1 was played with the dealer at seat 0 and has ended
    And player "player-C" busted at seat 2 during hand 1
    When the next hand at the table begins
    Then the dealer is at seat 0
    And the small blind is at seat 3
    And the big blind is at seat 0

  @wip
  @EU-0576
  Scenario: SB busts — BB stays in place, button advances normally
    # Dealer 0, SB 1 (player-B), BB 2 (player-C). player-B busts.
    # Next hand: button → 1 is dead (no player), so dealer advances to the
    # *next active* seat... but the BB still must not double-blind. By the
    # dead-button rule, the player who was BB last hand (player-C) becomes
    # SB this hand, and BB moves to the next active seat (seat 3).
    Given a table "Main Table" exists
    And player "player-A" is seated at position 0
    And player "player-C" is seated at position 2
    And player "player-D" is seated at position 3
    And hand 1 was played with the dealer at seat 0 and has ended
    And player "player-B" busted at seat 1 during hand 1
    When the next hand at the table begins
    Then the small blind is at seat 2
    And the big blind is at seat 3

  @wip
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
    Given a table "Main Table" exists
    And player "player-A" is seated at position 0
    And player "player-C" is seated at position 2
    And hand 1 was played with the dealer at seat 0 and has ended
    And player "player-B" busted at seat 1 during hand 1
    When the next hand at the table begins
    Then the dealer is at seat 2
    And the dealer is the small blind for the heads-up hand
    And the big blind is at seat 0

  @wip
  @EU-0578
  Scenario: No player pays the big blind twice in a row across an elimination
    # The orbit invariant: a player who was BB on hand N is NEVER BB on
    # hand N+1 even if eliminations would naively produce that. This
    # scenario constructs the elimination pattern that breaks naive +1
    # advancement and asserts the BB seat changes occupant.
    Given a table "Main Table" exists
    And player "player-A" is seated at position 0
    And player "player-D" is seated at position 3
    And hand 1 was played with the dealer at seat 0 and player "player-D" on the big blind, and has ended
    And player "player-C" busted at seat 2 during hand 1
    When the next hand at the table begins
    Then player "player-D" is not on the big blind

  # ==========================================================================
  # Table Balancing — TDA Rule 11A
  # ==========================================================================
  # Real poker (TDA Rule 11A): "To balance in flop and mixed-games, the
  # player to be big blind next moves to the worst position, including
  # single big blind if available, even if that means the seat is big
  # blind twice. Worst position is never the small blind." The cluster-
  # tier EA-0012 covers the multi-table cluster integration; this
  # unit scenario pins the deterministic per-table algorithm.

  @EU-1180
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
    Given a table "Source" exists
    And player "Alice" is seated at position 0
    And player "Bob" is seated at position 1
    And player "Carol" is seated at position 2
    And player "Dave" is seated at position 3
    And the source table has the dealer button at seat 0
    And a table "Dest" exists
    And player "Eve" is seated at position 0 of "Dest"
    And player "Frank" is seated at position 1 of "Dest"
    When the coordinator balances tables from "Source" to "Dest"
    # Source-side emit (table-domain): names the player + destination table
    # by root. The destination seat is filled by a downstream saga that
    # holds both tables in view; the unit-tier scenario verifies the
    # source aggregate's BB-next choice and routing target only.
    Then the moved player is "Dave"
    And the move's destination table is "Dest"

  @EU-1181
  Scenario: Final-table combination — 9-handed event collapses 2 tables of 5 to one final table of 9
    # Rule: TDA RP-9 (2024) — "9 and 8-handed events will combine from two
    #       tables of five players each to a 9-handed final table."
    # Two 5-handed tables with one elimination remaining before the final
    # table. After the next bust, the remaining 9 players are seated at a
    # single final table by random redraw.
    # The "next bust" referred to in the rule narrative trims the field
    # from 10 to 9 before the seating; we represent the post-bust state
    # below by listing only the 9 players who reach the FT.
    Given a table "Semi-1" exists
    And player "Alice" is seated at position 0
    And player "Bob" is seated at position 1
    And player "Carol" is seated at position 2
    And player "Dave" is seated at position 3
    And a table "Semi-2" exists
    And player "Frank" is seated at position 0 of "Semi-2"
    And player "Grace" is seated at position 1 of "Semi-2"
    And player "Henry" is seated at position 2 of "Semi-2"
    And player "Ivy"   is seated at position 3 of "Semi-2"
    And player "Jack"  is seated at position 4 of "Semi-2"
    When the coordinator combines "Semi-1,Semi-2" into final table "Final"
    Then the final table has 9 active players
    And every original player has been reseated at "Final"
    And "Semi-1" is broken
    And "Semi-2" is broken

  # ==========================================================================
  # Random Seat Assignment — TDA Rule 7 / WSOP Rule 34/65
  # ==========================================================================
  # Real poker (TDA Rule 7): "Tournament and satellite seats will be randomly
  # assigned." WSOP Rule 34: "Entrants will be assigned to a table and seat
  # through a random computer selection." The current SeatPlayer flow with
  # seat=-1 picks the next *available* seat — this is fine for cash play
  # but tournament seating must be RNG-driven.

  @wip
  @EU-1182
  Scenario: Tournament seat assignment is uniformly random among available seats
    # Rule: TDA Rule 7 (2024) — random correct seating.
    # Rule: WSOP Rule 34 (2025) — random computer selection.
    Given a tournament table "Random-1" exists
    And seats 0, 2, 5, and 7 are unoccupied
    When player "Alice" is seated at any available seat for 1500 chips in tournament mode
    Then player "Alice" is seated at a seat drawn uniformly at random from {0, 2, 5, 7}
    And the random draw is reproducible for replay

  # ==========================================================================
  # Broken-Table Reseating — TDA Rule 10A
  # ==========================================================================
  # Real poker (TDA Rule 10A): "New players entering the tournament and
  # players from broken tables can get any seat including the small or big
  # blind or the button and be dealt in except between the SB and button."

  @EU-1183
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
    Given a table "Dest" exists
    And player "Alice" is seated at position 0 on the button
    And player "Bob" is seated at position 1 on the small blind
    And player "Carol" is seated at position 2 on the big blind
    And player "Dave" is seated at position 3
    And seats 4, 5, 6, 7 are open
    And a hand has been dealt at "Dest" with substantial action this orbit
    When moved player "Eve" is seated at position 4 for 1500 chips
    Then player "Eve" is seated at position 4
    And player "Eve" is dealt out of the current hand
    And player "Eve" is dealt in starting the next hand

  # ==========================================================================
  # Halt Play When Short — TDA Rule 11D
  # ==========================================================================
  # Real poker (TDA Rule 11D): "Play will halt on tables 3 or more players
  # short (by elimination) than the table with the most players once the
  # blinds are impacted."

  @wip
  @EU-1184
  Scenario: Play halts on a short table when 3+ behind once the blinds are impacted
    # Rule: TDA Rule 11D (2024).
    # 9-handed event. Source table A has 8 players. Short table B has 5.
    # The difference is 3, which triggers halt-play once the blinds at B
    # are impacted (i.e. when the BB hits an open seat at B).
    Given a table "Table-A" exists with 8 active players
    And a table "Table-B" exists with 5 active players
    When the next hand at "Table-B" would assign the big blind to an empty seat
    Then "Table-B" halts for balancing
    And "Table-B" is halted for balancing

  @wip
  @EU-1184B
  Scenario: Halted table resumes after the coordinator issues ResumePlayAtTable
    # Rule: TDA Rule 11D (2024) — resume side. Once rebalancing closes the
    # deficit the tournament coordinator clears the halt explicitly via
    # ResumePlayAtTable; the table emits TableResumedForBalancing and
    # accepts StartHand again.
    Given a table "Table-A" exists with 8 active players
    And a table "Table-B" exists with 5 active players
    And the next hand at "Table-B" would assign the big blind to an empty seat
    When the coordinator resumes play at "Table-B"
    Then "Table-B" resumes from balancing
    And "Table-B" is no longer halted for balancing

  @wip
  @EU-1184C
  Scenario: A 2-player deficit does not trigger halt (below the 3-short threshold)
    # Rule: TDA Rule 11D (2024) — first clause ("3 or more players short").
    # 9-handed event. Largest table A has 8 players. Short table B has 6.
    # Deficit is 2, below the rule's 3-player threshold. The BB-on-empty
    # trigger fires but no halt is ordered.
    Given a table "Table-A" exists with 8 active players
    And a table "Table-B" exists with 6 active players
    When the next hand at "Table-B" would assign the big blind to an empty seat
    Then "Table-B" does not halt for balancing
    And "Table-B" is not halted for balancing

  @wip
  @EU-1184D
  Scenario: Halt comparator uses the largest table, not the average
    # Rule: TDA Rule 11D (2024) — second clause ("than the table with
    # the most players"). Three tables: 9, 6, 6. Average over peers
    # would be (9+6)/2 = 7.5 → deficit < 3 → no halt. Max is 9 →
    # deficit 3 → halt fires. This sanity-checks the comparator
    # choice: rule says "the table with the most players", not "the
    # average across remaining tables".
    Given a table "Table-A" exists with 9 active players
    And a table "Table-B" exists with 6 active players
    And a table "Table-C" exists with 6 active players
    When the next hand at "Table-B" would assign the big blind to an empty seat
    Then "Table-B" halts for balancing
    And "Table-B" is halted for balancing

  @EU-1184E
  @wip
  Scenario: A halted table refuses StartHand until the coordinator resumes
    # Rule: TDA Rule 11D (2024) — the effect of "halt". A halted table
    # does not start new hands. No HandStarted is emitted; the command
    # is rejected so the saga / operator gets a clear signal.
    Given a table "Table-A" exists with 8 active players
    And a table "Table-B" exists with 5 active players
    And the next hand at "Table-B" would assign the big blind to an empty seat
    When the next hand at "Table-B" begins
    Then the start-hand at "Table-B" is refused because the table is halted for balancing
    And no hand starts at "Table-B"

  @wip
  @EU-1184F
  Scenario: Halt re-arms after a previous resume if the deficit reopens
    # Rule: TDA Rule 11D (2024) — the rule is evaluated each time the
    # BB threatens an empty seat, not once-per-table. After a resume,
    # if the deficit still meets the threshold and the BB again
    # threatens an empty seat (e.g. before rebalancing fully closed
    # the gap), the table halts again.
    Given a table "Table-A" exists with 8 active players
    And a table "Table-B" exists with 5 active players
    And the next hand at "Table-B" would assign the big blind to an empty seat
    And the coordinator resumes play at "Table-B"
    When the next hand at "Table-B" would assign the big blind to an empty seat
    Then "Table-B" halts for balancing
    And "Table-B" is halted for balancing

  # ==========================================================================
  # Dodging Blinds Penalty — TDA Rule 33 / WSOP Rule 86
  # ==========================================================================
  # Real poker (TDA Rule 33 + WSOP Rule 86): "A Participant who intentionally
  # dodges his or her blind(s) when moving from an existing seat must
  # forfeit both blinds (and BBA if applicable) and will receive a one (1)
  # round penalty."

  @EU-1185
  Scenario: A player who skips a blind by moving forfeits the missed blinds and earns a round penalty
    # Rule: TDA Rule 33 (2024) + WSOP Rule 86 (2025).
    Given a table "Main Table" exists with blinds 5/10
    And player "Alice" is seated at position 1
    And the next hand would post Alice's big blind
    When player "Alice" requests a seat change to seat 4 to skip her blind
    Then player "Alice" is penalised for dodging her blind
    And player "Alice" forfeits 15 chips
    And player "Alice" misses 1 round as a penalty

  # ==========================================================================
  # Initial Button Placement — WSOP Rule 85
  # ==========================================================================
  # WSOP-specific (Rule 85): "At the start of an Event, the button will
  # begin in the seat with the first chip stack to the dealer's right."
  # Operationally: the button on hand 1 of any new table is *deterministic*
  # given the seat-occupancy list, not a coin flip.

  @wip
  @EU-1186
  Scenario: Initial button placement on hand 1 starts at the seat to the dealer's right
    # Rule: WSOP Rule 85 (2025) — initial button placement.
    # Dealer position (the dealer person, not the button) is at seat 0.
    # First chip stack to the dealer's right (counter-clockwise) is the
    # highest seat number with a player. With seats 1, 3, 5 occupied,
    # the button starts at seat 5.
    Given a table "Main Table" exists
    And player "Alice" is seated at position 1
    And player "Bob" is seated at position 3
    And player "Carol" is seated at position 5
    When the first hand at the table begins
    Then the table is on hand number 1
    And the dealer is at seat 5

  # ==========================================================================
  # Final-Table Combination Thresholds — TDA RP-9 / WSOP Rule 68
  # ==========================================================================
  # Real poker (TDA RP-9 + WSOP Rule 68): final-table combination point
  # depends on the event's max-handed configuration:
  #   9-handed event → combine to FT with 10 remaining (5+5 → 9 was EU-1181)
  #   8-handed event → combine to FT with 9 remaining (4+5 → 8)
  #   7-handed event → combine to FT with 8 remaining (4+4 → 7)
  #   6-handed event → combine to FT with 7 remaining (4+3 → 6)

  @EU-1187
  Scenario: 8-handed event combines 2 tables of 4 and 5 to a final table of 9 then 8
    # Rule: WSOP Rule 68b (2025) — 8-handed → combine at 9 remaining.
    Given an 8-handed tournament with 9 active players across "Semi-1" and "Semi-2"
    And "Semi-1" has 4 players "Alice,Bob,Carol,Dave"
    And "Semi-2" has 5 players "Eve,Frank,Grace,Henry,Ivy"
    When the coordinator combines "Semi-1,Semi-2" into final table "Final"
    Then the final table has 9 active players
    And the final table is configured as 8-handed

  @EU-1188
  Scenario: 6-handed event combines at 7 remaining
    # Rule: WSOP Rule 68d (2025) — 6-handed → combine at 7 remaining.
    Given a 6-handed tournament with 7 active players across "Semi-1" and "Semi-2"
    And "Semi-1" has 4 players "Alice,Bob,Carol,Dave"
    And "Semi-2" has 3 players "Eve,Frank,Grace"
    When the coordinator combines "Semi-1,Semi-2" into final table "Final"
    Then the final table has 7 active players
    And the final table is configured as 6-handed
