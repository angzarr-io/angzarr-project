# Allocated: EU-0400 .. EU-0499 (in use: 0400..0440, 0441..0442, 0445..0447)
Feature: Process manager logic
  The HandFlowPM orchestrates a poker hand's state machine: dealing, blind
  posting, betting rounds, community cards, and showdown. Unlike sagas,
  process managers are STATEFUL - they maintain their own event stream to
  track workflow progress.

  # Why a process manager (not just sagas):
  # - Hand flow requires sequencing: blinds before betting, flop before turn
  # - State machine transitions need memory (current phase, who has acted)
  # - Timeouts require knowing the current action player
  # - Multiple events across domains must be correlated

  # Patterns enabled by process managers:
  # - Cross-domain correlation: Events from table AND hand domains drive one
    # workflow. Same pattern applies to order+payment+shipping coordination.
  # - Long-running workflows: A hand may last minutes with many events. PM state
    # survives restarts. Same pattern applies to approval chains, onboarding flows.
  # - Timeout orchestration: PM schedules timeouts, handles expiration. Same
    # pattern applies to payment timeouts, SLA enforcement, auction endings.
  # - Compensation coordination: When downstream fails, PM updates workflow state
    # before source aggregate compensates. Same pattern for distributed sagas.

  # Why poker exercises PM patterns well:
  # - Multi-domain events: HandStarted (table) + CardsDealt (hand) + actions (hand)
  # - Complex state machine: DEALING→BLINDS→BETTING→FLOP→BETTING→TURN→... with
    # clear phase transitions and invalid paths
  # - Timeouts are critical: players have N seconds to act or auto-fold/check
  # - Action tracking: who has acted, who needs to act, who has folded

  # The HandFlowPM:
  # - Receives events from table and hand domains
  # - Maintains workflow state (phase, betting state, player status)
  # - Emits commands to advance the hand (PostBlind, DealCommunityCards, AwardPot)
  # - Handles timeouts with sensible defaults (auto-fold/check)

  # ==========================================================================
  # Hand Initialization
  # ==========================================================================
  # When a table starts a hand, the PM creates a HandProcess to track the
  # workflow. This process state persists across all phases of the hand.

  @EU-0400
  Scenario: Process manager initializes hand from HandStarted
    Given a HandFlowPM
    And a HandStarted event with:
      | hand_number | game_variant   | dealer_position | small_blind | big_blind |
      | 1           | TEXAS_HOLDEM   | 0               | 5           | 10        |
    And active players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    When the process manager starts the hand
    Then a HandProcess is created with phase DEALING
    And the process has 2 players
    And the process has dealer_position 0

  # ==========================================================================
  # Blind Posting Phase
  # ==========================================================================
  # After cards are dealt, the PM drives blind posting: small blind first,
  # then big blind. Once both are posted, betting can begin.

  @EU-0401
  Scenario: Process manager transitions to blind posting after cards dealt
    Given an active hand process in phase DEALING
    And a CardsDealt event
    When the process manager handles the event
    Then the process transitions to phase POSTING_BLINDS
    And a PostBlind command is sent for small blind

  @EU-0402
  Scenario: Process manager posts big blind after small blind
    Given an active hand process in phase POSTING_BLINDS
    And small_blind_posted is true
    And a BlindPosted event for small blind
    When the process manager handles the event
    Then a PostBlind command is sent for big blind

  @EU-0403
  Scenario: Process manager starts betting after big blind posted
    Given an active hand process in phase POSTING_BLINDS
    And small_blind_posted is true
    And a BlindPosted event for big blind
    When the process manager handles the event
    Then the process transitions to phase BETTING
    And action_on is set to UTG position

  # ==========================================================================
  # Betting Round Management
  # ==========================================================================
  # The PM tracks who has acted, current bet, and when the round is complete.
  # A round ends when all active players have acted and matched the current bet.
  # Raises reset the "has acted" state for other players.

  @EU-0404
  Scenario: Process manager advances action after player acts
    Given an active hand process in phase BETTING
    And action_on is position 2
    And an ActionTaken event for player at position 2 with action CALL
    When the process manager handles the event
    Then action_on advances to next active player

  @EU-0405
  Scenario: Process manager resets has_acted after raise
    Given an active hand process in phase BETTING
    And players at positions 0, 1, 2 have all acted
    And an ActionTaken event for player at position 0 with action RAISE
    When the process manager handles the event
    Then players at positions 1 and 2 have has_acted reset to false

  @EU-0406
  Scenario: Process manager detects betting complete
    Given an active hand process in phase BETTING
    And all active players have acted and matched the current bet
    And an ActionTaken event for the last player
    When the process manager handles the event
    Then the betting round ends
    And the process advances to next phase

  @EU-0407
  Scenario: Process manager deals flop after preflop betting
    Given an active hand process with betting_phase PREFLOP
    And betting round is complete
    When the process manager ends the betting round
    Then a DealCommunityCards command is sent with count 3
    And the process transitions to phase DEALING_COMMUNITY

  @EU-0408
  Scenario: Process manager deals turn after flop betting
    Given an active hand process with betting_phase FLOP
    And betting round is complete
    When the process manager ends the betting round
    Then a DealCommunityCards command is sent with count 1

  @EU-0409
  Scenario: Process manager deals river after turn betting
    Given an active hand process with betting_phase TURN
    And betting round is complete
    When the process manager ends the betting round
    Then a DealCommunityCards command is sent with count 1

  @EU-0410
  Scenario: Process manager starts showdown after river betting
    Given an active hand process with betting_phase RIVER
    And betting round is complete
    When the process manager ends the betting round
    Then the process transitions to phase SHOWDOWN
    And an AwardPot command is sent

  # ==========================================================================
  # Position-Specific Action Order
  # ==========================================================================
  # Three positional rules every poker engine must get right:
  #   - Preflop: BB acts last and retains the "option" to check or raise even
  #     when current_bet == BB amount (everyone else just called the blind).
  #   - Post-flop, ring (3+): action starts at the first un-folded seat left
  #     of the dealer (typically the SB position).
  #   - Post-flop, heads-up: action reverses — BB acts first, dealer/SB last.
  # All three are easy to get wrong with off-by-one logic in the seat walker.

  @EU-0445
  Scenario: BB retains option preflop after non-BB players match the blind
    # Three-handed: dealer at 0, SB at 1, BB at 2. Blinds posted, current_bet
    # = BB. Dealer (UTG with 3 players) calls; SB completes. Both have
    # bet_this_round == current_bet, but the round must NOT be complete: BB's
    # has_acted is still false (the PM resets it on _start_betting), so BB
    # gets the option to check or raise even though their blind already
    # matches. A buggy implementation that closes the round on
    # "everyone-matched" would skip BB entirely.
    Given an active hand process in phase BETTING
    And dealer is at position 0 and 3 players seated at positions 0, 1, 2
    And blinds posted: SB position 1 amount 5, BB position 2 amount 10
    And action_on is position 0
    When the player at position 0 calls 10
    And the player at position 1 calls 5
    Then the betting round is not complete
    And action_on is position 2

  @EU-0446
  Scenario: Post-flop action starts at first active seat left of dealer (3-handed)
    # After the flop is dealt with 3 players still in (dealer at seat 0, SB at
    # 1, BB at 2), the next betting round opens with action on seat 1 (SB) —
    # the first active seat clockwise from the dealer. Confirms the seat
    # walker uses the dealer position, not the previous-round action_on.
    Given an active hand process with betting_phase PREFLOP
    And dealer is at position 0 and 3 players seated at positions 0, 1, 2
    And the preflop betting round is complete
    When a CommunityCardsDealt event for FLOP is handled
    Then the process transitions to phase BETTING
    And action_on is position 1

  @EU-0447
  Scenario: Post-flop action starts on the BB in heads-up
    # Heads-up reverses the post-flop order: dealer/SB at seat 0 acts last,
    # BB at seat 1 acts first. _find_next_active(dealer_position) wraps to
    # the next seat — which IS the BB. Without an explicit assertion, a
    # heads-up off-by-one (e.g. starting on the dealer post-flop) would slip
    # through unit tests because the action still completes.
    Given an active hand process with betting_phase PREFLOP
    And dealer is at position 0 and 2 players seated at positions 0, 1
    And the preflop betting round is complete
    When a CommunityCardsDealt event for FLOP is handled
    Then the process transitions to phase BETTING
    And action_on is position 1

  # ==========================================================================
  # All-in and Early Endings
  # ==========================================================================
  # Hands can end early if all but one player folds. All-in players are
  # tracked separately since they can't take further actions but remain
  # eligible for pot awards.

  @EU-0411
  Scenario: Process manager awards pot to last player standing
    Given an active hand process with 2 players
    And an ActionTaken event with action FOLD
    When the process manager handles the event
    Then the process transitions to phase COMPLETE
    And an AwardPot command is sent to the remaining player

  @EU-0412
  Scenario: Process manager handles all-in correctly
    Given an active hand process in phase BETTING
    And an ActionTaken event with action ALL_IN
    When the process manager handles the event
    Then the player is marked as is_all_in
    And the player is not included in active players for betting

  # ==========================================================================
  # Timeout Handling
  # ==========================================================================
  # Players who don't act within the time limit are auto-acted: fold if
  # facing a bet, check if no bet. This prevents hands from stalling
  # indefinitely.

  @EU-0413
  Scenario: Process manager auto-folds on timeout when facing bet
    Given an active hand process in phase BETTING
    And current_bet is 20
    And action_on player has bet_this_round 0
    When the action times out
    Then the process manager sends PlayerAction with FOLD

  @EU-0414
  Scenario: Process manager auto-checks on timeout when no bet
    Given an active hand process in phase BETTING
    And current_bet is 0
    When the action times out
    Then the process manager sends PlayerAction with CHECK

  # ==========================================================================
  # Draw Game Phases
  # ==========================================================================
  # Draw games have an additional phase between betting rounds where players
  # discard and draw new cards. The PM tracks draw completion.

  @EU-0415
  Scenario: Process manager handles Five Card Draw phase transition
    Given an active hand process with game_variant FIVE_CARD_DRAW
    And betting_phase PREFLOP
    And betting round is complete
    When the process manager ends the betting round
    Then the process transitions to phase DRAW

  @EU-0416
  Scenario: Process manager starts final betting after draw
    Given an active hand process with game_variant FIVE_CARD_DRAW
    And betting_phase DRAW
    And all players have completed their draws
    When the process manager handles the last draw
    Then the process transitions to phase BETTING
    And betting_phase is set to DRAW

  # ==========================================================================
  # Community Card Dealing
  # ==========================================================================
  # When community cards are dealt, the PM resets betting state for the new
  # round: bet amounts reset to zero, action moves to first player after dealer.

  @EU-0417
  Scenario: Process manager resets betting state for new round
    Given an active hand process in phase BETTING
    And a CommunityCardsDealt event for FLOP
    When the process manager handles the event
    Then all players have bet_this_round reset to 0
    And all players have has_acted reset to false
    And current_bet is reset to 0
    And action_on is set to first player after dealer

  # ==========================================================================
  # State Management
  # ==========================================================================
  # The PM maintains accurate pot totals and player stacks throughout the
  # hand. These scenarios verify state updates are correct.

  @EU-0418
  Scenario: Process manager tracks pot total correctly
    Given an active hand process
    And a series of BlindPosted and ActionTaken events totaling 150
    When all events are processed
    Then pot_total is 150

  @EU-0419
  Scenario: Process manager tracks player stacks correctly
    Given an active hand process with player "player-1" at stack 500
    And an ActionTaken event for "player-1" with amount 50
    When the process manager handles the event
    Then "player-1" stack is 450

  @EU-0420
  Scenario: Process manager completes hand on PotAwarded
    Given an active hand process in phase SHOWDOWN
    And a PotAwarded event
    When the process manager handles the event
    Then the process transitions to phase COMPLETE
    And any pending timeout is cancelled

  # ==========================================================================
  # Buy-In Process Manager
  # ==========================================================================
  # The BuyInPM coordinates buy-in flows across Player <-> Table aggregates:
  # 1. Player emits BuyInRequested
  # 2. PM (optionally) queries Table state via QueryClient for pre-validation
  # 3. On pass, PM emits SeatPlayer command + BuyInInitiated process event
  # 4. Table replies with PlayerSeated (success) or SeatingRejected (failure)
  # 5. Success path: PM emits ConfirmBuyIn + BuyInCompleted process event
  #    Failure path: PM emits ReleaseBuyIn + BuyInFailed process event
  #
  # These scenarios exercise the happy/error paths without a query client
  # wired (validation is skipped when table_state is empty).

  @EU-0421
  Scenario: BuyInPM emits SeatPlayer command for BuyInRequested
    Given a BuyInPM with player_root "player_123"
    And a BuyInRequested event with table_root "table_456", reservation_id "res_789", seat 2, amount 500
    And destinations with sequences table=5
    When the BuyInPM handles buy_in_requested
    Then a SeatPlayer command is sent to the "table" domain
    And the SeatPlayer command has player_root "player_123"
    And the SeatPlayer command has seat 2
    And the SeatPlayer command has amount 500
    And the SeatPlayer command has reservation_id "res_789"

  @EU-0422
  Scenario: BuyInPM records BuyInInitiated process event
    Given a BuyInPM with player_root "player_123"
    And a BuyInRequested event with table_root "table_456", reservation_id "res_789", seat 2, amount 500
    And destinations with sequences table=5
    When the BuyInPM handles buy_in_requested
    Then the process event is a angzarr_client.proto.examples.v1.BuyInInitiated event
    And the BuyInInitiated event has player_root "player_123"
    And the BuyInInitiated event has table_root "table_456"
    And the BuyInInitiated event phase is BUY_IN_SEATING

  @EU-0423
  Scenario: BuyInPM emits ConfirmBuyIn on PlayerSeated
    Given a BuyInPM
    And a PlayerSeated event with player_root "player_123", reservation_id "res_789", seat_position 2, stack 500
    And destinations with sequences player=3
    When the BuyInPM handles player_seated
    Then a ConfirmBuyIn command is sent to the "reservation" domain
    And the ConfirmBuyIn command has reservation_id "res_789"

  @EU-0424
  Scenario: BuyInPM records BuyInCompleted on PlayerSeated
    Given a BuyInPM
    And a PlayerSeated event with player_root "player_123", reservation_id "res_789", seat_position 2, stack 500
    And destinations with sequences player=3
    When the BuyInPM handles player_seated
    Then the process event is a angzarr_client.proto.examples.v1.BuyInCompleted event
    And the BuyInCompleted event has player_root "player_123"
    And the BuyInCompleted event has seat 2

  @EU-0425
  Scenario: BuyInPM emits ReleaseBuyIn on SeatingRejected
    Given a BuyInPM
    And a SeatingRejected event with player_root "player_123", reservation_id "res_789", reason "Seat already taken"
    And destinations with sequences player=3
    When the BuyInPM handles seating_rejected
    Then a ReleaseBuyIn command is sent to the "reservation" domain
    And the ReleaseBuyIn command has reservation_id "res_789"
    And the ReleaseBuyIn command has reason "Seat already taken"

  @EU-0426
  Scenario: BuyInPM records BuyInFailed on SeatingRejected
    Given a BuyInPM
    And a SeatingRejected event with player_root "player_123", reservation_id "res_789", reason "Seat already taken"
    And destinations with sequences player=3
    When the BuyInPM handles seating_rejected
    Then the process event is a angzarr_client.proto.examples.v1.BuyInFailed event
    And the BuyInFailed event has player_root "player_123"
    And the BuyInFailed event failure code is "SEATING_REJECTED"

  # ==========================================================================
  # Rebuy Process Manager
  # ==========================================================================
  # The RebuyPM coordinates rebuy flows across Player <-> Tournament <-> Table:
  # 1. Player emits RebuyRequested
  # 2. PM (optionally) queries Tournament + Table state for pre-validation
  # 3. On pass, PM emits ProcessRebuy command to Tournament +
  #    RebuyInitiated process event
  # 4. Tournament replies RebuyProcessed (approve) or RebuyDenied (reject)
  # 5. On approve, PM emits AddRebuyChips to Table which echoes
  #    RebuyChipsAdded — PM then emits ConfirmRebuyFee + RebuyCompleted
  #    On deny, PM emits ReleaseRebuyFee + RebuyFailed

  @EU-0427
  Scenario: RebuyPM emits ProcessRebuy for RebuyRequested
    Given a RebuyPM with player_root "player_123"
    And a RebuyRequested event with tournament_root "tournament_456", table_root "table_789", reservation_id "res_001", seat 2, fee 50
    And destinations with sequences tournament=5, table=3
    When the RebuyPM handles rebuy_requested
    Then a ProcessRebuy command is sent to the "tournament" domain
    And the ProcessRebuy command has player_root "player_123"
    And the ProcessRebuy command has reservation_id "res_001"

  @EU-0428
  Scenario: RebuyPM records RebuyInitiated process event
    Given a RebuyPM with player_root "player_123"
    And a RebuyRequested event with tournament_root "tournament_456", table_root "table_789", reservation_id "res_001", seat 2, fee 50
    And destinations with sequences tournament=5
    When the RebuyPM handles rebuy_requested
    Then the process event is a angzarr_client.proto.examples.v1.RebuyInitiated event
    And the RebuyInitiated event has player_root "player_123"
    And the RebuyInitiated event has tournament_root "tournament_456"
    And the RebuyInitiated event phase is REBUY_APPROVING

  @EU-0429
  Scenario: RebuyPM emits AddRebuyChips on RebuyProcessed
    Given a RebuyPM with table_root "table_789" and seat 2
    And a RebuyProcessed event with player_root "player_123", reservation_id "res_001", chips_added 1500, rebuy_count 1
    And destinations with sequences table=3
    When the RebuyPM handles rebuy_processed
    Then an AddRebuyChips command is sent to the "table" domain
    And the AddRebuyChips command has player_root "player_123"
    And the AddRebuyChips command has reservation_id "res_001"
    And the AddRebuyChips command has seat 2
    And the AddRebuyChips command has amount 1500

  @EU-0430
  Scenario: RebuyPM emits ReleaseRebuyFee on RebuyDenied
    Given a RebuyPM with tournament_root "tournament_456"
    And a RebuyDenied event with player_root "player_123", reservation_id "res_001", reason "Rebuy limit reached"
    And destinations with sequences player=5
    When the RebuyPM handles rebuy_denied
    Then a ReleaseRebuyFee command is sent to the "reservation" domain
    And the ReleaseRebuyFee command has reservation_id "res_001"
    And the ReleaseRebuyFee command has reason "Rebuy limit reached"

  @EU-0431
  Scenario: RebuyPM records RebuyFailed on RebuyDenied
    Given a RebuyPM with tournament_root "tournament_456"
    And a RebuyDenied event with player_root "player_123", reservation_id "res_001", reason "Rebuy limit reached"
    And destinations with sequences player=5
    When the RebuyPM handles rebuy_denied
    Then the process event is a angzarr_client.proto.examples.v1.RebuyFailed event
    And the RebuyFailed event has player_root "player_123"
    And the RebuyFailed event failure code is "REBUY_DENIED"

  @EU-0432
  Scenario: RebuyPM emits ConfirmRebuyFee on RebuyChipsAdded
    Given a RebuyPM with tournament_root "tournament_456", table_root "table_789", fee 50
    And a RebuyChipsAdded event with player_root "player_123", reservation_id "res_001", seat 2, amount 1500, new_stack 2000
    And destinations with sequences player=5
    When the RebuyPM handles rebuy_chips_added
    Then a ConfirmRebuyFee command is sent to the "reservation" domain
    And the ConfirmRebuyFee command has reservation_id "res_001"

  @EU-0433
  Scenario: RebuyPM records RebuyCompleted on RebuyChipsAdded
    Given a RebuyPM with tournament_root "tournament_456", table_root "table_789", fee 50
    And a RebuyChipsAdded event with player_root "player_123", reservation_id "res_001", seat 2, amount 1500, new_stack 2000
    And destinations with sequences player=5
    When the RebuyPM handles rebuy_chips_added
    Then the process event is a angzarr_client.proto.examples.v1.RebuyCompleted event
    And the RebuyCompleted event has player_root "player_123"
    And the RebuyCompleted event has chips_added 1500

  # ==========================================================================
  # Registration Process Manager
  # ==========================================================================
  # The RegistrationPM coordinates registration flows across
  # Player <-> Tournament aggregates:
  # 1. Player emits RegistrationRequested
  # 2. PM (optionally) queries Tournament state for pre-validation
  #    (registration_open, capacity, already-registered)
  # 3. On pass, PM emits EnrollPlayer command + RegistrationInitiated
  #    process event
  # 4. Tournament replies TournamentPlayerEnrolled (success) or
  #    TournamentEnrollmentRejected (failure)
  # 5. Success: PM emits ConfirmRegistrationFee + RegistrationCompleted
  #    Failure: PM emits ReleaseRegistrationFee + RegistrationFailed
  #
  # The tournament-state rebuild scenarios verify the TournamentStateHelper
  # used during pre-validation correctly folds tournament domain events.

  @EU-0434
  Scenario: Tournament state rebuild from TournamentCreated event
    Given a tournament event book with a TournamentCreated event name "Test Tournament", max_players 100, buy_in 50, starting_stack 1500
    When I rebuild the tournament state from the event book
    Then the tournament state has registration_open true
    And the tournament state has max_players 100
    And the tournament state has buy_in 50
    And the tournament state has starting_stack 1500
    And the tournament state has registered_count 0

  @EU-0435
  Scenario: Tournament state rebuild tracks player enrollments
    Given a tournament event book with:
      | event_type                | name      | max_players | player_root |
      | TournamentCreated         | Test      | 50          |             |
      | TournamentPlayerEnrolled  |           |             | player_123  |
    When I rebuild the tournament state from the event book
    Then the tournament state has registered player "player_123"
    And the tournament state has registered_count 1

  @EU-0436
  Scenario: Tournament state rebuild closes registration after start
    Given a tournament event book with:
      | event_type         | name |
      | TournamentCreated  | Test |
      | TournamentStarted  |      |
    When I rebuild the tournament state from the event book
    Then the tournament state has registration_open false
    And the tournament state status is TOURNAMENT_RUNNING

  @EU-0437
  Scenario: Direct tournament_state_rebuild folds events into a state helper
    Given an empty tournament state helper
    When I apply a TournamentCreated event with name "T" and max_players 4
    And I apply a TournamentPlayerEnrolled event for player_root "p1"
    Then the tournament state has registered_count 1
    And the tournament state has max_players 4

  @EU-0438
  Scenario: RegistrationPM emits EnrollPlayer for RegistrationRequested
    Given a RegistrationPM with player_root "player_123"
    And a RegistrationRequested event with tournament_root "tournament_456", reservation_id "res_001", fee 50
    And destinations with sequences tournament=5
    When the RegistrationPM handles registration_requested
    Then an EnrollPlayer command is sent to the "tournament" domain
    And the EnrollPlayer command has player_root "player_123"
    And the EnrollPlayer command has reservation_id "res_001"

  @EU-0439
  Scenario: RegistrationPM emits ConfirmRegistrationFee on TournamentPlayerEnrolled
    Given a RegistrationPM with tournament_root "tournament_456" and fee 50
    And a TournamentPlayerEnrolled event with player_root "player_123", reservation_id "res_001", fee_paid 50, starting_stack 1500
    And destinations with sequences player=3
    When the RegistrationPM handles player_enrolled
    Then a ConfirmRegistrationFee command is sent to the "reservation" domain
    And the ConfirmRegistrationFee command has reservation_id "res_001"

  @EU-0440
  Scenario: RegistrationPM emits ReleaseRegistrationFee on TournamentEnrollmentRejected
    Given a RegistrationPM with tournament_root "tournament_456"
    And a TournamentEnrollmentRejected event with player_root "player_123", reservation_id "res_001", reason "Tournament full"
    And destinations with sequences player=3
    When the RegistrationPM handles enrollment_rejected
    Then a ReleaseRegistrationFee command is sent to the "reservation" domain
    And the ReleaseRegistrationFee command has reservation_id "res_001"
    And the ReleaseRegistrationFee command has reason "Tournament full"

  # ==========================================================================
  # RegistrationPM — Missing Fee Default
  # ==========================================================================
  # When RegistrationRequested carries no fee, the PM defaults the recorded
  # amount to zero so downstream replay has a well-formed Currency value.

  @EU-0441
  Scenario: RegistrationPM defaults missing fee to zero
    Given a RegistrationPM with player_root "player_123"
    And a RegistrationRequested event with tournament_root "tournament_456", reservation_id "res_001" and no fee
    And destinations with sequences tournament=5
    When the RegistrationPM handles registration_requested
    Then the process event is a angzarr_client.proto.examples.v1.RegistrationInitiated event
    And the RegistrationInitiated event has fee amount 0

  # HandComplete -> EndHand was moved out of the PM and lives in
  # TableSyncCompleteSaga. See saga.feature for coverage.
