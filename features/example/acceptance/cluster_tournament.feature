# Allocated: EA-0006 .. EA-0013

Feature: Cluster Tournament Acceptance
  Tournament-scoped acceptance scenarios that exercise the full
  tournament lifecycle against a deployed poker cluster: creating a
  tournament, registering players, starting play, advancing blinds,
  processing rebuys, eliminating players, and completing the
  tournament — together with the per-hand lifecycle that eliminations
  hang off of.

  Hand completion is fast-forwarded via AwardPot rather than scripted
  through every betting action: the tournament lifecycle is what
  these scenarios are pinning, and the betting-round correctness is
  already covered by features/example/poker/hand.feature.

  # CLUSTER-ONLY: validated against a deployed cluster

  Background:
    Given the poker cluster is reachable

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
    Then within 5 seconds the table starts the hand and cards are dealt to the players

    When the hand at table "Spring-1" is awarded to "Alice"
    And I eliminate player "Bob" from tournament "Spring"
    Then tournament "Spring" has players_remaining 1

    When I complete tournament "Spring" with winner "Alice"
    Then tournament "Spring" has status "Completed"
    And tournament "Spring" winner is "Alice"

  # ===========================================================================
  # Multi-hand with blind advance, rebuy, and sequential eliminations.
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
    Then within 5 seconds the table starts the hand and cards are dealt to the players
    When the hand at table "Majors-1" is awarded to "Alice"

    # --- Blinds advance between hands ---
    And I advance blind level on tournament "Majors"
    Then tournament "Majors" has current_level 2

    # --- Hand 2: Charlie takes a bad beat, rebuys in ---
    When a hand starts at table "Majors-1"
    And the hand at table "Majors-1" is awarded to "Alice"
    And I process a rebuy for player "Charlie" on tournament "Majors"
    Then tournament "Majors" has total_prize_pool 1600

    # --- Hand 3: Bob busts ---
    When a hand starts at table "Majors-1"
    And the hand at table "Majors-1" is awarded to "Alice"
    And I eliminate player "Bob" from tournament "Majors"
    Then tournament "Majors" has players_remaining 2

    # --- Hand 4: Charlie busts, Alice wins heads-up ---
    When a hand starts at table "Majors-1"
    And the hand at table "Majors-1" is awarded to "Alice"
    And I eliminate player "Charlie" from tournament "Majors"
    Then tournament "Majors" has players_remaining 1

    When I complete tournament "Majors" with winner "Alice"
    Then tournament "Majors" has status "Completed"
    And tournament "Majors" winner is "Alice"

  # ===========================================================================
  # Full lifecycle — exercises tournament play end-to-end: registration,
  # buy-ins, rebuys, pause / resume, a real betting hand, blind advance,
  # eliminations, and withdrawals.
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

    # --- Player-side financial primitives ---
    When player "Alice" reserves 200 chips for an upcoming bet
    Then player "Alice" has reserved funds 200
    When player "Alice" confirms the 200-chip deduction
    Then player "Alice" has bankroll 4800
    And player "Alice" has reserved funds 0

    When player "Bob" reserves 150 chips for an upcoming bet
    And player "Bob" releases the reserved 150 chips

    When player "Dana" withdraws 500 chips
    Then player "Dana" has bankroll 2500

    # --- Tournament setup ---
    Given a tournament "Worlds" with buy_in 500, starting_stack 1500, max_players 9, min_players 2, rebuys enabled with cost 100 and chips 1000
    When I open registration on tournament "Worlds"

    # --- Tournament registration ---
    When player "Alice" initiates tournament registration for "Worlds"
    Then the registration request was accepted
    When player "Bob" initiates tournament registration for "Worlds"
    Then the registration request was accepted
    When player "Charlie" initiates tournament registration for "Worlds"
    Then the registration request was accepted

    When player "Alice" registers for tournament "Worlds"
    And player "Bob" registers for tournament "Worlds"
    And player "Charlie" registers for tournament "Worlds"
    And player "Dana" registers for tournament "Worlds"
    Then tournament "Worlds" has 4 registered players
    And tournament "Worlds" has total_prize_pool 2000

    # --- Buy-ins and seating ---
    When I create a Texas Hold'em table "Worlds-1" with blinds 5/10
    And player "Alice" initiates buy-in to table "Worlds-1" at seat 0 for 1500
    Then the buy-in request was accepted
    When player "Bob" initiates buy-in to table "Worlds-1" at seat 1 for 1500
    Then the buy-in request was accepted

    When player "Alice" joins table "Worlds-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "Worlds-1" at seat 1 with buy-in 1500
    And player "Charlie" joins table "Worlds-1" at seat 2 with buy-in 1500
    And player "Dana" joins table "Worlds-1" at seat 3 with buy-in 1500

    When I close registration on tournament "Worlds"
    And I start tournament "Worlds"

    # --- Pause / resume mid-tournament ---
    When I pause tournament "Worlds"
    Then tournament "Worlds" has status "Paused"
    When I resume tournament "Worlds"
    Then tournament "Worlds" has status "Running"

    # --- A real betting hand played out action by action ---
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

    # --- Mid-tournament progression ---
    When I advance blind level on tournament "Worlds"
    Then tournament "Worlds" has current_level 2

    # --- Rebuy ---
    When player "Dana" initiates rebuy on tournament "Worlds" at table "Worlds-1" seat 3
    Then the rebuy request was accepted
    When I process a rebuy for player "Dana" on tournament "Worlds"
    Then tournament "Worlds" has total_prize_pool 2100

    # --- Eliminate down to a winner ---
    When a hand starts at table "Worlds-1"
    And the hand at table "Worlds-1" is awarded to "Alice"
    And I eliminate player "Dana" from tournament "Worlds"
    Then tournament "Worlds" has players_remaining 3

    When a hand starts at table "Worlds-1"
    And the hand at table "Worlds-1" is awarded to "Alice"
    And I eliminate player "Bob" from tournament "Worlds"
    Then tournament "Worlds" has players_remaining 2

    When a hand starts at table "Worlds-1"
    And the hand at table "Worlds-1" is awarded to "Alice"
    And I eliminate player "Charlie" from tournament "Worlds"
    Then tournament "Worlds" has players_remaining 1

    When I complete tournament "Worlds" with winner "Alice"
    Then tournament "Worlds" has status "Completed"
    And tournament "Worlds" winner is "Alice"

    # --- Cleanup ---
    When player "Alice" withdraws 1000 chips
    Then player "Alice" has bankroll 3800

  # ===========================================================================
  # Color-up chip race (TDA Rule 28). Between blind levels, low-denomination
  # chips are removed from play and exchanged for higher-denomination chips
  # via a randomised "race" for any odd chips that don't divide evenly.
  # ===========================================================================

  @tournament @color-up @cluster
  @EA-0011
  Scenario: Color-up at level transition removes low-denom chips from every stack
    Given registered players with bankroll:
      | name    | bankroll |
      | Alice   | 5000     |
      | Bob     | 5000     |
      | Charlie | 5000     |
    And a tournament "ColorUp" with buy_in 500, starting_stack 1500, max_players 9, min_players 2
    When I create a Texas Hold'em table "ColorUp-1" with blinds 5/10
    And player "Alice" joins table "ColorUp-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "ColorUp-1" at seat 1 with buy-in 1500
    And player "Charlie" joins table "ColorUp-1" at seat 2 with buy-in 1500
    And I open registration on tournament "ColorUp"
    And player "Alice" registers for tournament "ColorUp"
    And player "Bob" registers for tournament "ColorUp"
    And player "Charlie" registers for tournament "ColorUp"
    And I start tournament "ColorUp"

    # The color-up retires 25-denom chips and exchanges them for 100-denom
    # chips, racing any odd remainders to whole 100s. Total chips in play
    # must be conserved (modulo legal rounding at the race step).
    When I advance blind level on tournament "ColorUp" with color-up:
      | retire_denomination | new_denomination |
      | 25                  | 100              |
    Then the color-up completes on tournament "ColorUp"
    And every active player's stack contains no chips of denomination 25
    And the total chips in play before and after the color-up are equal

  # ===========================================================================
  # Table balancing (TDA Rule 14). When tables differ in active player count
  # by more than one, the tournament must move a player from the larger
  # table to the smaller. The moved player's stack travels with them.
  # ===========================================================================

  @tournament @balancing @cluster
  @EA-0012
  Scenario: Table balancing moves a player when one table is short
    Given registered players with bankroll:
      | name    | bankroll |
      | Alice   | 5000     |
      | Bob     | 5000     |
      | Charlie | 5000     |
      | Dana    | 5000     |
      | Eve     | 5000     |
    And a tournament "Balance" with buy_in 500, starting_stack 1500, max_players 9, min_players 2
    When I create a Texas Hold'em table "Balance-1" with blinds 5/10
    And I create a Texas Hold'em table "Balance-2" with blinds 5/10
    And player "Alice" joins table "Balance-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "Balance-1" at seat 1 with buy-in 1500
    And player "Charlie" joins table "Balance-1" at seat 2 with buy-in 1500
    And player "Dana" joins table "Balance-1" at seat 3 with buy-in 1500
    And player "Eve" joins table "Balance-2" at seat 0 with buy-in 1500
    And I open registration on tournament "Balance"
    And every player registers for tournament "Balance"
    And I start tournament "Balance"

    # Table-1 has 4 players, Table-2 has 1. The tournament must rebalance
    # to (3, 2) or (2, 3), reseating one player at Table-2 with their
    # existing stack intact.
    When I trigger table balancing on tournament "Balance"
    Then a player is moved from one table to the other on tournament "Balance"
    And table "Balance-1" has 3 active players
    And table "Balance-2" has 2 active players
    And the moved player's stack on table "Balance-2" equals their stack on table "Balance-1" before the move

  # ===========================================================================
  # Hand-for-hand on the bubble (TDA Rule 12). When the next elimination is
  # the bubble (last out-of-the-money finisher), all tables must complete
  # one hand simultaneously before any starts the next, so a single player
  # cannot stall to pass the bubble onto another table.
  # ===========================================================================

  @tournament @bubble @cluster
  @EA-0013
  Scenario: Bubble triggers hand-for-hand play across all active tables
    Given registered players with bankroll:
      | name    | bankroll |
      | Alice   | 5000     |
      | Bob     | 5000     |
      | Charlie | 5000     |
      | Dana    | 5000     |
    And a tournament "Bubble" with buy_in 500, starting_stack 1500, max_players 9, min_players 2
    And the tournament pays positions 1,2,3 at percentages 50,30,20
    When I create a Texas Hold'em table "Bubble-1" with blinds 5/10
    And I create a Texas Hold'em table "Bubble-2" with blinds 5/10
    And player "Alice" joins table "Bubble-1" at seat 0 with buy-in 1500
    And player "Bob" joins table "Bubble-1" at seat 1 with buy-in 1500
    And player "Charlie" joins table "Bubble-2" at seat 0 with buy-in 1500
    And player "Dana" joins table "Bubble-2" at seat 1 with buy-in 1500
    And I open registration on tournament "Bubble"
    And every player registers for tournament "Bubble"
    And I start tournament "Bubble"

    # 4 players; 3 paid; the next elimination is the bubble. The tournament
    # enters hand-for-hand play: tables must wait for every hand to
    # complete before any starts a new one.
    When the tournament enters bubble play
    Then tournament "Bubble" begins hand-for-hand play
    And table "Bubble-1" is waiting for the synchronised hand to complete
    And table "Bubble-2" is waiting for the synchronised hand to complete

    # First synchronised hand: Bubble-1 finishes first, Bubble-2 still in
    # progress. Bubble-1 must NOT start the next hand until Bubble-2
    # completes the current one.
    When a hand completes at table "Bubble-1"
    Then table "Bubble-1" has finished its synchronised hand
    And table "Bubble-2" is waiting for the synchronised hand to complete
    And table "Bubble-1" cannot start a new hand yet

    When a hand completes at table "Bubble-2"
    Then the synchronised hand-for-hand round completes on tournament "Bubble"
    And both tables can start the next synchronised hand

    # On bubble break (an elimination), hand-for-hand ends.
    When I eliminate player "Dana" from tournament "Bubble"
    Then hand-for-hand play ends on tournament "Bubble"
    And tournament "Bubble" has players_remaining 3
