# Allocated: EU-0400 .. EU-0499 (in use: 0400..0440, 0441..0442, 0445..0447)
Feature: Hand orchestration
  The hand orchestrator runs each hand through dealing, blinds, betting,
  community cards, and showdown. It also coordinates the buy-in, rebuy, and
  tournament registration flows that span the player, table, and tournament
  sides of the game.

  # ==========================================================================
  # Hand Initialization
  # ==========================================================================
  # When a table starts a hand, the orchestrator begins tracking it so that
  # dealing, blinds, betting, and the showdown all happen in order.

  @EU-0400
  Scenario: A new hand begins in the dealing phase
    Given a hand has just started with dealer at position 0, small blind 5, big blind 10
    And the seated players are:
      | player   | position | stack |
      | player-1 | 0        | 500   |
      | player-2 | 1        | 500   |
    When the hand is started
    Then the hand is in the dealing phase
    And the hand has 2 players
    And the dealer is at position 0

  # ==========================================================================
  # Blind Posting Phase
  # ==========================================================================
  # After cards are dealt, the small blind is posted first, then the big
  # blind. Once both are posted, betting can begin.

  @EU-0401
  Scenario: Blinds are posted once the cards are dealt
    Given a hand is in the dealing phase
    When the cards are dealt to the players
    Then the hand moves to posting blinds
    And the small blind is asked of the player due to post it

  @EU-0402
  Scenario: The big blind is posted after the small blind
    Given a hand is posting blinds
    And the small blind has been posted
    When the small blind is posted
    Then the big blind is asked of the player due to post it

  @EU-0403
  Scenario: Betting opens after the big blind is posted
    Given a hand is posting blinds
    And the small blind has been posted
    When the big blind is posted
    Then the hand moves to the betting round
    And action is on the player under the gun

  # ==========================================================================
  # Betting Round Management
  # ==========================================================================
  # The orchestrator tracks who has acted and when the round is complete.
  # A round ends once every active player has acted and matched the current
  # bet. A raise reopens the action for everyone still in the hand.

  @wip
  @EU-0404
  Scenario: Action passes to the next player after one acts
    Given a hand is in a betting round
    And action is on the player at position 2
    When the player at position 2 calls
    Then action passes to the next active player

  @EU-0405
  Scenario: A raise reopens the action for everyone else
    Given a hand is in a betting round
    And the players at positions 0, 1, and 2 have all acted
    When the player at position 0 raises
    Then the players at positions 1 and 2 must act again

  @EU-0406
  Scenario: The betting round ends when everyone has acted and matched the bet
    Given a hand is in a betting round
    And every active player has acted and matched the current bet
    When the last player acts
    Then the betting round ends
    And the hand advances to the next phase

  @EU-0407
  Scenario: The flop is dealt after the preflop betting round
    Given preflop betting is complete
    When the betting round ends
    Then the flop is dealt
    And the hand is dealing community cards

  @EU-0408
  Scenario: The turn is dealt after the flop betting round
    Given flop betting is complete
    When the betting round ends
    Then the turn card is dealt

  @EU-0409
  Scenario: The river is dealt after the turn betting round
    Given turn betting is complete
    When the betting round ends
    Then the river card is dealt

  @EU-0410
  Scenario: Showdown begins after the river betting round
    Given river betting is complete
    When the betting round ends
    Then the hand moves to showdown
    And the pot is awarded

  # ==========================================================================
  # Position-Specific Action Order
  # ==========================================================================
  # Three positional rules every poker engine must get right:
  #   - Preflop: the big blind acts last and keeps the option to check or
  #     raise even when everyone else has only matched the blind.
  #   - Post-flop, ring (3+ players): action starts at the first un-folded
  #     seat left of the dealer.
  #   - Post-flop, heads-up: action reverses — the big blind acts first and
  #     the dealer/small blind acts last.

  @EU-0445
  Scenario: The big blind keeps the option preflop after the others just call
    # Three-handed: dealer at 0, small blind at 1, big blind at 2. After the
    # dealer calls and the small blind completes, both have matched the big
    # blind but the round is NOT over — the big blind still has the option to
    # check or raise.
    Given a hand is in a betting round
    And the dealer is at position 0 with players at positions 0, 1, and 2
    And the small blind of 5 was posted by position 1 and the big blind of 10 was posted by position 2
    And action is on the player at position 0
    When the player at position 0 calls 10
    And the player at position 1 calls 5
    Then the betting round is not yet complete
    And action is on the big blind at position 2

  @EU-0446
  @wip
  Scenario: Post-flop action starts on the first active seat left of the dealer (3-handed)
    # After the flop is dealt with three players still in (dealer at seat 0,
    # small blind at 1, big blind at 2), the next round opens with action on
    # seat 1 — the first active seat clockwise from the dealer.
    Given preflop betting is complete
    And the dealer is at position 0 with players at positions 0, 1, and 2
    When the flop is dealt
    Then the hand moves to the betting round
    And action is on the player at position 1

  @EU-0447
  @wip
  Scenario: Post-flop action starts on the big blind in heads-up
    # Heads-up reverses the post-flop order: the dealer/small blind at seat 0
    # acts last and the big blind at seat 1 acts first.
    Given preflop betting is complete
    And the dealer is at position 0 with players at positions 0 and 1
    When the flop is dealt
    Then the hand moves to the betting round
    And action is on the player at position 1

  # ==========================================================================
  # All-in and Early Endings
  # ==========================================================================
  # A hand can end early if everyone but one player folds. All-in players
  # cannot take further actions but remain eligible for pot awards.

  @EU-0411
  Scenario: The pot is awarded to the last player still in the hand
    Given a hand with 2 players is in progress
    When one of the players folds
    Then the hand is complete
    And the pot is awarded to the remaining player

  @EU-0412
  Scenario: A player who moves all-in is taken out of the action
    Given a hand is in a betting round
    When a player moves all-in
    Then that player is marked as all-in
    And that player no longer acts in this betting round

  # ==========================================================================
  # Timeout Handling
  # ==========================================================================
  # Players who don't act within the time limit are auto-acted: fold if
  # facing a bet, check if there is no bet to face. This keeps hands from
  # stalling indefinitely.

  @EU-0413
  Scenario: A player who times out facing a bet is folded
    Given a hand is in a betting round
    And the player to act faces a bet of 20 with nothing committed this round
    When the player times out
    Then the player is folded

  @EU-0414
  Scenario: A player who times out with no bet to face is checked
    Given a hand is in a betting round
    And there is no bet to call
    When the player times out
    Then the player is checked

  # ==========================================================================
  # Draw Game Phases
  # ==========================================================================
  # Draw games have an additional phase between betting rounds where players
  # discard and draw new cards.

  @EU-0415
  Scenario: Five Card Draw moves to the draw after the first betting round
    Given a Five Card Draw hand has finished the first betting round
    When the betting round ends
    Then the hand moves to the draw

  @EU-0416
  Scenario: Five Card Draw resumes betting after every player has drawn
    Given a Five Card Draw hand is in the draw
    And every player has finished drawing
    When the last player finishes drawing
    Then the hand moves to the final betting round

  # ==========================================================================
  # Community Card Dealing
  # ==========================================================================
  # When new community cards are dealt, the betting state resets: nothing is
  # committed yet for the new round and action moves to the first player
  # left of the dealer who is still in the hand.

  @EU-0417
  Scenario: A new community card resets the betting state for the next round
    Given a hand is in a betting round
    When the flop is dealt
    Then no player has anything committed this round
    And no player has yet acted this round
    And there is no bet to call
    And action is on the first active player left of the dealer

  # ==========================================================================
  # Pot and Stack Tracking
  # ==========================================================================
  # The orchestrator keeps the running pot total and the players' stacks
  # accurate throughout the hand.

  @EU-0418
  Scenario: The pot total reflects every blind and bet so far
    Given a hand is in progress
    And the players have together contributed 150 in blinds and bets
    Then the pot total is 150

  @EU-0419
  Scenario: A bet is deducted from the player's stack
    Given a hand is in progress with "player-1" sitting on 500
    When "player-1" puts 50 into the pot
    Then "player-1"'s stack is 450

  @EU-0420
  Scenario: The hand ends once the pot has been awarded
    Given a hand is at showdown
    When the pot is awarded
    Then the hand is complete
    And any pending timeout is cancelled

  # ==========================================================================
  # Buy-In Flow
  # ==========================================================================
  # A buy-in is coordinated across the player and table sides:
  # 1. The player requests a buy-in for a seat.
  # 2. The orchestrator asks the table to seat the player.
  # 3. If the table accepts, the player's funds are confirmed for that seat.
  # 4. If the table rejects, the player's reservation is released.

  @EU-0421
  Scenario: A buy-in request asks the table to seat the player
    Given a buy-in is in progress for player "player_123"
    When player "player_123" requests a buy-in at table "table_456" for seat 2 with 500 chips under reservation "res_789"
    Then the table is asked to seat "player_123" at seat 2 with 500 chips under reservation "res_789"

  @EU-0422
  Scenario: A buy-in request is recorded as in progress
    Given a buy-in is in progress for player "player_123"
    When player "player_123" requests a buy-in at table "table_456" for seat 2 with 500 chips under reservation "res_789"
    Then the buy-in for "player_123" at "table_456" is recorded as awaiting seating

  @EU-0423
  Scenario: Once the player is seated the buy-in funds are confirmed
    Given a buy-in is in progress
    When the table seats "player_123" at seat 2 with 500 chips under reservation "res_789"
    Then "player_123"'s buy-in reservation "res_789" is confirmed

  @EU-0424
  Scenario: Once the player is seated the buy-in is recorded as completed
    Given a buy-in is in progress
    When the table seats "player_123" at seat 2 with 500 chips under reservation "res_789"
    Then the buy-in for "player_123" at seat 2 is recorded as completed

  @EU-0425
  Scenario: If seating is refused the buy-in funds are released
    Given a buy-in is in progress
    When the table refuses to seat "player_123" under reservation "res_789" because "Seat already taken"
    Then "player_123"'s buy-in reservation "res_789" is released because "Seat already taken"

  @EU-0426
  Scenario: If seating is refused the buy-in is recorded as failed
    Given a buy-in is in progress
    When the table refuses to seat "player_123" under reservation "res_789" because "Seat already taken"
    Then the buy-in for "player_123" is recorded as failed because the table refused to seat the player

  # ==========================================================================
  # Rebuy Flow
  # ==========================================================================
  # A rebuy is coordinated across the player, tournament, and table sides:
  # 1. The player requests a rebuy.
  # 2. The orchestrator asks the tournament to approve it.
  # 3. If approved, the table adds the rebuy chips and the fee is confirmed.
  # 4. If denied, the rebuy fee is released.

  @EU-0427
  Scenario: A rebuy request asks the tournament to approve the rebuy
    Given a rebuy is in progress for player "player_123"
    When player "player_123" requests a rebuy at tournament "tournament_456", table "table_789", seat 2 with fee 50 under reservation "res_001"
    Then the tournament is asked to approve the rebuy for "player_123" under reservation "res_001"

  @EU-0428
  Scenario: A rebuy request is recorded as awaiting approval
    Given a rebuy is in progress for player "player_123"
    When player "player_123" requests a rebuy at tournament "tournament_456", table "table_789", seat 2 with fee 50 under reservation "res_001"
    Then the rebuy for "player_123" in tournament "tournament_456" is recorded as awaiting approval

  @EU-0429
  Scenario: An approved rebuy asks the table to add the rebuy chips
    Given a rebuy is in progress for table "table_789" at seat 2
    When the tournament approves the rebuy for "player_123" under reservation "res_001" with 1500 chips
    Then the table is asked to add 1500 chips for "player_123" at seat 2 under reservation "res_001"

  @EU-0430
  Scenario: A denied rebuy releases the rebuy fee
    Given a rebuy is in progress for tournament "tournament_456"
    When the tournament denies the rebuy for "player_123" under reservation "res_001" because "Rebuy limit reached"
    Then "player_123"'s rebuy reservation "res_001" is released because "Rebuy limit reached"

  @EU-0431
  Scenario: A denied rebuy is recorded as failed
    Given a rebuy is in progress for tournament "tournament_456"
    When the tournament denies the rebuy for "player_123" under reservation "res_001" because "Rebuy limit reached"
    Then the rebuy for "player_123" is recorded as failed because the tournament denied the rebuy

  @EU-0432
  Scenario: Once the chips are added the rebuy fee is confirmed
    Given a rebuy is in progress for tournament "tournament_456" at table "table_789" with fee 50
    When the table adds 1500 rebuy chips for "player_123" at seat 2 under reservation "res_001"
    Then "player_123"'s rebuy fee reservation "res_001" is confirmed

  @EU-0433
  Scenario: Once the chips are added the rebuy is recorded as completed
    Given a rebuy is in progress for tournament "tournament_456" at table "table_789" with fee 50
    When the table adds 1500 rebuy chips for "player_123" at seat 2 under reservation "res_001"
    Then the rebuy for "player_123" is recorded as completed with 1500 chips added

  # ==========================================================================
  # Tournament Registration Flow
  # ==========================================================================
  # Tournament registration is coordinated across the player and tournament
  # sides:
  # 1. The player requests to register for a tournament.
  # 2. The orchestrator asks the tournament to enroll the player.
  # 3. If enrolled, the registration fee is confirmed.
  # 4. If rejected, the fee is released.
  #
  # The first three scenarios verify a tournament's registration state can
  # be reconstructed from its history (open/closed, capacity, who has
  # already registered).

  @EU-0434
  Scenario: A newly created tournament is open for registration
    Given a tournament has been created with name "Test Tournament", up to 100 players, buy-in 50, and starting stack 1500
    When the tournament's registration state is reconstructed from its history
    Then the tournament is open for registration
    And the tournament allows up to 100 players
    And the tournament buy-in is 50
    And the tournament starting stack is 1500
    And no players have registered yet

  @EU-0435
  Scenario: Reconstructing the tournament state shows who has registered
    Given a tournament history with:
      | event                    | name | max_players | player     |
      | tournament created       | Test | 50          |            |
      | player enrolled          |      |             | player_123 |
    When the tournament's registration state is reconstructed from its history
    Then "player_123" is registered for the tournament
    And 1 player is registered for the tournament

  @EU-0436
  Scenario: Reconstructing the tournament state shows registration closed once it starts
    Given a tournament history with:
      | event              | name |
      | tournament created | Test |
      | tournament started |      |
    When the tournament's registration state is reconstructed from its history
    Then the tournament is closed for registration
    And the tournament is running

  @EU-0437
  Scenario: The tournament state reflects each enrollment as it is applied
    Given a fresh tournament
    When a tournament is created with name "T" and up to 4 players
    And "p1" is enrolled in the tournament
    Then 1 player is registered for the tournament
    And the tournament allows up to 4 players

  @EU-0438
  Scenario: A registration request asks the tournament to enroll the player
    Given a registration is in progress for player "player_123"
    When player "player_123" requests registration in tournament "tournament_456" with fee 50 under reservation "res_001"
    Then the tournament is asked to enroll "player_123" under reservation "res_001"

  @EU-0439
  Scenario: Once the player is enrolled the registration fee is confirmed
    Given a registration is in progress for tournament "tournament_456" with fee 50
    When the tournament enrolls "player_123" under reservation "res_001" with fee paid 50 and starting stack 1500
    Then "player_123"'s registration fee reservation "res_001" is confirmed

  @EU-0440
  Scenario: A rejected registration releases the registration fee
    Given a registration is in progress for tournament "tournament_456"
    When the tournament rejects the registration for "player_123" under reservation "res_001" because "Tournament full"
    Then "player_123"'s registration fee reservation "res_001" is released because "Tournament full"

  # ==========================================================================
  # Registration — Missing Fee Default
  # ==========================================================================
  # When a registration request carries no fee, the recorded amount defaults
  # to zero so the rest of the flow has a well-formed amount to work with.

  @EU-0441
  Scenario: A registration without a fee is recorded with a zero fee
    Given a registration is in progress for player "player_123"
    When player "player_123" requests registration in tournament "tournament_456" under reservation "res_001" with no fee
    Then the registration for "player_123" is recorded with a fee of 0

  # End-of-hand cleanup was moved out of the orchestrator and lives in the
  # table-sync flow. See saga.feature for coverage.
