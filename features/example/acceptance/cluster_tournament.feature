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
