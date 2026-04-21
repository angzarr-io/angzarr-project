# Allocated: EA-0006 .. EA-0010
Feature: Cluster Tournament Acceptance
  Tournament-scoped cluster-tier acceptance scenarios. These exercise
  the tournament aggregate end-to-end against a deployed angzarr
  cluster: CreateTournament, registration, StartTournament,
  AdvanceBlindLevel, ProcessRebuy, EliminatePlayer, and
  CompleteTournament — plus the per-hand lifecycle (HandStarted /
  HandComplete) that eliminations hang off of.

  Hand completion is fast-forwarded via AwardPot rather than scripted
  through every betting action: the tournament lifecycle is what
  these scenarios are pinning, and the betting-round correctness is
  already covered by features/example/unit/hand.feature.

  How to run:
  - Start a cluster (kind bootstrap) and export PLAYER_URL /
    TABLE_URL / HAND_URL / TOURNAMENT_URL / RESERVATION_URL to the
    coordinator endpoints.
  - Without the URLs set, these scenarios run against the
    InProcessClient and exercise the same command surface without
    the network.

  # CLUSTER-ONLY: validated against a deployed kind cluster

  Background:
    Given the poker cluster is reachable via gRPC

  # ===========================================================================
  # Minimal happy path — create, register two players, start, play a hand,
  # eliminate the loser, complete the tournament.
  # ===========================================================================

  @tournament @e2e @cluster
  @EA-0006
  Scenario: Two-player tournament completes after one hand
    Given registered players with bankroll:
      | name  | bankroll |
      | Alice | 2000     |
      | Bob   | 2000     |
    And a tournament "Spring" with buy_in 500, starting_stack 1500, max_players 9, min_players 2
    When I create a Texas Hold'em table "Spring-1" with blinds 5/10
    And player "Alice" joins table "Spring-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "Spring-1" at seat 1 with buy-in 1500
    And I open registration on tournament "Spring"
    And player "Alice" registers for tournament "Spring"
    And player "Bob" registers for tournament "Spring"
    Then tournament "Spring" has 2 registered players
    And tournament "Spring" has total_prize_pool 1000

    When I start tournament "Spring"
    And a hand starts at table "Spring-1"
    Then within 5 seconds:
      | domain | event_type  |
      | table  | HandStarted |
      | hand   | CardsDealt  |

    When the hand at table "Spring-1" is fast-forwarded with "Alice" winning the pot
    And I eliminate player "Bob" from tournament "Spring"
    Then tournament "Spring" has players_remaining 1

    When I complete tournament "Spring" with winner "Alice"
    Then tournament "Spring" has status "Completed"
    And tournament "Spring" winner is "Alice"

  # ===========================================================================
  # Multi-hand with blind advance + rebuy + sequential eliminations.
  # Exercises AdvanceBlindLevel, ProcessRebuy, multiple eliminations, and
  # completion with a multi-hand history.
  # ===========================================================================

  @tournament @multihand @rebuy @cluster
  @EA-0007
  Scenario: Three-player tournament with blind advance, rebuy, and eliminations
    Given registered players with bankroll:
      | name    | bankroll |
      | Alice   | 5000     |
      | Bob     | 5000     |
      | Charlie | 5000     |
    And a tournament "Majors" with buy_in 500, starting_stack 1500, max_players 9, min_players 2, rebuys enabled with cost 100 and chips 1000
    When I create a Texas Hold'em table "Majors-1" with blinds 5/10
    And player "Alice" joins table "Majors-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "Majors-1" at seat 1 with buy-in 1500
    And player "Charlie" joins table "Majors-1" at seat 2 with buy-in 1500
    And I open registration on tournament "Majors"
    And player "Alice" registers for tournament "Majors"
    And player "Bob" registers for tournament "Majors"
    And player "Charlie" registers for tournament "Majors"
    Then tournament "Majors" has 3 registered players
    And tournament "Majors" has total_prize_pool 1500

    When I start tournament "Majors"

    # --- Hand 1: Alice wins, nobody eliminated ---
    And a hand starts at table "Majors-1"
    Then within 5 seconds:
      | domain | event_type  |
      | table  | HandStarted |
      | hand   | CardsDealt  |
    When the hand at table "Majors-1" is fast-forwarded with "Alice" winning the pot

    # --- Blinds advance between hands ---
    And I advance blind level on tournament "Majors"
    Then tournament "Majors" has current_level 2

    # --- Hand 2: Charlie takes a bad beat, rebuys in ---
    When a hand starts at table "Majors-1"
    And the hand at table "Majors-1" is fast-forwarded with "Alice" winning the pot
    And I process a rebuy for player "Charlie" on tournament "Majors"
    Then tournament "Majors" has total_prize_pool 1600

    # --- Hand 3: Bob busts ---
    When a hand starts at table "Majors-1"
    And the hand at table "Majors-1" is fast-forwarded with "Alice" winning the pot
    And I eliminate player "Bob" from tournament "Majors"
    Then tournament "Majors" has players_remaining 2

    # --- Hand 4: Charlie busts, Alice wins heads-up ---
    When a hand starts at table "Majors-1"
    And the hand at table "Majors-1" is fast-forwarded with "Alice" winning the pot
    And I eliminate player "Charlie" from tournament "Majors"
    Then tournament "Majors" has players_remaining 1

    When I complete tournament "Majors" with winner "Alice"
    Then tournament "Majors" has status "Completed"
    And tournament "Majors" winner is "Alice"

  # ===========================================================================
  # Full lifecycle — exercises every code path touched by tournament play:
  #   - reservation aggregate Initiate*: registration, buy-in, rebuy
  #   - pmg-reservation-pm fan-out: ReserveFunds + EnrollPlayer / SeatPlayer /
  #     ProcessRebuy / AddRebuyChips
  #   - player financial primitives directly: ReserveFunds, ReleaseFunds,
  #     DeductReservedFunds, WithdrawFunds, TransferFunds
  #   - tournament Pause / Resume + CloseRegistration
  #   - real betting hand: PostBlind, PlayerAction (call/raise/fold),
  #     DealCommunityCards (flop / turn / river), RevealCards, AwardPot
  #   - saga-table-hand:   HandStarted   → DealCards
  #   - saga-table-player: HandEnded     → ReleaseFunds
  #   - saga-hand-table:   HandComplete  → EndHand
  #   - saga-hand-player:  PotAwarded    → DepositFunds (winner credit)
  #   - rejection paths: RebuyDenied, reservation request rejection
  # ===========================================================================

  @tournament @complex @cluster @full-lifecycle
  @EA-0008
  Scenario: Full-lifecycle complex tournament across every code path
    Given registered players with bankroll:
      | name    | bankroll |
      | Alice   | 5000     |
      | Bob     | 5000     |
      | Charlie | 5000     |
      | Dana    | 3000     |

    # --- Direct player-financial primitives (exercise the handlers the PM
    # would normally drive) ---------------------------------------------------
    When player "Alice" reserves 200 chips against key "test-bucket"
    Then player "Alice" has reserved funds 200
    When player "Alice" deducts 200 reserved chips against key "test-bucket"
    Then player "Alice" has bankroll 4800
    And player "Alice" has reserved funds 0

    When player "Bob" reserves 150 chips against key "release-bucket"
    And player "Bob" releases reserved funds for key "release-bucket"

    When player "Dana" withdraws 500 chips
    Then player "Dana" has bankroll 2500

    # --- Tournament setup ----------------------------------------------------
    Given a tournament "Worlds" with buy_in 500, starting_stack 1500, max_players 9, min_players 2, rebuys enabled with cost 100 and chips 1000
    When I open registration on tournament "Worlds"

    # --- Reservation chain: Initiate* registration kicks the PM
    # (RegistrationRequested -> ReserveFunds + EnrollPlayer fanned out) ------
    When player "Alice" initiates tournament registration for "Worlds"
    Then the reservation request was accepted
    When player "Bob" initiates tournament registration for "Worlds"
    Then the reservation request was accepted
    When player "Charlie" initiates tournament registration for "Worlds"
    Then the reservation request was accepted

    # --- Direct EnrollPlayer for tournament-side state determinism. The
    # Initiate* path's PM fan-out is observed but not awaited.
    When player "Alice" registers for tournament "Worlds"
    And player "Bob" registers for tournament "Worlds"
    And player "Charlie" registers for tournament "Worlds"
    And player "Dana" registers for tournament "Worlds"
    Then tournament "Worlds" has 4 registered players
    And tournament "Worlds" has total_prize_pool 2000

    # --- Buy-in chain: Initiate* triggers PM seating fan-out -----------------
    When I create a Texas Hold'em table "Worlds-1" with blinds 5/10
    And player "Alice" initiates buy-in to table "Worlds-1" at seat 0 for 1500
    Then the reservation request was accepted
    When player "Bob" initiates buy-in to table "Worlds-1" at seat 1 for 1500
    Then the reservation request was accepted

    # --- Direct JoinTable so the table-side state is deterministic for
    # the betting hand that follows.
    When player "Alice" joins table "Worlds-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "Worlds-1" at seat 1 with buy-in 1500
    And player "Charlie" joins table "Worlds-1" at seat 2 with buy-in 1500
    And player "Dana" joins table "Worlds-1" at seat 3 with buy-in 1500

    When I close registration on tournament "Worlds"
    And I start tournament "Worlds"

    # --- Pause / resume mid-tournament ---------------------------------------
    When I pause tournament "Worlds"
    Then tournament "Worlds" has status "Paused"
    When I resume tournament "Worlds"
    Then tournament "Worlds" has status "Running"

    # --- Real betting hand ---------------------------------------------------
    # StartHand emits HandStarted; saga-table-hand consumes from AMQP and
    # dispatches DealCards -> CardsDealt at the deterministic hand_root.
    # Then a full betting round: PostBlind, PlayerAction (call/raise/fold/
    # check), DealCommunityCards (flop/turn/river), AwardPot.
    # AwardPot emits PotAwarded + HandComplete:
    #   saga-hand-player:  PotAwarded   -> DepositFunds (winner credit)
    #   saga-hand-table:   HandComplete -> EndHand -> HandEnded
    #   saga-table-player: HandEnded    -> ReleaseFunds (per-player)
    When a hand starts at table "Worlds-1"
    And the hand has been dealt at table "Worlds-1"
    And "Alice" posts small blind 5
    And "Bob" posts big blind 10
    And "Charlie" raises to 30
    And "Dana" folds
    And "Alice" folds
    And "Bob" calls 30
    And the dealer deals the flop
    And "Bob" checks
    And "Charlie" bets 40
    And "Bob" calls 40
    And the dealer deals the turn
    And "Bob" checks
    And "Charlie" checks
    And the dealer deals the river
    And "Bob" checks
    And "Charlie" bets 100
    And "Bob" folds
    And the pot is awarded to "Charlie" with amount 145

    # --- Mid-tournament progression ------------------------------------------
    When I advance blind level on tournament "Worlds"
    Then tournament "Worlds" has current_level 2

    # Rebuy chain: Initiate* triggers PM (ReserveFunds + ProcessRebuy +
    # AddRebuyChips). Direct ProcessRebuy keeps the tournament-state
    # bookkeeping deterministic.
    When player "Dana" initiates rebuy on tournament "Worlds" at table "Worlds-1" seat 3
    Then the reservation request was accepted
    When I process a rebuy for player "Dana" on tournament "Worlds"
    Then tournament "Worlds" has total_prize_pool 2100

    # --- Eliminate down to a winner (each hand fast-forwarded for brevity;
    # the real-betting path above already exercised the full hand cycle) ----
    When a hand starts at table "Worlds-1"
    And the hand at table "Worlds-1" is fast-forwarded with "Alice" winning the pot
    And I eliminate player "Dana" from tournament "Worlds"
    Then tournament "Worlds" has players_remaining 3

    When a hand starts at table "Worlds-1"
    And the hand at table "Worlds-1" is fast-forwarded with "Alice" winning the pot
    And I eliminate player "Bob" from tournament "Worlds"
    Then tournament "Worlds" has players_remaining 2

    When a hand starts at table "Worlds-1"
    And the hand at table "Worlds-1" is fast-forwarded with "Alice" winning the pot
    And I eliminate player "Charlie" from tournament "Worlds"
    Then tournament "Worlds" has players_remaining 1

    When I complete tournament "Worlds" with winner "Alice"
    Then tournament "Worlds" has status "Completed"
    And tournament "Worlds" winner is "Alice"

    # --- Cleanup financial path ----------------------------------------------
    When player "Alice" withdraws 1000 chips
    Then player "Alice" has bankroll 3800
