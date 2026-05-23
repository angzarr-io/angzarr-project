# Allocated: EU-0001 .. EU-0099, EU-0568, EU-1008, EU-1009, EU-1100 .. EU-1124,
#            EU-1130 .. EU-1135, EU-1140 .. EU-1146, EU-1150,
#            EU-1170 .. EU-1172, EU-1200 .. EU-1201, EU-1210 .. EU-1211,
#            EU-1220 .. EU-1221, EU-1230 .. EU-1233, EU-1240 .. EU-1242,
#            EU-1250, EU-1260 .. EU-1261,
#            EU-1270 .. EU-1278, EU-1280 .. EU-1282, EU-1284 .. EU-1290,
#            EU-1295 .. EU-1296,
#            EU-1320 .. EU-1341 (stud-specific),
#            EU-1342 .. EU-1365 (TDA betting/disclosure gap scenarios)
Feature: Hand aggregate logic
  A hand manages a single poker hand: dealing, betting rounds, community
  cards, and showdown. Each hand is an isolated consistency boundary with
  its own history.

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  #   TDA       = Poker Tournament Directors Association Rules, 2024 v1.0
  #               (Oct 9, 2024). Canonical at https://www.pokertda.com/.
  #               Rule numbers refer to the longform document.
  #   Robert's  = "Robert's Rules of Poker" by Bob Ciaffone, Version 11.
  #               Canonical at https://www.pagat.com/docs/RobsPkrRules11.pdf.
  #   WSOP      = World Series of Poker Official Tournament Rules, 2025.
  #               Canonical at https://www.wsop.com/.
  # See angzarr docs site or features/example/RULES.md for the full
  # cross-reference between scenarios and rule sources.

  # Why this aggregate exists:
  # - Hands have complex, well-defined state machines (phases, betting rounds)
  # - Hand-level activity (actions, dealing) is high-frequency
  # - Hand logic is game-variant-specific (Hold'em vs Omaha vs Draw)
  # - Separating from table enables parallel hand processing (multi-table)

  # What breaks if this is wrong:
  # - Players could act out of turn
  # - Betting amounts could violate minimum raise rules
  # - Community cards could be dealt in wrong phases
  # - Showdown could award pots incorrectly

  # Patterns enabled by this aggregate:
  # - State machine enforcement: DEALING->BLINDS->BETTING->FLOP->... Each phase has
    # valid transitions; invalid actions rejected. Same pattern applies to
    # order fulfillment, insurance claims, approval workflows.
  # - Turn-based action tracking: Only one player can act at a time. Same pattern
    # applies to board games, auction rounds, approval chains.
  # - High-frequency activity streams exercise snapshot optimization. Same
    # pattern applies to IoT sensors, trading systems.
  # - Variant polymorphism: Same aggregate handles Hold'em/Omaha/Draw with
    # different rules. Same pattern applies to payment methods, shipping carriers.

  # Why poker exercises these patterns well:
  # - State transitions are unambiguous: can't deal turn before flop
  # - Turn order is strictly enforced: only the player whose turn it is can act
  # - Activity is high: blinds, many actions, three community-card streets
  # - Rules vary by variant: 2 hole cards (Hold'em) vs 4 (Omaha) vs 5 (Draw)

  # ==========================================================================
  # Card Dealing
  # ==========================================================================
  # Rule: Robert's SC Hold'em / SC Omaha / SC Draw / SC Stud (Ciaffone
  #       v11) and WSOP IX (2025) - variant-specific hole-card counts:
  #       2 for Hold'em, 4 for Omaha, 5 for Draw, 2 down + 1 up for Stud.
  # Dealing initializes the hand with hole cards for each player. The number
  # of hole cards depends on game variant (2 for Hold'em, 4 for Omaha, 5 for Draw).

  @EU-0001
  Scenario: Deal Texas Hold'em hand to 2 players
    Given the hand has not yet been dealt
    When a Texas Hold'em hand is dealt to:
      | player   | position | stack |
      | player-1 | 0        | 500   |
      | player-2 | 1        | 500   |
    Then each player has 2 hole cards
    And the remaining deck has 48 cards

  @EU-0002
  Scenario: Deal Omaha hand to 3 players
    Given the hand has not yet been dealt
    When an Omaha hand is dealt to:
      | player   | position | stack |
      | player-1 | 0        | 500   |
      | player-2 | 1        | 500   |
      | player-3 | 2        | 500   |
    Then each player has 4 hole cards
    And the remaining deck has 40 cards

  @EU-0003
  Scenario: Deal Five Card Draw hand to 4 players
    Given the hand has not yet been dealt
    When a Five Card Draw hand is dealt to:
      | player   | position | stack |
      | player-1 | 0        | 500   |
      | player-2 | 1        | 500   |
      | player-3 | 2        | 500   |
      | player-4 | 3        | 500   |
    Then each player has 5 hole cards
    And the remaining deck has 32 cards

  @EU-0004
  Scenario: Deterministic shuffle with seed
    Given the hand has not yet been dealt
    When a Texas Hold'em hand is dealt with seed "test-seed-123" to:
      | player   | position | stack |
      | player-1 | 0        | 500   |
      | player-2 | 1        | 500   |
    Then player "player-1" holds the cards expected for seed "test-seed-123"

  @EU-0005
  Scenario: Cannot deal cards twice
    Given a Texas Hold'em hand has already been dealt
    When the dealer attempts to deal the hand again
    Then the deal is refused because the hand has already been dealt

  @EU-0006
  Scenario: Cannot deal with fewer than 2 players
    Given the hand has not yet been dealt
    When a Texas Hold'em hand is dealt to only 1 player
    Then the deal is refused because at least 2 players are required

  # ==========================================================================
  # Blind Posting
  # ==========================================================================
  # Rule: WSOP IX Texas Hold'em (2025) - blind structure ("two blinds...
  #       multiple blinds, an ante, or combination").
  # Rule: TDA Rule 30 (2024) - short-stacked / absent players: blinds
  #       posted as available; remainder forfeit if absent.
  # Blinds are forced bets that seed the pot and drive action. Small blind
  # is posted first, then big blind. Short-stacked players post all-in blinds.

  @EU-0007
  Scenario: Post small blind
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When player-1 posts the small blind of 5
    Then the small blind is posted at 5
    And player-1's stack is 495
    And the pot is 5

  @EU-0008
  Scenario: Post big blind
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And player-1 has posted a blind of 5
    When player-2 posts the big blind of 10
    Then the big blind is posted at 10
    And the pot is 15

  @EU-0009
  Scenario: Post all-in blind when short-stacked
    # Real poker (TDA Rule 30): a forced bet that consumes the entire remaining
    # stack puts the player all-in for that hand. The all-in status is what
    # downstream side-pot accounting (EU-1100..1109) keys off - without it,
    # the short-stack blind silently breaks pot construction.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-1 | 0        | 3     |
      | player-2 | 1        | 500   |
    When player-1 posts the small blind of 5
    Then the small blind is posted at 3
    And player-1's stack is 0
    And player-1 is all-in

  # ==========================================================================
  # Player Actions
  # ==========================================================================
  # Rule: TDA Rule 3 (2024) - official terminology: bet, raise, call, fold,
  #       check, all-in, complete.
  # Rule: TDA Rule 43 (2024) - minimum bet/raise amounts.
  # Rule: TDA Rule 55 (2024) - invalid declarations (call when no bet,
  #       raise when no bet must = at least min bet, check facing a bet =
  #       call/fold).
  # Actions are the core gameplay: fold, check, call, bet, raise, all-in.
  # Each action has validation rules (can't check when facing a bet, minimum
  # raise amounts). Invalid actions are rejected, not auto-corrected.

  @EU-0010
  Scenario: Player folds
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When player-1 folds
    Then player-1 is folded

  @EU-0011
  Scenario: Player checks when no bet
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When player-1 checks
    Then player-1's check is recorded

  @EU-0012
  Scenario: Player calls the big blind
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 calls for 5
    Then player-1's call of 5 is recorded
    And the pot is 20

  @EU-0013
  Scenario: Player bets
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When player-1 bets 20
    Then player-1's bet of 20 is recorded
    And the next player owes 20 to call

  @EU-0014
  Scenario: Player raises
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 raises to 30
    Then player-1's raise puts 25 more chips into the pot
    # The total raise reaches 30, so the next actor must reach 30 to call.
    And the next player owes 30 to call

  @EU-0015
  Scenario: Player goes all-in
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-1 | 0        | 50    |
      | player-2 | 1        | 500   |
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 goes all-in for 50
    Then player-1's all-in is recorded
    And player-1's stack is 0

  @EU-0016
  Scenario: Cannot check when facing a bet
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 attempts to check
    Then the check is refused because a player cannot check when facing a bet

  @EU-0017
  Scenario: Cannot bet less than minimum
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When player-1 attempts to bet 5
    Then the bet is refused because it is below the minimum bet

  # ==========================================================================
  # Community Cards
  # ==========================================================================
  # Rule: WSOP IX Texas Hold'em / Omaha (2025) - flop (3 cards), turn (1
  #       card), river (1 card), with one card burned before each.
  # Rule: TDA Rule 38 (2024) - one burn per street.
  # Community cards are shared by all players. Hold'em/Omaha have flop (3),
  # turn (1), river (1). Draw games have no community cards. Dealing community
  # cards transitions between betting rounds.

  @EU-0018
  Scenario: Deal the flop
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When the dealer deals the flop
    Then 3 community cards are revealed
    And the hand is in the FLOP phase
    And 3 cards have been removed from the remaining deck

  @EU-0019
  @wip
  Scenario: Deal the turn
    Given a Texas Hold'em hand has been dealt to 2 players
    And the flop has been dealt
    And the flop betting round is complete
    When the dealer deals the turn
    Then 1 community card is revealed
    And the hand is in the TURN phase
    And there are 4 community cards in play

  @EU-0020
  @wip
  Scenario: Deal the river
    Given a Texas Hold'em hand has been dealt to 2 players
    And the flop and turn have been dealt
    And the turn betting round is complete
    When the dealer deals the river
    Then the hand is in the RIVER phase
    And there are 5 community cards in play

  @EU-0021
  Scenario: Cannot deal community cards in Five Card Draw
    Given a Five Card Draw hand has been dealt to 2 players
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When the dealer attempts to deal community cards
    Then the deal is refused because Five Card Draw has no community cards

  # ==========================================================================
  # Draw Phase (Five Card Draw)
  # ==========================================================================
  # Rule: WSOP IX Draw Games (2025) - discard/draw mechanics.
  # Rule: TDA RP-17 (2024) - limping is allowed in single-draw games.
  # In draw games, players discard and receive new cards. Standing pat means
  # keeping all cards. Draw is only valid in draw game variants.

  @EU-0022
  Scenario: Player discards and draws cards
    Given a Five Card Draw hand has been dealt to 2 players
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And player-1's initial hole cards have been captured as "pre_draw"
    When player-1 discards cards at positions 0, 2, and 4
    Then player-1 has discarded 3 cards and drawn 3 cards
    And player-1 has 5 hole cards
    # Discarding positions [0, 2, 4] must replace exactly those positions and
    # leave positions 1 and 3 unchanged.
    And player-1's card at position 1 matches the "pre_draw" card at position 1
    And player-1's card at position 3 matches the "pre_draw" card at position 3

  @EU-0023
  Scenario: Player stands pat (no discard)
    Given a Five Card Draw hand has been dealt to 2 players
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When player-1 stands pat
    Then player-1 has discarded 0 cards and drawn 0 cards

  @EU-0024
  Scenario: Cannot draw in Texas Hold'em
    Given a Texas Hold'em hand has been dealt to 2 players
    And blinds have been posted bringing the pot to 15
    When player-1 attempts to draw
    Then the draw is refused because Texas Hold'em does not support drawing

  # ==========================================================================
  # Showdown - Card Reveal
  # ==========================================================================
  # Rule: TDA Rule 13A (2024) - proper tabling: turn all cards face up so
  #       the dealer and players can read the hand clearly.
  # Rule: TDA Rule 14 (2024) - discarding face-down does not automatically
  #       kill the hand if cards remain identifiable.
  # At showdown, remaining players reveal or muck their cards. Revealing
  # triggers hand evaluation; mucking concedes without showing.

  @EU-0025
  Scenario: Player reveals cards at showdown
    Given a Texas Hold'em hand has reached showdown with 2 players
    When player-1 reveals their cards
    Then player-1's cards are tabled
    And player-1's hand ranking is determined

  @EU-0026
  Scenario: Player mucks cards
    Given a Texas Hold'em hand has reached showdown with 2 players
    When player-1 mucks
    Then player-1's hand is mucked

  # ==========================================================================
  # Pot Award
  # ==========================================================================
  # Rule: TDA Rule 12 (2024) - cards speak: best hand wins regardless of
  #       verbal declaration.
  # Rule: TDA Rule 17B (2024) - uncontested showdown: last live cards win
  #       without tabling.
  # Pots are awarded after showdown (best hand) or when all but one player
  # folds. Awarding the pot completes the hand and returns control to table.

  @EU-0027
  Scenario: Award pot to single winner
    Given a Texas Hold'em hand has reached showdown with 2 players
    And player-1 tabled a FLUSH
    And player-2 mucked
    When the pot of 15 is awarded to player-1
    Then player-1 wins 15

  @EU-0028
  Scenario: Awarding the pot completes the hand
    Given a Texas Hold'em hand has reached showdown with 2 players
    When the pot of 15 is awarded to player-1
    Then the hand is complete

  # ==========================================================================
  # Hand Evaluation Logic
  # ==========================================================================
  # Rule: Robert's Rules section 1 (Ciaffone v11) - universal 10-rank hierarchy.
  # Rule: Robert's section 31 (Ciaffone v11) - kicker tiebreak by highest
  #       remaining card.
  # Hand ranking (high card through royal flush) determines winners. These
  # scenarios verify the evaluator correctly ranks hands and compares kickers.

  @EU-0029
  @wip
  Scenario: Royal flush beats straight flush
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | As Ks      | Qs Js Ts 2c 3d     |
      | player-2 | 9s 8s      | Qs Js Ts 2c 3d     |
    When hands are evaluated
    Then player-1 has a ROYAL_FLUSH
    And player-2 has a STRAIGHT_FLUSH
    And player-1 wins

  @EU-0030
  @wip
  Scenario: Full house beats flush
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | Ah Ad      | Ac 2d 2h 4h 6h     |
      | player-2 | Kh 7h      | Ac 2d 2h 4h 6h     |
    When hands are evaluated
    Then player-1 has a FULL_HOUSE
    And player-2 has a FLUSH
    And player-1 wins

  @EU-0031
  @wip
  Scenario: High card comparison with kickers
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | Ah Qc      | Kd Jc 9s 4h 2d     |
      | player-2 | Ah Jd      | Kd Jc 9s 4h 2d     |
    When hands are evaluated
    Then player-1 has a HIGH_CARD
    And player-2 has a PAIR
    And player-2 wins

  # ==========================================================================
  # Reveal-Time Hand Evaluation
  # ==========================================================================
  # Rule: Robert's Rules section 1 (Ciaffone v11) - same hierarchy as the
  #       Hand-Evaluation-Logic section above; this section pins reveal-time
  #       integration with the evaluator across every rank category.
  # These scenarios verify that revealing cards correctly evaluates the hand
  # and surfaces the ranking.

  @EU-0032
  Scenario: Reveal detects straight
    Given a hand at showdown with player-1 holding "Th 9c" and community "8d 7s 6h 2c 3d"
    When player-1 reveals their cards
    Then player-1 has a STRAIGHT

  @EU-0033
  Scenario: Reveal detects wheel straight (A-2-3-4-5)
    Given a hand at showdown with player-1 holding "Ah 2c" and community "3d 4s 5h Kc Qd"
    When player-1 reveals their cards
    Then player-1 has a STRAIGHT

  @EU-0034
  Scenario: Reveal detects straight flush
    Given a hand at showdown with player-1 holding "9h 8h" and community "7h 6h 5h 2c 3d"
    When player-1 reveals their cards
    Then player-1 has a STRAIGHT_FLUSH

  @EU-0035
  Scenario: Reveal detects royal flush
    Given a hand at showdown with player-1 holding "As Ks" and community "Qs Js Ts 2c 3d"
    When player-1 reveals their cards
    Then player-1 has a ROYAL_FLUSH

  @EU-0036
  Scenario: Reveal detects four of a kind
    Given a hand at showdown with player-1 holding "Kh Kd" and community "Ks Kc 2h 3d 4s"
    When player-1 reveals their cards
    Then player-1 has a FOUR_OF_A_KIND

  @EU-0037
  Scenario: Reveal detects full house
    Given a hand at showdown with player-1 holding "Ah Ad" and community "Ac 2d 2h 4s 6c"
    When player-1 reveals their cards
    Then player-1 has a FULL_HOUSE

  @EU-0038
  Scenario: Reveal detects flush
    Given a hand at showdown with player-1 holding "Ah 7h" and community "2h 4h 6h Kc Qd"
    When player-1 reveals their cards
    Then player-1 has a FLUSH

  @EU-0039
  Scenario: Reveal detects three of a kind
    Given a hand at showdown with player-1 holding "Jh Jd" and community "Js 2c 4d 6h 8s"
    When player-1 reveals their cards
    Then player-1 has a THREE_OF_A_KIND

  @EU-0040
  Scenario: Reveal detects two pair
    Given a hand at showdown with player-1 holding "Th Td" and community "5s 5c 2h 3d Ks"
    When player-1 reveals their cards
    Then player-1 has a TWO_PAIR

  @EU-0041
  Scenario: Reveal detects pair
    Given a hand at showdown with player-1 holding "Ah Ac" and community "Kd Js 9h 4c 2d"
    When player-1 reveals their cards
    Then player-1 has a PAIR

  @EU-0042
  Scenario: Reveal detects high card
    Given a hand at showdown with player-1 holding "Ah Qc" and community "Kd Js 9h 4c 2d"
    When player-1 reveals their cards
    Then player-1 has a HIGH_CARD

  # ==========================================================================
  # Error Paths - Betting Validation
  # ==========================================================================
  # Rule: TDA Rule 43 (2024) - minimum raise = largest prior bet/raise on
  #       the current street.
  # The hand enforces strict betting rules. Invalid actions are rejected
  # with clear reasons rather than auto-corrected.

  @EU-0043
  Scenario: Cannot raise less than minimum raise amount
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And player-1 has called for 5
    When player-2 attempts to raise to 15
    Then the raise is refused because it is below the minimum raise

  # ==========================================================================
  # Split Pot and Kicker Resolution
  # ==========================================================================
  # Rule: TDA Rule 21 (2024) - "Each side pot will be split separately."
  # Rule: Robert's section 31 (Ciaffone v11) - kicker tiebreak by highest
  #       remaining card.
  # Multiple players can share a pot when hands are identical, or a kicker
  # can determine the winner when hand rankings match.

  @EU-0044
  @wip
  Scenario: Split pot when hands are identical
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | As Kd      | Ah Kh 2c 5d 9s     |
      | player-2 | Ac Ks      | Ah Kh 2c 5d 9s     |
    When hands are evaluated
    Then player-1 has a TWO_PAIR
    And player-2 has a TWO_PAIR

  @EU-0045
  @wip
  Scenario: Kicker determines winner with matching pairs
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | As Kd      | Ah 2c 5d 9s 3h     |
      | player-2 | Ac Qd      | Ah 2c 5d 9s 3h     |
    When hands are evaluated
    Then player-1 has a PAIR
    And player-2 has a PAIR
    And player-1 wins

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # (Framework: state is reconstructed by replaying history. Not a poker
  # rule - verifies that the codified rules above produce a consistent
  # rebuilt state.)
  # Hand state includes phase, community cards, player stacks, and who has
  # folded. These scenarios verify correct state rebuilding.

  @EU-0046
  Scenario: State after dealing
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    Then the hand is in the PREFLOP phase
    And the hand is in the betting state
    And the hand has 2 players

  @EU-0047
  @wip
  Scenario: State with community cards
    Given a Texas Hold'em hand has been dealt to 2 players
    And the flop has been dealt
    Then there are 3 community cards in play
    And the hand is in the FLOP phase

  @EU-0048
  Scenario: State tracks folded players
    Given a Texas Hold'em hand has been dealt to 3 players
    And blinds have been posted bringing the pot to 15
    And player-1 has folded
    Then player-1 is folded
    And 2 active players remain

  # ==========================================================================
  # Deal - Additional Edge Cases
  # ==========================================================================
  # (Framework: deal-validation edge cases - empty player list,
  # deterministic seed reproducibility. The "minimum 2 players" check
  # codifies the universal poker requirement that a hand needs at least
  # two participants - Rule: WSOP IX Flop Games (2025) "Played with 2-10
  # Participants".)
  # Validation failures around dealing: empty player list, minimum players,
  # and deterministic reproducibility.

  @EU-0049
  Scenario: Cannot deal with empty player list
    Given the hand has not yet been dealt
    When a Texas Hold'em hand is dealt with no players
    Then the deal is refused because no players were provided

  @EU-0050
  @wip
  Scenario: Deterministic deal produces identical hole cards for the same seed
    Given the hand has not yet been dealt
    When the same Texas Hold'em hand is dealt twice with seed "seed123"
    Then both deals produce identical hole cards

  # ==========================================================================
  # Blind Posting - Edge Cases
  # ==========================================================================
  # (Framework: pre-condition gates around blind posting. Some scenarios
  # do double duty: "cannot post blind by folded player" enforces the
  # rule that folded hands cannot resume action - see TDA Rule 30.)
  # Rule: TDA Rule 30 (2024) - folded / absent players cannot act.

  @EU-0051
  Scenario: Cannot post blind before hand is dealt
    Given the hand has not yet been dealt
    When player-1 attempts to post the small blind of 5
    Then the blind is refused because the hand has not been dealt

  @EU-0052
  Scenario: Cannot post blind without identifying the player
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When someone attempts to post the small blind of 5 without identifying the player
    Then the blind is refused because a player must be identified

  @EU-0053
  Scenario: Cannot post blind for player not in hand
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When ghost attempts to post the small blind of 5
    Then the blind is refused because ghost is not in the hand

  @EU-0054
  Scenario: Cannot post blind with zero or negative amount
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When player-1 attempts to post a small blind of 0
    Then the blind is refused because the amount must be positive

  @EU-0055
  Scenario: Cannot post blind after hand complete
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And the hand is complete
    When player-1 attempts to post the small blind of 5
    Then the blind is refused because the hand is complete

  @EU-0056
  Scenario: Cannot post blind by folded player
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And player-1 has folded
    When player-1 attempts to post the small blind of 5
    Then the blind is refused because player-1 has folded

  # ==========================================================================
  # Player Action - Edge Cases
  # ==========================================================================
  # Rule: TDA Rule 30 (2024) - folded players cannot act.
  # Rule: TDA Rule 16 (2024) - all-in player has no further action.
  # Rule: TDA Rule 43 (2024) - minimum raise increment.
  # Rule: TDA Rule 55 (2024) - invalid bet declarations.
  # Pre-action validation: hand must exist, player must exist, cannot act
  # while folded or all-in. Action-specific validations follow.

  @EU-0057
  Scenario: Cannot act before hand is dealt
    Given the hand has not yet been dealt
    When player-1 attempts to fold
    Then the fold is refused because the hand has not been dealt

  @EU-0058
  Scenario: Cannot act without identifying the player
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When someone attempts to fold without identifying the player
    Then the fold is refused because a player must be identified

  @EU-0059
  Scenario: Cannot act for player not in hand
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When ghost attempts to fold
    Then the fold is refused because ghost is not in the hand

  @EU-0060
  Scenario: Folded player cannot act again
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And player-1 has folded
    When player-1 attempts to check
    Then the check is refused because player-1 has folded

  @EU-0061
  Scenario: Cannot take actions outside betting phase
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And the hand has reached showdown
    When player-1 attempts to fold
    Then the fold is refused because the hand is not in a betting phase

  @EU-0062
  Scenario: Cannot call when there is nothing to call
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And player-1 has called for 5
    When player-2 attempts to call
    Then the call is refused because there is nothing to call

  @EU-0063
  Scenario: Cannot bet when there is already a bet
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 attempts to bet 20
    Then the bet is refused because there is already a bet to be matched

  @EU-0064
  Scenario: Cannot bet more than stack
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When player-1 attempts to bet 5000
    Then the bet is refused because it exceeds player-1's stack

  @EU-0065
  Scenario: Cannot raise when there is no bet
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When player-1 attempts to raise to 20
    Then the raise is refused because there is no bet to raise

  @EU-0066
  Scenario: Cannot raise more than stack
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 attempts to raise to 5000
    Then the raise is refused because it exceeds player-1's stack

  @EU-0067
  Scenario: Raise below minimum increment rejected
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 attempts to raise to 12
    Then the raise is refused because it is below the minimum raise

  @EU-0068
  Scenario: Invalid action type rejected
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 attempts to take an unknown kind of action
    Then the action is refused because the action type is not recognised

  @EU-0069
  Scenario: All-in uses the entire remaining stack
    Given a Texas Hold'em hand has been dealt to 2 players with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When player-1 goes all-in
    Then player-1's all-in is recorded
    And player-1's stack is 0

  @EU-0070
  Scenario: Bet for entire remaining stack becomes all-in
    # The short-stacked-blinds step posts a small blind of 5 from the initial
    # stack of 100, leaving player-1 with 95 going into the flop. A bet of 95
    # equals the remaining stack, so the action is reclassified as all-in.
    Given a Texas Hold'em hand has been dealt to 2 players with 100-chip stacks
    And short-stacked blinds have been posted with small 5, big 10, and 100-chip stacks
    And the preflop betting round is complete
    And the flop has been dealt
    When player-1 bets 95
    Then player-1's action is recorded as all-in for 95
    And player-1's stack is 0

  @EU-0071
  Scenario: Raise for entire remaining stack becomes all-in
    Given a Texas Hold'em hand has been dealt to 2 players with 100-chip stacks
    And short-stacked blinds have been posted with small 5, big 10, and 100-chip stacks
    When player-1 raises to 100
    Then player-1's action is recorded as all-in

  @EU-0072
  Scenario: All-in player cannot act again
    Given a Texas Hold'em hand has been dealt to 2 players with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And player-1 has gone all-in for 995
    When player-1 attempts to check
    Then the check is refused because player-1 is already all-in

  # ==========================================================================
  # Community Card Dealing - Edge Cases
  # ==========================================================================
  # (Framework: pre-condition gates around community-card dealing. The
  # "wrong count for phase transition" check enforces the variant
  # structure codified in WSOP IX Texas Hold'em / Omaha - flop=3,
  # turn=1, river=1.)
  # Rule: WSOP IX Texas Hold'em (2025) - fixed flop/turn/river card counts.

  @EU-0073
  Scenario: Cannot deal community cards before the hand
    Given the hand has not yet been dealt
    When the dealer attempts to deal 3 community cards
    Then the deal is refused because the hand has not been dealt

  @EU-0074
  Scenario: Cannot deal zero community cards
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When the dealer attempts to deal 0 community cards
    Then the deal is refused because at least one card must be dealt

  @EU-0075
  Scenario: Wrong count for phase transition is rejected
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When the dealer attempts to deal 1 community card
    Then the deal is refused because the flop expects 3 cards

  @EU-0076
  Scenario: Cannot deal community cards after hand complete
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And the hand is complete
    When the dealer attempts to deal 3 community cards
    Then the deal is refused because the hand is complete

  # ==========================================================================
  # Reveal - Edge Cases
  # ==========================================================================
  # Rule: TDA Rule 13A (2024) - reveal must table all required hole cards.
  # Rule: TDA Rule 30 (2024) - folded players cannot reveal.
  # (Framework: pre-condition gates around showdown reveal.)

  @EU-0077
  Scenario: Cannot reveal before hand is dealt
    Given the hand has not yet been dealt
    When player-1 attempts to reveal their cards
    Then the reveal is refused because the hand has not been dealt

  @EU-0078
  Scenario: Cannot reveal outside of showdown
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When player-1 attempts to reveal their cards
    Then the reveal is refused because the hand is not at showdown

  @EU-0079
  Scenario: Cannot reveal without identifying the player
    Given a Texas Hold'em hand has reached showdown with 2 players
    When someone attempts to reveal cards without identifying the player
    Then the reveal is refused because a player must be identified

  @EU-0080
  Scenario: Cannot reveal for player not in hand
    Given a Texas Hold'em hand has reached showdown with 2 players
    When ghost attempts to reveal their cards
    Then the reveal is refused because ghost is not in the hand

  @EU-0081
  Scenario: Folded player cannot reveal cards
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And player-1 has folded
    And the hand has reached showdown
    When player-1 attempts to reveal their cards
    Then the reveal is refused because player-1 has folded

  # ==========================================================================
  # Pot Award - Edge Cases
  # ==========================================================================
  # Rule: TDA Rule 12 (2024) - cards speak: only eligible (un-folded)
  #       hands can be awarded the pot.
  # Rule: TDA Rule 21 (2024) - pots are split per pot, not blended; the
  #       award sum cannot exceed the pot total.
  # (Framework: ledger-conservation guards. Awarding more than the pot
  # would corrupt the chip ledger; awarding less is auto-corrected to
  # the actual pot.)

  @EU-0082
  Scenario: Cannot award pot before hand is dealt
    Given the hand has not yet been dealt
    When the pot of 100 is awarded to player-1
    Then the award is refused because the hand has not been dealt

  @EU-0083
  Scenario: Cannot award with empty awards list
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When the pot is awarded with no winners specified
    Then the award is refused because at least one winner is required

  @EU-0084
  Scenario: Cannot award to player not in hand
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When the pot of 15 is awarded to ghost
    Then the award is refused because ghost is not in the hand

  @EU-0085
  Scenario: Cannot award to folded player
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And player-1 has folded
    When the pot of 15 is awarded to player-1
    Then the award is refused because player-1 is folded

  @EU-0086
  Scenario: Cannot award pot after hand complete
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And the hand is complete
    When the pot of 15 is awarded to player-1
    Then the award is refused because the hand is already complete

  @EU-0087
  Scenario: Award adjusts mismatched total to the actual pot
    # When the sum of awards doesn't match the pot, the first winner's
    # amount is adjusted so the total matches the pot.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When 10 of the pot is awarded to player-1
    Then player-1 wins 15

  @EU-1009
  Scenario: A pot splits evenly between two winners with identical hands
    # Identical-hand split: pot 100, two winners each take 50. EU-0044
    # confirms the rankings are equal but never asserts the pot is actually
    # divided. Without this scenario, an evaluator that picks a single
    # winner by enumeration order on ties would silently overpay one player
    # and stiff the other - the rank labels would still match.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 100
    When the pot is awarded as:
      | player   | amount |
      | player-1 | 50     |
      | player-2 | 50     |
    Then there are 2 winners
    And player-1 wins 50
    And player-2 wins 50

  @EU-1008
  Scenario: Pot award is rejected when the awards exceed the pot
    # The under-award case (EU-0087) is silently corrected, but the over-award
    # case must reject - paying out chips that don't exist would corrupt the
    # ledger.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When 50 of the pot is awarded to player-1
    Then the award is refused because awards exceed the pot
    And the rejection records the awarded amount 50 against the pot bound 15

  # ==========================================================================
  # Per-Round State Reset After Betting Round
  # ==========================================================================
  # Rule: TDA Rule 47A (2024) - at the start of each new street, the
  #       minimum bet/raise resets per the BB amount; current_bet resets
  #       to 0. (See raise_tracking.feature for the arithmetic.)
  # Completing a betting round resets per-round betting state (current bet,
  # per-player contribution this round, has-acted flags) and can carry stack
  # snapshots. For Five Card Draw, completing preflop advances the phase to
  # the draw phase.

  @EU-0088
  Scenario: Completing a betting round resets per-round betting state
    Given a Texas Hold'em hand has been dealt to 2 players with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And the preflop betting round is complete
    Then the current bet is 0
    And each player's contribution this round is 0

  @EU-0089
  Scenario: Completing a betting round updates player stack snapshots
    Given a Texas Hold'em hand has been dealt to 2 players with 1000-chip stacks
    And the preflop betting round is complete with stack snapshots:
      | player   | stack | all_in | folded |
      | player-1 | 800   | false  | false  |
      | player-2 | 0     | true   | false  |
    Then player-1's stack is 800
    And player-2's stack is 0
    And player-2 is all-in

  @EU-0090
  Scenario: Five Card Draw advances preflop to draw phase
    Given a Five Card Draw hand has been dealt to 2 players
    And the preflop betting round is complete
    Then the hand is in the DRAW phase

  @EU-0091
  Scenario: Five Card Draw does not re-enter draw phase on draw completion
    Given a Five Card Draw hand has been dealt to 2 players
    And the preflop betting round is complete
    And the draw betting round is complete
    Then the hand is in the DRAW phase

  @EU-0092
  Scenario: Texas Hold'em does not advance to a draw phase on preflop complete
    Given a Texas Hold'em hand has been dealt to 2 players
    And the preflop betting round is complete
    Then the hand is in the PREFLOP phase

  # ==========================================================================
  # State Accessors and Replay
  # ==========================================================================
  # (Framework: replay correctness. These pin the projection of individual
  # hand activity into hand state - stack updates from pot awards, status
  # transitions on hand completion, etc. Not poker rules, but the substrate
  # that makes the codified rules survive replay.)

  @EU-0093
  Scenario: Hand identity is derived from the table and hand number
    Given a hand at table "aabbccdd" with hand number 5
    Then the hand carries that table and hand-number identity

  @EU-0094
  Scenario: Awarding a pot increases the winner's stack
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And player-1 has been awarded 100
    Then player-1's stack is 600

  @EU-0095
  Scenario: Completing a hand transitions it to the complete state
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And the hand is complete
    Then the hand is in the complete state

  @EU-0096
  Scenario: The hand records every action that has taken place
    Given a Texas Hold'em hand has been dealt to 2 players with 1000-chip stacks
    And player-1 has posted a blind of 5
    And player-2 has posted a blind of 10
    Then the hand history reflects the deal and both blind postings

  @EU-0097
  Scenario: Posted blinds are reflected in the hand state
    Given a Texas Hold'em hand has been dealt to 2 players with 1000-chip stacks
    And player-1 has posted a blind of 5
    And player-2 has posted a blind of 10
    Then the small blind is 5
    And the big blind is 10
    And the minimum raise is 10

  @EU-0098
  Scenario: Active-player count excludes folded and all-in players
    Given a Texas Hold'em hand has been dealt to 3 players
    And blinds have been posted bringing the pot to 15
    And player-3 has folded
    Then 2 active players remain

  @EU-0099
  Scenario: Cannot award to winner whose identity is unknown
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When the pot of 15 is awarded to unknown-player
    Then the award is refused because unknown-player is not in the hand

  # ==========================================================================
  # Draw Request - Duplicate Indices
  # ==========================================================================
  # (Framework: input-validation guard. WSOP IX Draw Games specifies a
  # player may not change discards once placed; duplicating an index in
  # the discard list is malformed input and rejected.)
  # Rule: WSOP IX Draw Games (2025) - discard list is well-formed.

  @EU-0568
  Scenario: A draw request is rejected when card positions are duplicated
    Given a Five Card Draw hand has been dealt to 2 players
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When player-1 attempts to discard cards at positions 0, 0, and 1
    Then the draw is refused because the discard positions are duplicated

  # ==========================================================================
  # Side Pots - Layered Awards When Stacks Differ
  # ==========================================================================
  # Rule: TDA Rule 21 (2024) - "Each side pot will be split separately."
  # Rule: Robert's section 38 (Ciaffone v11) - side-pot construction.
  # When a player goes all-in for less than the current bet, a side pot is
  # created from the additional chips contributed by the players with
  # deeper stacks. The all-in player is eligible only for the main pot;
  # the side pot is contested only among the remaining bettors. Each pot
  # carries a pot type ("main", "side_1", "side_2", ...) and a set of
  # eligible players.

  @EU-1100
  @wip
  Scenario: Three-way all-in at different stacks creates a main pot and one side pot
    # A=100, B=200, C=500. A all-in for 100. B all-in for 200. C calls 200.
    # Main pot = 100 * 3 = 300, eligible {A,B,C}.
    # Side pot = (200 - 100) * 2 = 200, eligible {B,C} only.
    # C's uncontested chips (300) return to C - not part of any pot.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And player-A has gone all-in for 100
    And player-B has gone all-in for 200
    And player-C has called for 200
    When the side pots are computed
    Then there are 2 pots
    And the main pot holds 300 and is contestable by player-A, player-B, and player-C
    And side pot 1 holds 200 and is contestable by player-B and player-C

  @EU-1101
  Scenario: Side pot is contested only by players who could match the higher all-in
    # Same setup as EU-1100. If player-A wins the showdown, A takes only the
    # main pot (300); the side pot (200) is awarded to whichever of B/C has
    # the better hand among them, since A was not eligible for it.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And all three players are all-in with totals 100, 200, and 200
    And the side pots are computed as:
      | pot    | amount | eligible                            |
      | main   | 300    | player-A, player-B, player-C        |
      | side_1 | 200    | player-B, player-C                  |
    When the pots are awarded as:
      | player   | amount | pot    |
      | player-A | 300    | main   |
      | player-C | 200    | side_1 |
    Then there are 2 winners
    And player-A wins 300 from the main pot
    And player-C wins 200 from side pot 1

  @EU-1102
  Scenario: Award is rejected when the winner is not eligible for the pot
    # Player-A is all-in for the main pot only; awarding player-A any chips
    # from "side_1" must be rejected - A could not have matched those chips.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And the side pots are computed as:
      | pot    | amount | eligible                            |
      | main   | 300    | player-A, player-B, player-C        |
      | side_1 | 200    | player-B, player-C                  |
    When the pots are awarded as:
      | player   | amount | pot    |
      | player-A | 200    | side_1 |
    Then the award is refused because player-A is not eligible for side pot 1

  @EU-1103
  @wip
  Scenario: Four-way all-in produces a main pot and two distinct side pots
    # A=50, B=150, C=300, D=300. All four all-in.
    # Main pot   = 50  * 4 = 200, eligible {A,B,C,D}
    # Side pot 1 = 100 * 3 = 300, eligible {B,C,D}
    # Side pot 2 = 150 * 2 = 300, eligible {C,D}
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 50    |
      | player-B | 1        | 150   |
      | player-C | 2        | 300   |
      | player-D | 3        | 300   |
    And blinds have been posted bringing the pot to 15
    And all four players are all-in with totals 50, 150, 300, and 300
    When the side pots are computed
    Then there are 3 pots
    And the main pot holds 200 and is contestable by player-A, player-B, player-C, and player-D
    And side pot 1 holds 300 and is contestable by player-B, player-C, and player-D
    And side pot 2 holds 300 and is contestable by player-C and player-D

  @EU-1104
  @wip
  Scenario: A folded player's contributions stay in the pot they were already part of
    # Folding does not refund chips. If a player put in 80 and then folded
    # before an opponent went all-in for 100, that 80 still counts toward
    # the main pot. The main pot is sized to the smallest still-contesting
    # all-in (100), not to the folded player's contribution (80).
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And player-B invested 80 then folded
    And player-A is all-in for 100
    And player-C called 100
    When the side pots are computed
    Then there is 1 pot
    And the main pot holds 280 and is contestable by player-A and player-C

  @EU-1105
  @wip
  Scenario: An uncontested over-bet by the deepest stack is returned, not pooled
    # If C bets 500 but the next-deepest stack is 200 (B all-in), the
    # uncontested 300 of C's bet is NOT placed into any pot - it returns to
    # C's stack. Only chips that at least two players can match form a pot.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And player-A is all-in for 100, player-B is all-in for 200, and player-C bets 500
    When the side pots are computed
    Then 300 uncontested chips are returned to player-C
    And the total of all pots is 500

  @EU-1106
  Scenario: Pot awards are routed to the correct pot
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And the side pots are computed as:
      | pot    | amount |
      | main   | 300    |
      | side_1 | 200    |
    When the pots are awarded as:
      | player   | amount | pot    |
      | player-A | 300    | main   |
      | player-B | 200    | side_1 |
    Then player-A's winnings come from the main pot
    And player-B's winnings come from side pot 1

  @EU-1107
  Scenario: Completing a multi-pot award lists every winner across pots
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And the side pots are computed as:
      | pot    | amount |
      | main   | 300    |
      | side_1 | 200    |
    When the pots are awarded as:
      | player   | amount | pot    |
      | player-A | 300    | main   |
      | player-C | 200    | side_1 |
    Then the hand is complete
    And the completion lists 2 winners
    And the completion shows player-A winning the main pot
    And the completion shows player-C winning side pot 1

  @EU-1108
  Scenario: Split within a side pot when two eligible players tie
    # B and C are eligible for side_1. Both have identical hands. The pot
    # (200) splits 100/100. A is ineligible and receives nothing from side_1.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
      | player-C | 2        | 500   |
    And blinds have been posted bringing the pot to 15
    And the side pots are computed as:
      | pot    | amount |
      | main   | 300    |
      | side_1 | 200    |
    When the pots are awarded as:
      | player   | amount | pot    |
      | player-A | 300    | main   |
      | player-B | 100    | side_1 |
      | player-C | 100    | side_1 |
    Then there are 3 winners

  @EU-1109
  @wip
  Scenario: All-in for less than min-raise does not create a side pot when only one other caller remains
    # When only one player has chips left to bet after a short all-in, no
    # side pot can form (a pot needs at least two contestable bettors).
    # Main pot just absorbs both contributions.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 30    |
      | player-B | 1        | 500   |
    And blinds have been posted bringing the pot to 15
    And player-A is all-in for 30 and player-B called 30
    When the side pots are computed
    Then there is 1 pot
    And the main pot holds 60 and is contestable by player-A and player-B

  # ==========================================================================
  # Antes - Forced Per-Player Bets Before Blinds
  # ==========================================================================
  # Rule: TDA RP-11 (2024) - "If a single-player ante is used, the big
  #       blind ante format (BBA) with big-blind-first calculation is
  #       recommended. Antes should not be reduced (including at the final
  #       table) as play progresses in the event."
  # Rule: WSOP IX Texas Hold'em (2025) - ante / blind+ante structures.
  # Tournaments commonly require every player to post an ante in addition
  # to the blinds. Modern WSOP / TDA structures more often use the "BB
  # ante" - a single ante posted by the BB equal to the BB amount. Either
  # form must contribute to the pot before the deal-deciding action begins.

  @EU-1110
  Scenario: Each player posts an ante before the small blind
    # Per-player ante. Three players each post ante 2 (total 6) before SB/BB
    # are posted. Pot after antes = 6, after SB+BB = 21.
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-1 | 0        | 500   |
      | player-2 | 1        | 500   |
      | player-3 | 2        | 500   |
    When player-1 posts an ante of 2
    And player-2 posts an ante of 2
    And player-3 posts an ante of 2
    Then 3 antes have been posted
    And the pot is 6
    And player-1's stack is 498
    And player-2's stack is 498
    And player-3's stack is 498

  @EU-1111
  Scenario: Big-blind ante is posted once by the BB seat for the whole table
    # BB ante = the BB amount, posted by the BB seat in addition to the BB.
    # With BB=10 and a BB-ante structure, the BB seat puts 20 in (10 BB +
    # 10 ante), other seats post no ante.
    Given a Texas Hold'em hand has been dealt to 3 players with 500-chip stacks
    When player-2 posts the big-blind ante of 10
    Then the big-blind ante is posted at 10
    And player-2's stack is 490
    And the pot is 10

  @EU-1112
  Scenario: Short-stacked player posts an all-in ante for less than the full ante
    # A short stack with chips below the ante still posts what they have and
    # is marked all-in for the hand. The ante they did post still contributes
    # to the main pot (parallel to short-stacked blinds, EU-0009).
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-1 | 0        | 1     |
      | player-2 | 1        | 500   |
    When player-1 attempts to post an ante of 5
    Then the ante is posted at 1
    And player-1's stack is 0
    And player-1 is all-in

  @EU-1113
  Scenario: Posting an ante does not start the betting round on its own
    # Antes are forced bets but do NOT establish the current bet (only the
    # big blind does). After ante and SB are posted, the current bet is
    # still the SB amount.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    When player-1 posts an ante of 2
    Then the ante is posted
    And the current bet is 0

  @EU-1114
  Scenario: Cannot post an ante after blinds are already posted
    # Procedural ordering: antes are collected before blinds. Posting an
    # ante after the BB is up is rejected.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When player-1 attempts to post an ante of 2
    Then the ante is refused because antes must be posted before the blinds

  @EU-1115
  @wip
  Scenario: Ante contributes to the main pot for side-pot accounting
    # An ante from a player who later folds still belongs to the main pot,
    # exactly like blinds (parallel to EU-1104).
    Given a Texas Hold'em hand has been dealt to:
      | player   | position | stack |
      | player-A | 0        | 100   |
      | player-B | 1        | 200   |
    And player-A posts an ante of 5 then folds before the flop
    And player-B posts an ante of 5
    When the side pots are computed
    Then the main pot includes player-A's ante of 5
    And the main pot includes player-B's ante of 5

  # ==========================================================================
  # Showdown Reveal Order
  # ==========================================================================
  # Rule: TDA Rule 17A (2024) - "The last aggressive player on the final
  #       betting round (final street) must table first. If there was no
  #       final round bet, the player who would act first in a final
  #       betting round must table first (i.e. first seat left of the
  #       button in flop games)."
  # At showdown the player who took the last aggressive action (bet or
  # raise) on the river must show first. If there was no betting on the
  # river, the first un-folded seat clockwise of the dealer button shows
  # first; remaining players follow in clockwise order.

  @EU-1120
  @wip
  Scenario: Last aggressor on the river shows cards first
    # Three-handed: dealer at seat 0 (player-A), SB at 1 (player-B), BB at 2
    # (player-C). On the river, player-B bets, player-C calls, player-A
    # calls. Last aggressor was player-B. Showdown order: B, then C clockwise,
    # then A.
    Given a hand at showdown with:
      | player   | seat | folded |
      | player-A | 0    | false  |
      | player-B | 1    | false  |
      | player-C | 2    | false  |
    And the last aggressive action on the river was by player-B
    When the showdown order is established
    Then the showdown order is player-B, player-C, player-A

  @EU-1121
  @wip
  Scenario: With no river betting, the first seat clockwise of the dealer shows first
    # Dealer at seat 0. Round was checked through. Seat 1 (SB) is the first
    # un-folded clockwise seat from the dealer, so SB shows first; the rest
    # follow clockwise.
    Given a hand at showdown with:
      | player   | seat | folded |
      | player-A | 0    | false  |
      | player-B | 1    | false  |
      | player-C | 2    | false  |
    And there was no aggressive action on the river
    And the dealer button is at seat 0
    When the showdown order is established
    Then the showdown order is player-B, player-C, player-A

  @EU-1122
  @wip
  Scenario: Folded players are excluded from the showdown order
    # player-C folded on the turn. They do not appear in the showdown
    # order even though they were dealt in.
    Given a hand at showdown with:
      | player   | seat | folded |
      | player-A | 0    | false  |
      | player-B | 1    | false  |
      | player-C | 2    | true   |
      | player-D | 3    | false  |
    And the last aggressive action on the river was by player-A
    When the showdown order is established
    Then the showdown order is player-A, player-B, player-D

  @EU-1123
  Scenario: An out-of-order reveal is rejected
    # The hand enforces showdown order: a reveal from a player whose turn
    # has not yet come up must be rejected. (Once the player ahead has
    # shown or mucked, the next player can act.)
    Given a hand at showdown with order player-A, player-B, player-C
    When player-B attempts to reveal their cards
    Then the reveal is refused because it is out of order

  @EU-1124
  Scenario: A muck advances the showdown to the next player in order
    # When the leading player mucks (without showing), the next player in
    # the showdown order becomes the active showdown player. They may show
    # or muck in turn.
    Given a hand at showdown with order player-A, player-B, player-C
    When player-A mucks
    Then player-A's hand is mucked
    And the next player to show is player-B

  # ==========================================================================
  # Action Clock - TDA Rule 29
  # ==========================================================================
  # Real poker (TDA Rule 29): a player called on the clock has 25 seconds plus
  # a 5-second countdown to act. If the timer expires while facing a bet, the
  # hand is dead (auto-fold). If not facing a bet, the hand is checked. The
  # action clock is started explicitly (by the floor, by a player, or by an
  # idle-detection process) targeting the seat currently to act. Time-out
  # records a fold or check as appropriate.

  @EU-1130
  Scenario: Action clock expires while facing a bet - hand auto-folds
    # Rule: TDA Rule 29 (2024) - 25s + 5s clock; "if the player faces a bet
    #       and time expires, the hand is dead".
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When the action clock is started on Alice for 30 seconds
    And Alice's action clock expires
    Then Alice is folded

  @EU-1131
  Scenario: Action clock expires with no bet to call - hand auto-checks
    # Rule: TDA Rule 29 (2024) - "if not facing a bet, the hand is checked".
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When the action clock is started on Alice for 30 seconds
    And Alice's action clock expires
    Then Alice's check is recorded

  @EU-1132
  Scenario: Cannot start an action clock for a seat that is not currently to act
    # Rule: TDA Rule 29 (2024) - "Players must be at their seats to call for
    #       a clock"; the clock applies to the seat currently to act.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And the action is on Carol
    When the action clock is started on Alice for 30 seconds
    Then the clock is refused because the action is not on Alice

  # ==========================================================================
  # 50% Raise Rule - TDA Rule 43A
  # ==========================================================================
  # Real poker (TDA Rule 43A): in no-limit and pot-limit, a silent push amount
  # of 50% or more of the largest prior bet but less than a minimum raise is
  # auto-promoted to a full minimum raise. A silent push amount of less than
  # 50% is treated as a CALL. An *explicitly declared* raise that is below
  # the minimum is corrected per Rule 52A (any time pre-river, before the
  # turn is dealt after the flop, etc.). EU-0067 hard-rejects the silent-
  # under-min-raise case - the implementation must distinguish silent-push
  # from declared-raise and apply the 50%-rule for the silent path.

  @EU-1133
  Scenario: Silent push amount of 50%+ of min raise is auto-promoted to a full minimum raise
    # Rule: TDA Rule 43A (2024) - "A player who raises 50% or more of the
    #       largest prior bet but less than a minimum raise must make a full
    #       minimum raise."
    # current bet 10, last raise increment 10 -> min raise-to 20.
    # Alice silently pushes 16 (11 over her prior SB; 50% of the 10-chip
    # raise increment is met). The handler must auto-promote to raise-to 20.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Alice silently pushes 16
    Then Alice's action is recorded as a raise
    And the next player owes 20 to call

  @EU-1134
  Scenario: Silent push amount of less than 50% of min raise is treated as a CALL
    # Rule: TDA Rule 43A (2024) - "If less than 50% it is a call unless
    #       'raise' is first declared or the player is all-in."
    # current bet 10, min raise-to 20. Alice silently pushes 12 (7 over her
    # prior SB; less than 50% of the 10-chip increment). Per Rule 43A this
    # is a CALL, not a rejection. The call adds 5 on top of her posted SB.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Alice silently pushes 12
    Then Alice's call of 5 is recorded

  @EU-1135
  Scenario: Explicit declared raise below the minimum is corrected to the minimum (Rule 52A)
    # Rule: TDA Rule 52A (2024) - "Opening or raising less than the minimum
    #       legal amount is corrected anywhere on the current street (if on
    #       the river any time before showdown starts)."
    # current bet 10, min raise-to 20. Alice explicitly declares a raise to
    # 15 (an underraise). Per Rule 52A this is corrected to a full min raise.
    # (Differs from EU-0067, which rejects: that scenario captures the
    # silent-amount path before this rule is applied.)
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Alice declares a raise to 15
    Then Alice's action is recorded as a raise
    And the next player owes 20 to call

  # ==========================================================================
  # Multiple Short All-Ins Re-Open the Bet - TDA Rule 47B
  # ==========================================================================
  # Real poker (TDA Rule 47A second sentence): if multiple short all-ins
  # cumulatively reach a full bet or raise, the betting reopens for players
  # who have already acted. The minimum raise is always the last full valid
  # bet or raise of the round. EU-1007 covers the single-short case; these
  # scenarios cover the cumulative case.

  @EU-1140
  @wip
  Scenario: Two cumulative short all-ins that together meet a full raise reopen the bet
    # Rule: TDA Rule 47A (2024), second sentence - "If multiple short all-ins
    #       re-open the betting, the minimum raise is always the last full
    #       valid bet or raise of the round."
    # current bet 100, min raise increment 50 (so min raise-to 150). Two
    # players each go all-in for 130 (each is +30, individually less than
    # the 50 increment). Combined increment is 60 - more than 50, so action
    # reopens for any earlier bettor and the new raise increment becomes 60.
    Given the current bet is 100 and the last raise increment is 50
    When one player goes all-in to 130
    And another player goes all-in to 160
    Then the bet is reopened for prior actors
    And the last raise increment is 60
    And the current bet is 160

  @EU-1141
  @wip
  Scenario: Two cumulative short all-ins that together do not meet a full raise do not reopen
    # Rule: TDA Rule 47A (2024), first sentence - "An all-in wager (or
    #       cumulative multiple short all-ins) totaling less than a full bet
    #       or raise will not reopen betting."
    # current bet 100, min raise increment 50. Two short all-ins of 120 and
    # 130: combined increment is 30 - below the 50 threshold. Action does
    # NOT reopen for prior actors.
    Given the current bet is 100 and the last raise increment is 50
    When one player goes all-in to 120
    And another player goes all-in to 130
    Then the bet is not reopened for prior actors
    And the last raise increment is 50
    And the current bet is 130

  # ==========================================================================
  # Player Absent at Initial Deal - TDA Rule 30
  # ==========================================================================
  # Real poker (TDA Rule 30): "to have a live hand, players must be at their
  # seats when the last card is dealt to all players on the initial deal."
  # Players not present have their cards killed immediately and any posted
  # blinds/antes forfeit to the pot. The aggregate must accept an explicit
  # "absent at deal" marker so the activity is recorded before action begins.

  @EU-1145
  Scenario: Absent player at initial deal - cards killed, posted blinds forfeit to the pot
    # Rule: TDA Rule 30 (2024) - "Players not then at their seats may not
    #       look at their cards which are killed immediately. Their posted
    #       blinds and antes forfeit to the pot."
    # 3 players, Bob is absent at the deal. The deal still records 3 hands
    # (the deal was attempted) but Bob's hand is immediately killed. Bob's
    # already-posted SB (5) stays in the pot and contributes to side-pot
    # accounting parallel to a folded blind.
    Given the hand has not yet been dealt
    When a Texas Hold'em hand is dealt to:
      | player | position | stack | absent |
      | Alice  | 0        | 500   | false  |
      | Bob    | 1        | 500   | true   |
      | Carol  | 2        | 500   | false  |
    And Bob had posted a small blind of 5 before the deal
    Then Bob is folded
    And the pot is 5

  @EU-1146
  Scenario: Absent player's hand is killed even if cards were physically dealt
    # Rule: TDA Rule 30 (2024) - absent-at-deal hands are killed immediately
    #       and may not be resurrected by a returning player.
    # The hand must mark the absent player's hand dead before any action -
    # they cannot peek and act on the dealt cards.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And Alice was absent at the initial deal
    When Alice attempts to check
    Then the check is refused because Alice was absent at the deal

  # ==========================================================================
  # Declared Rebuy Plays Behind - TDA Rule 27
  # ==========================================================================
  # Real poker (TDA Rule 27): "Players may not miss a hand. Players declaring
  # intent to rebuy before a hand are playing chips behind and must make the
  # re-buy." A declared-rebuy is a binding commitment - the player is dealt
  # in, the rebuy chips are treated as posted-behind for the purposes of the
  # current hand's max bet, and the rebuy MUST be paid afterwards.

  @EU-1150
  Scenario: Declared rebuy commits the player and treats the chips as playing behind
    # Rule: TDA Rule 27 (2024) - "Players may not miss a hand. Players
    #       declaring intent to rebuy before a hand are playing chips behind
    #       and must make the re-buy."
    # 2 players. Alice has stack 0 going into the hand. She declares a
    # rebuy of 500 before cards are dealt. The aggregate must:
    #  - deal Alice in (she cannot miss the hand)
    #  - treat the 500 as available for action this hand (chips behind)
    #  - record a rebuy obligation so the rebuy must be paid post-hand
    Given a table called "Main Table" exists
    And Alice declares a rebuy of 500 before the next hand
    When a Texas Hold'em hand is dealt to:
      | player | position | stack |
      | Alice  | 0        | 0     |
      | Bob    | 1        | 500   |
    Then Alice's effective stack is 500
    And a rebuy obligation of 500 is recorded for Alice

  # ==========================================================================
  # Odd-Chip Distribution - TDA Rule 20 / Robert's Rules section 35
  # ==========================================================================
  # Real poker (TDA Rule 20): odd chips are first broken to the smallest
  # denomination in play. In board games (Hold'em / Omaha / Draw) the odd
  # chip goes to the first seat clockwise of the dealer button. In high-low
  # split, the odd chip in the total pot goes to the high side. EU-1009
  # covers an even split; these scenarios pin the *odd* chip rule.

  @EU-1170
  @wip
  Scenario: Odd-chip split awards the extra chip to first seat clockwise of the button
    # Rule: TDA Rule 20A (2024) - "Board games with 2 or more high or low
    #       hands: the odd chip goes to the first seat left of the button."
    # Rule: Robert's Rules section 35-5(a) (Ciaffone v11) - "In a button
    #       game, the first hand clockwise from the button gets the odd
    #       chip."
    # Pot 101, two-way tie. Seat 1 (Alice) is first clockwise of the dealer
    # button at seat 0. Alice gets 51, Bob gets 50.
    Given a Texas Hold'em hand has been dealt to:
      | player | position | stack |
      | Alice  | 1        | 500   |
      | Bob    | 2        | 500   |
    And blinds have been posted bringing the pot to 101
    And the dealer button is at seat 0
    When the pot is split between Alice and Bob
    Then there are 2 winners
    And Alice wins 51
    And Bob wins 50

  @EU-1171
  @wip
  Scenario: Odd-chip H/L split - extra chip in the total pot goes to the high side
    # Rule: TDA Rule 20C (2024) - "H/L split: the odd chip in the total pot
    #       goes to the high side."
    # Rule: Robert's Rules section 35-8 (Ciaffone v11) - "the chip goes to
    #       the high hand."
    # H/L pot 101 in a split-pot variant. High and low are awarded 50.5
    # each before the odd-chip rule; the odd chip goes to the high winner.
    Given a hand at showdown with a split-pot variant, high winner Alice and low winner Bob
    When the pot of 101 is split between high and low
    Then the high side receives 51
    And the low side receives 50

  @EU-1172
  Scenario: Multi-way odd chip in the high portion of an H/L split - high card by suit
    # Rule: Robert's Rules section 35-9 (Ciaffone v11) - "When there is one
    #       odd chip in the high portion of the pot and two or more high
    #       hands split all or half the pot, the odd chip goes to the
    #       player with the high card by suit."
    # When 2+ high hands tie for half a split-pot, the odd chip in the high
    # half goes to the player with the highest card by suit (using all 7
    # cards, not just the 5-card hand).
    Given a hand at showdown with an H/L split and two tied high winners
    And Alice holds the high card by suit "Ah"
    And Bob holds the high card by suit "Kh"
    When the high half of the pot (51) is split
    Then Alice receives 26
    And Bob receives 25

  # ==========================================================================
  # Playing the Board (Hold'em) - TDA Rule 19 / Robert's Rules section 31
  # ==========================================================================
  # Real poker (TDA Rule 19): "to play the board, players must table all hole
  # cards to get part of the pot." A Hold'em player whose best 5-card hand
  # uses zero or one hole cards can still claim a share of the pot but ONLY
  # if both hole cards are tabled at showdown. Mucking either card forfeits
  # the claim. Robert's Rules section Omaha-1 disallows playing the board in
  # Omaha entirely (must use 2 hole cards).

  @EU-1200
  Scenario: Hold'em player tabling both hole cards plays the board successfully
    # Rule: TDA Rule 19 (2024) - "To play the board, players must table all
    #       hole cards to get part of the pot."
    # Rule: Robert's Rules section 31-9 (Ciaffone v11) - must declare
    #       playing the board before discarding cards or forfeit claim to
    #       the pot.
    # Board is a royal flush A-K-Q-J-T spades; Alice holds 2c 3d. She
    # plays the board. Both hole cards must be tabled. Pot is split with
    # any other un-folded player who also tabled.
    Given a hand at showdown with Alice holding "2c 3d" and community "As Ks Qs Js Ts"
    When Alice reveals her cards
    Then Alice has a ROYAL_FLUSH
    And Alice is playing the board

  @EU-1201
  Scenario: Hold'em player who mucks one hole card forfeits playing-the-board
    # Rule: TDA Rule 19 (2024) - must table ALL hole cards; partial muck
    #       forfeits any claim on the pot.
    # Even if the board is a royal, partially mucking forfeits the claim.
    # The remaining live cards cannot be used to claim a share.
    Given a hand at showdown with Alice holding "2c 3d" and community "As Ks Qs Js Ts"
    When Alice attempts to reveal while mucking only the card at position 0
    Then the reveal is refused because she cannot claim to play the board after mucking a hole card

  # ==========================================================================
  # Level Change During a Hand - TDA Rule 23
  # ==========================================================================
  # Real poker (TDA Rule 23): "A new level applies to the next hand. Hands
  # begin on the first riffle, push of the shuffler button, or on the dealer
  # push. If a hand starts at the prior level by mistake, the hand will
  # continue at the prior level after substantial action occurs." For the
  # hand aggregate, "in-hand" is determined by whether the hand has been
  # dealt.

  @EU-1210
  Scenario: Level change announced after the deal - current hand stays at the prior level
    # Rule: TDA Rule 23 (2024) - "A new level applies to the next hand. If a
    #       hand starts at the prior level by mistake, the hand will continue
    #       at the prior level after substantial action occurs."
    # The hand was dealt at level 1 (BB=10). A blind-level advance arrives
    # mid-hand. The hand must continue to use BB=10 for any subsequent
    # action this hand; the new level applies only to the NEXT hand.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks at blind level 1 (SB 5 / BB 10)
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And the blind level advances to level 2 (SB 10 / BB 20) mid-hand
    Then the big blind is 10
    And the minimum raise is 10

  @EU-1211
  @wip
  Scenario: Level change during dealer push - incoming dealer deals one hand at the prior level
    # Rule: TDA Rule 23 (2024) - "If a new level starts during the dealer
    #       push, the incoming dealer will deal one hand at the prior level."
    # Operationally: the prior-level hand has already been dealt. The next
    # hand starts at the new level.
    Given the prior hand at table "Main Table" was dealt at blind level 1
    And the blind level has advanced to level 2
    When a new hand is started at table "Main Table"
    Then the new hand is started at blind level 2

  # ==========================================================================
  # Face-Up for All-Ins / Uncontested Showdown - TDA Rules 16 + 17B
  # ==========================================================================
  # Real poker:
  #  Rule 16 - once a player is all-in and all betting action by all other
  #    players in the hand is complete, ALL hands must be tabled without
  #    delay. No player who is either all-in or has called all betting
  #    action may muck their hand.
  #  Rule 17B - a non all-in showdown is uncontested if all but one player
  #    mucks face down without tabling. The last live hand wins and is not
  #    required to table.

  @EU-1220
  Scenario: Once action is closed with at least one all-in, every remaining hand must be tabled
    # Rule: TDA Rule 16 (2024) - "All hands will be tabled without delay
    #       once a player is all-in and all betting action by all other
    #       players in the hand is complete. No player who is either all-in
    #       or has called all betting action may muck their hand without
    #       tabling. All hands in both the main and side pot(s) must be
    #       tabled and are live."
    # 3 players. Alice all-in for 100; Bob all-in for 200; Carol called 200.
    # All action closed. The showdown requires every remaining player to
    # table - a muck from any of them is rejected.
    Given a hand at showdown with all-in face-up required
    And the showdown order is Alice, Bob, Carol
    When Alice attempts to muck
    Then the muck is refused because the card must be face up

  @EU-1221
  Scenario: Uncontested showdown - last live hand wins without tabling
    # Rule: TDA Rule 17B (2024) - "A non all-in showdown is uncontested if
    #       all but one player mucks face down without tabling. The last
    #       player with live cards wins and is not required to table."
    # 2 players, no river all-in. Alice mucks face down, Bob has live
    # cards. The pot is awarded to Bob without requiring a reveal.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 100
    And the hand has reached showdown
    When Alice mucks
    And the showdown becomes uncontested with Bob remaining
    Then Bob wins 100
    And Bob is not required to reveal his cards

  # ==========================================================================
  # Misdeals, Fouled Decks, Substantial Action, Burns - TDA Rules 35, 36, 38
  # ==========================================================================
  # Real poker:
  #  Rule 35A - misdeal triggers (boxed cards, exposed downcards by dealer
  #    error, dealt to wrong/dead seat, wrong number of cards, etc.)
  #  Rule 35E - fouled deck: 2+ cards of same suit and rank in the deck
  #    means all bets are returned regardless of substantial action.
  #  Rule 36 - Substantial Action (SA): A) any 2 actions in turn at least
  #    one of which puts chips in the pot, OR B) any combination of 3
  #    actions in turn. Posted blinds do not count toward SA.
  #  Rule 38 - burns are one-per-street even if the stub is reshuffled
  #    mid-hand.

  @EU-1230
  Scenario Outline: Misdeal triggers - pre-SA, hand is redealt; post-SA, hand stands
    # Rule: TDA Rule 35A & 35D (2024) - misdeal taxonomy: boxed cards on
    #       initial deal; first card to wrong seat; cards dealt to a seat
    #       not entitled; entitled seat dealt out; wrong card count; non-
    #       standard card; in flop games an exposed downcard. Once
    #       substantial action occurs (Rule 36) a misdeal cannot be
    #       declared and the hand stands.
    Given a hand in progress with substantial action <sa>
    When the dealer reports a misdeal of type "<type>"
    Then the outcome is "<outcome>"

    Examples:
      | type                   | sa    | outcome              |
      | BOXED_CARDS_INITIAL    | false | MISDEAL_REDEAL       |
      | EXPOSED_DOWNCARD       | false | MISDEAL_REDEAL       |
      | DEALT_TO_DEAD_SEAT     | false | MISDEAL_REDEAL       |
      | WRONG_CARD_COUNT       | false | MISDEAL_REDEAL       |
      | EXPOSED_DOWNCARD       | true  | HAND_STANDS          |
      | BOXED_CARDS_INITIAL    | true  | HAND_STANDS          |

  @EU-1231
  @wip
  Scenario: Fouled deck - duplicate (rank, suit) found at any time returns all bets
    # Rule: TDA Rule 35E (2024) - "If 2 or more cards of the same suit and
    #       rank are found, the deck is fouled. If a fouled deck is
    #       discovered, regardless of SA, play will stop and all bets will
    #       be returned."
    # A fouled deck is detected regardless of substantial action. Play
    # stops, every bet on the current hand is refunded.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And substantial action has occurred on the current hand
    When the dealer reports a fouled deck (duplicate "Ah" found)
    Then the deck is declared fouled
    And every player's contribution to the hand is refunded
    And the hand is void

  @EU-1232
  Scenario Outline: Substantial Action threshold - pre-SA misdeals redeal, post-SA stand
    # Rule: TDA Rule 36 (2024) - "Substantial Action is either A) any 2
    #       actions in turn, at least one of which puts chips in the pot
    #       (i.e. any 2 actions except 2 checks or 2 folds) or B) any
    #       combination of 3 actions in turn (check, bet, raise, call,
    #       fold). Posted blinds do not count towards SA."
    # 2 actions where at least one puts chips in the pot, OR 3 actions of
    # any kind (including 3 checks or 3 folds), constitutes SA. Posted
    # blinds do NOT count.
    Given a Texas Hold'em hand has been dealt to 4 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When the players take "<actions>" in turn
    Then substantial action is <sa>

    Examples:
      | actions               | sa    |
      | FOLD,FOLD             | false |
      | CHECK,CHECK           | false |
      | FOLD,FOLD,FOLD        | true  |
      | CALL,FOLD             | true  |
      | RAISE                 | false |
      | RAISE,FOLD            | true  |

  @EU-1233
  @wip
  Scenario: Stub reshuffle mid-hand still burns exactly one card per street
    # Rule: TDA Rule 38 (2024) - "The burn is always one card per street,
    #       never more." Even after a mid-hand reshuffle (Rule 39A premature
    #       flop, RP-4 disordered stub, etc.) the next street burns exactly
    #       one card.
    # If the stub must be reshuffled during a hand (e.g. premature flop per
    # Rule 39A or stub disorder per RP-4), the next street still burns
    # exactly one card. Reshuffling does NOT add an extra burn.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the stub was reshuffled due to a premature flop
    When the dealer deals the flop
    Then 3 community cards are revealed
    And exactly 1 card was burned for this street

  # ==========================================================================
  # Out-of-Turn Action - TDA Rule 53
  # ==========================================================================
  # Real poker (TDA Rule 53A): action out of turn is backed up to the correct
  # player. If action to the OOT player does NOT change before action returns
  # to them, the OOT action is binding. If action changes, the OOT action is
  # not binding and the OOT player has all options. An OOT fold is always
  # binding.

  @EU-1240
  Scenario: OOT call is binding when prior players check or call without changing the action
    # Rule: TDA Rule 53A (2024) - "Any action out of turn (check, call, or
    #       raise) will be backed up to the correct player in order. The OOT
    #       action is subject to penalty and is binding if action to the OOT
    #       player does not change. A check, call or fold by the correct
    #       player does not change action."
    # 3 players, action on Alice. Carol acts out of turn with a call.
    # Alice then checks (no change), Bob checks (no change). When action
    # returns to Carol, the OOT call is binding.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    And the action is on Alice
    When Carol calls out of turn for 0
    And Alice checks
    And Bob checks
    Then Carol's out-of-turn call is binding
    And Carol's check is recorded

  @EU-1241
  Scenario: OOT raise is NOT binding when an earlier player bets or raises
    # Rule: TDA Rule 53A (2024) - "If action changes, the OOT action is not
    #       binding; any bet or raise is returned to the OOT player who has
    #       all options: call, raise, or fold."
    # Action on Alice. Carol OOT pushes a raise to 60. Alice then bets 50
    # - action has changed. The OOT raise is returned to Carol, who may
    # now call, raise, or fold.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    And the action is on Alice
    When Carol raises to 60 out of turn
    And Alice bets 50
    And Bob calls 50
    Then Carol's out-of-turn raise is returned
    And Carol may now call, raise, or fold

  @EU-1242
  Scenario: OOT fold is always binding even if action changes
    # Rule: TDA Rule 53A (2024) - last sentence: "An OOT fold is binding."
    # Action on Alice. Carol OOT folds. Even after Alice bets and the
    # situation changes, Carol's fold stands - Rule 53A specifically makes
    # OOT folds binding.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    And the action is on Alice
    When Carol folds out of turn
    And Alice bets 50
    Then Carol is folded

  # ==========================================================================
  # Underbet / Underraise Correction - TDA Rule 52A
  # ==========================================================================
  # Real poker (TDA Rule 52A): in limit and no-limit, opening or raising less
  # than the minimum legal amount is corrected anywhere on the current street
  # (if on the river any time before showdown starts). Past the street's end
  # the error stands. EU-0067 hard-rejects below-min raises; this scenario
  # captures the corrective alternative when the error is detected mid-street.

  @EU-1250
  @wip
  Scenario: Underraise corrected on the same street before the next street is dealt
    # Rule: TDA Rule 52A (2024) - "In limit and no-limit, opening or raising
    #       less than the minimum legal amount is corrected anywhere on the
    #       current street (if on the river any time before showdown
    #       starts). After the turn the error stands [for flop-street
    #       errors]."
    # NLHE 100/200, postflop opening bet 600 (Alice), Bob raises to 1000
    # (200 underraise - should be at least 1200), Carol and Dave call. The
    # error is noticed before the turn is dealt. Per Rule 52A, every
    # bettor's contribution is corrected to the legal min raise of 1200
    # anywhere before the turn.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, Carol, and Dave with 5000-chip stacks
    And the flop has been dealt at blinds 100/200
    And Alice bets 600
    And Bob raises to 1000
    And Carol calls 1000
    And Dave calls 1000
    When the dealer detects the underraise before the turn is dealt
    Then the underraise is corrected
    And the corrected raise-to amount is 1200
    And every bettor's contribution is increased to match

  # ==========================================================================
  # Killed / Mucked Hands and Refunds - TDA Rules 65A + 15B
  # ==========================================================================
  # Real poker:
  #  Rule 65A - if a hand is killed by mistake or fouled to the point of
  #    being unidentifiable, the player has no redress for called bets, BUT
  #    if the player initiated a bet or raise that hasn't been called, the
  #    uncalled portion is returned to them.
  #  Rule 15B - if a player mucks thinking they've won (forgetting another
  #    player is still in the hand), and the cards are unrecoverable, the
  #    player is out and not entitled to a refund of called bets. If the
  #    player initiated a bet or raise that hasn't been called, the uncalled
  #    amount is returned.

  @EU-1260
  Scenario: Accidentally killed hand - uncalled portion of player's bet is returned
    # Rule: TDA Rule 65A (2024) - "If the dealer kills a hand by mistake or
    #       if a hand is fouled and cannot be identified to 100% certainty,
    #       the player has no redress and is not entitled to a refund of
    #       called bets. If the player initiated a bet or raise and hasn't
    #       been called, the uncalled amount will be returned."
    # Alice bets 100. Before Bob acts, the dealer accidentally mucks
    # Alice's hand. Per Rule 65A, the called portion (none yet) is forfeit
    # but the uncalled 100 is returned to Alice's stack.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    And Alice bets 100
    When the dealer accidentally mucks Alice's hand
    Then Alice's hand is declared killed by the dealer
    And Alice's stack is 400
    And the pot is 15

  @EU-1261
  @wip
  Scenario: Mucked-while-still-claiming - uncalled raise is refunded
    # Rule: TDA Rule 15B (2024) - "If a player bets then discards thinking
    #       they have won (forgetting another player is still in the hand)
    #       ... if cards are mucked and the player initiated a bet or raise
    #       not yet called, the uncalled amount will be returned."
    # Alice raises to 200 on the river. Alice then mucks face down thinking
    # she has won. Bob has not yet called. Per Rule 15B, the uncalled 200
    # raise is returned to Alice's stack but the called portion (any prior
    # bet) is forfeit.
    Given a Texas Hold'em hand has been dealt to 2 players with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the river has been dealt
    And Alice raises to 200
    When Alice mucks face down before Bob has called
    Then Alice is refunded the uncalled 200
    And Alice's stack is restored by the uncalled portion only

  # ==========================================================================
  # Rabbit Hunting Prohibited - TDA Rule 28
  # ==========================================================================
  # Real poker (TDA Rule 28): "Rabbit hunting (revealing cards that would have
  # come if the hand had not ended) is not allowed." Once a hand ends, the
  # remaining stub MUST NOT be revealed via any query or projection.

  @EU-1270
  Scenario: Hand ending early does not reveal the unburned community cards
    # Rule: TDA Rule 28 (2024) - "Rabbit hunting ... is not allowed."
    # Bob folds preflop. The flop, turn, and river are never dealt and
    # never revealed. The completed hand must NOT contain unburned stub
    # cards in any field.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Bob folds
    And the pot is awarded to Alice
    Then the hand is complete
    And no community cards were revealed
    And the hand history does not expose any stub cards

  # ==========================================================================
  # Tabling All Hole Cards - TDA Rule 13A
  # ==========================================================================
  # Real poker (TDA Rule 13A): "Proper tabling is both 1) turning all cards
  # face up on the table and 2) allowing the dealer and players to read the
  # hand clearly. 'All cards' means both hole cards in hold'em, all 4 hole
  # cards in Omaha, all 7 cards in 7-stud, etc." A reveal that omits any
  # required card is rejected.

  @EU-1271
  Scenario: Hold'em reveal must include both hole cards
    # Rule: TDA Rule 13A (2024) - must table both hole cards.
    Given a hand at showdown with Alice holding "Ah Kh" and community "Qh Jh Th 2c 3d"
    When Alice attempts to reveal tabling only the card at position 0
    Then the reveal is refused because the reveal is incomplete

  @EU-1272
  Scenario: A properly tabled winning hand cannot be killed by an erroneous award
    # Rule: TDA Rule 13C (2024) - "Dealers cannot kill a properly tabled
    #       hand that was obviously the winner."
    # Alice tables a royal flush. The hand must reject any award that
    # nominates a different non-tabled or losing hand as the winner - the
    # tabled-and-evaluated winner cannot be silently overridden by operator
    # error.
    Given a hand at showdown with Alice holding "As Ks" and community "Qs Js Ts 2c 3d"
    And Alice has tabled cards with a ROYAL_FLUSH
    And Bob has tabled cards with a PAIR
    When the pot of 100 is awarded to Bob
    Then the award is refused because a tabled winner's hand cannot be killed
    And the rejection identifies Alice as the tabled winner

  # ==========================================================================
  # Misdeal Edge Cases - TDA Rule 35B / 35C
  # ==========================================================================
  # Real poker:
  #  Rule 35B - "Players may be dealt 2 consecutive cards on the button"
  #    (i.e. dealer alternates around once and the button receives both its
  #    cards in succession at the end of the round). NOT a misdeal.
  #  Rule 35C - "In misdeals, the re-deal is an exact re-play: the button
  #    doesn't move, no new players are seated, limits stay the same."

  @EU-1273
  @wip
  Scenario: Two consecutive cards on the button are not a misdeal
    # Rule: TDA Rule 35B (2024) - explicit allowance.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, Carol, and Dave with 500-chip stacks
    And the dealer button is at seat 0 (Alice)
    And the dealer dealt the second card on the button consecutively
    Then the hand is in the PREFLOP phase
    And no misdeal was declared on this hand

  @EU-1274
  @wip
  Scenario: Re-deal preserves the dealer button position and blind levels
    # Rule: TDA Rule 35C (2024) - "the button doesn't move, no new players
    #       are seated, limits stay the same."
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And the dealer button is at seat 0 (Alice)
    And blinds posted at level 1 (SB 5 / BB 10)
    When the dealer declares a misdeal before substantial action
    And the hand is re-dealt
    Then the hand is re-dealt cleanly
    And the dealer button is still at seat 0 (Alice)
    And the hand level is still 1 (SB 5 / BB 10)

  @EU-1275
  Scenario: Button dealt too few cards - replaceable if announced before the button acts
    # Rule: TDA Rule 37 (2024) - "Missing button cards may be replaced even
    #       after substantial action if permitted for the game type. However,
    #       if the button acts on a hand with too few cards (by check or
    #       bet), the button's hand is dead."
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And the dealer button is at seat 0 (Alice)
    And Alice was dealt only 1 hole card
    When Alice announces the missing card before acting
    Then Alice's button card is replaced
    And Alice has 2 hole cards

  # ==========================================================================
  # Irregular Flops - TDA Rule 39
  # ==========================================================================

  @EU-1276
  @wip
  Scenario: 4-card flop - scramble all four, randomly select burn, remaining 3 = flop
    # Rule: TDA Rule 39A (2024) - "If the flop has 4 rather than 3 cards,
    #       exposed or not ... the dealer scrambles the 4 cards face down,
    #       the floor randomly selects 1 as the next burn card and the
    #       other 3 are the flop."
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When the dealer accidentally lays out 4 cards as the flop
    And the floor randomly selects one of the 4 as the burn card
    Then 3 community cards are revealed
    And exactly 1 card was burned for this street

  @EU-1277
  @wip
  Scenario: No-burn 3-card flop pre-action - scramble flop, one becomes burn, complete flop from stub
    # Rule: TDA Rule 39B (2024) - "If there was no burn on a 3-card flop,
    #       exposed or not ... if no action has occurred, the 3 cards are
    #       scrambled face down, one chosen as the burn. The flop will be
    #       the other 2 cards plus the next card off the stub."
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    When the dealer puts out a 3-card flop without burning
    And no action has occurred on the flop
    Then 3 community cards are revealed
    And exactly 1 card was burned for this street
    And exactly 1 of the original 3 flop cards is now the burn

  @EU-1278
  @wip
  Scenario: No-burn 3-card flop after action - flop stands, no extra burn for the turn
    # Rule: TDA Rule 39B (2024) - "If any action (even one check) has
    #       occurred, play proceeds with the initial 3 cards. Only one card
    #       is burned for the turn."
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the dealer put out a 3-card flop without burning
    And Alice checked on the flop
    When the dealer deals the turn
    Then the hand is in the TURN phase
    And exactly 1 card was burned for this street

  # ==========================================================================
  # Premature Cards - TDA RP-5
  # ==========================================================================
  # Real poker (TDA RP-5): board and burn cards sometimes get dealt
  # prematurely (before the previous round's action is finished). The
  # remedy: keep the existing burn card, return the premature card(s) to the
  # stub, reshuffle the entire stub, and re-deal the street WITHOUT another
  # burn.

  @EU-1280
  @wip
  Scenario: Premature flop - burn stays, premature flop returns to stub, reshuffle, re-deal without new burn
    # Rule: TDA RP-5A (2024) - premature flop procedure.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is incomplete
    When the dealer prematurely lays out a flop
    Then a premature flop is detected
    And the original burn card is preserved
    And the 3 premature cards are returned to the stub
    And the stub is reshuffled
    When the preflop betting round completes
    And the dealer deals the flop
    Then 3 community cards are revealed
    And no card was burned for this street

  @EU-1281
  @wip
  Scenario: Premature turn - burn stays, premature card returns, reshuffle, re-deal without new burn
    # Rule: TDA RP-5B (2024) - premature turn procedure.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    And the flop betting round is incomplete
    When the dealer prematurely deals a turn card
    Then a premature turn is detected
    And the original turn burn card is preserved
    And the premature card is returned to the stub
    And the stub is reshuffled
    When the flop betting round completes
    And the dealer deals the turn
    Then no card was burned for this street

  @EU-1282
  @wip
  Scenario: Premature river - burn stays, premature card returns, reshuffle, re-deal without new burn
    # Rule: TDA RP-5C (2024) - premature river procedure.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the turn betting round is incomplete
    When the dealer prematurely deals a river card
    Then a premature river is detected
    And the original river burn card is preserved
    And the premature card is returned to the stub
    And the stub is reshuffled
    When the turn betting round completes
    And the dealer deals the river
    Then no card was burned for this street

  # ==========================================================================
  # Pot-Limit Underbet Correction - TDA Rule 52B
  # ==========================================================================
  # Real poker (TDA Rule 52B): "In pot limit, if a player underbets the pot
  # based on an inaccurate count, if the pot count is too high (an illegal
  # bet), it will be corrected for all players anywhere on the current
  # street; if too low, corrected until substantial action occurs after the
  # bet."

  @EU-1284
  @wip
  Scenario: PL high (illegal) underbet is corrected for all players anywhere on the current street
    # Rule: TDA Rule 52B (2024) - high count = illegal bet, correct any time.
    # PLO 500/1000. Pot=10500. Alice asks for count, dealer says "11500"
    # (high). Alice bets 11500. Bob and Carol both call 11500. Before the
    # next street is dealt the error is noticed; the bet is reduced to
    # 10500 (the actual pot) for all callers.
    Given an Omaha hand has been dealt to Alice, Bob, Carol, and Dave with 100000-chip stacks
    And blinds posted at SB 500 / BB 1000 bringing the pot to 10500
    And the flop has been dealt
    When Alice pot-bets 11500 based on the dealer's illegal-high count
    And Bob calls 11500
    And Carol calls 11500
    And the dealer detects the illegal overbet before the turn is dealt
    Then the bet is corrected because the overbet exceeds the pot-limit cap
    And the corrected bet amount is 10500
    And every caller's contribution is reduced to 10500

  # ==========================================================================
  # Skipped Player Must Defend Right to Act - TDA Rule 53B
  # ==========================================================================
  # Real poker (TDA Rule 53B): "Players skipped by OOT action must defend
  # their right to act. If a skipped player had reasonable time and does
  # not speak up before substantial action OOT occurs after the player, the
  # OOT action is binding."

  @EU-1285
  Scenario: Skipped player who doesn't defend before SA-OOT loses their action
    # Rule: TDA Rule 53B (2024).
    # Action on Bob (seat 4). Alice (seat 5) acts OOT with a call of 600.
    # Carol (seat 6) folds. Two players have acted OOT - that's substantial
    # action. Bob never spoke up. Bob's hand is now subject to the floor's
    # ruling (typically dead or limited to passive action).
    Given a Texas Hold'em hand has been dealt to Alice, Bob, Carol, and Dave with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 600
    And the action is on Bob
    When Carol calls 600 out of turn
    And Dave folds out of turn
    And Bob did not speak up before substantial action
    Then Bob is recorded as having lost his right to act
    And the out-of-turn actions of Carol and Dave are binding

  # ==========================================================================
  # Pot-Limit Pre-Flop Pot Calculation - TDA Rule 54B
  # ==========================================================================
  # Real poker (TDA Rule 54B): "Pre-flop a dead or short all-in blind will
  # not affect pot calculation. All pre-flop pot and re-pot bets will assume
  # full blinds were posted."

  @EU-1286
  Scenario: PLO pre-flop pot calculation assumes full blinds even with a short SB
    # Rule: TDA Rule 54B (2024) - full blinds assumed.
    # PLO 100/200. Alice (SB seat) is short and posts only 100 (full SB).
    # Bob (BB) posts 200. Carol acts first; the legal pot-limit raise-to is
    # computed AS IF the blinds were a full 100 + 200 + 200 (call) + 200
    # (raise the call) = 700. So Carol's max raise-to pre-flop is 700.
    Given an Omaha hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And Alice posted the small blind of 100 from a stack of 100 (short all-in)
    And Bob posted the big blind of 200
    When the pot-limit pre-flop maximum raise-to amount is computed for Carol
    Then the maximum raise-to is 700

  # ==========================================================================
  # "I Bet The Pot" in NL - TDA Rule 54D
  # ==========================================================================
  # Real poker (TDA Rule 54D): "'I bet the pot' is not a valid bet in
  # no-limit but it does bind the player to making a valid bet (at least a
  # minimum bet) and may be subject to penalty. Players facing a bet must
  # make a valid raise."

  @EU-1287
  Scenario: "Bet the pot" declaration in no-limit binds the player to at least a minimum bet
    # Rule: TDA Rule 54D (2024).
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When Alice declares "bet the pot" on a no-limit table
    Then Alice's bet is recorded at the big blind (10)

  # ==========================================================================
  # Invalid Bet Declarations - TDA Rule 55
  # ==========================================================================
  # Real poker (TDA Rule 55): "If a player faces no bet and: A) declares
  # 'call', it is a check; B) declares 'raise', the player must make at
  # least a minimum bet. A player declaring 'check' when facing a bet may
  # call or fold, but cannot raise."

  @EU-1288
  @wip
  Scenario Outline: Invalid bet declaration outcomes
    # Rule: TDA Rule 55 (2024) - bind invalid declarations to the legal
    #       in-context action.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the betting situation is "<context>"
    When Alice declares "<declaration>"
    Then the recorded action is "<actual>"

    Examples:
      | context             | declaration | actual           |
      | facing no bet       | call        | CHECK            |
      | facing no bet       | raise       | BET (min)        |
      | facing a bet of 50  | check       | CALL_OR_FOLD     |

  # ==========================================================================
  # Non-Standard Folds - TDA Rule 58
  # ==========================================================================
  # Real poker (TDA Rule 58): "Any time before the end of the final betting
  # round, folding in turn if there's no bet to you (ex: facing a check or
  # first to act post-flop) or folding out of turn are binding folds subject
  # to penalty."

  @EU-1289
  Scenario: Folding in turn with no bet to call is a binding fold
    # Rule: TDA Rule 58 (2024) - folds are binding even with no bet facing.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    And the preflop betting round is complete
    And the flop has been dealt
    When Alice folds with no bet to call
    Then Alice is folded

  # ==========================================================================
  # Incorrect Button Movement - TDA Rule 34A
  # ==========================================================================
  # Real poker (TDA Rule 34A): "If incorrect button movement is discovered
  # before SA occurs, the error will be corrected. However, if SA has
  # occurred, play will continue. ... the button will not be backed-up on
  # the next hand."

  @EU-1290
  @wip
  Scenario: Incorrect button movement after substantial action stands for the rest of the hand
    # Rule: TDA Rule 34A (2024) - SA freezes the error in place.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, Carol, and Dave with 500-chip stacks
    And the dealer button was advanced to seat 2 (Carol) instead of seat 1 (Bob)
    And substantial action has occurred this hand
    When the dealer detects the button error
    Then no button correction is applied
    And the hand continues with the dealer button at seat 2 (Carol)
    And the next hand advances the button to seat 3 (Dave) - not back to seat 2

  # ==========================================================================
  # Limit Betting - TDA Rules 47B + 48
  # ==========================================================================
  # Limit-only rules (Hold'em, Omaha-Hi, etc. when played as a limit
  # variant). Marked @limit so engines that don't support limit can skip.

  @EU-1295 @limit
  @wip
  Scenario: Limit - short all-in of at least 50% of a full bet reopens betting
    # Rule: TDA Rule 47B (2024) - "In limit, at least 50% of a full bet or
    #       raise is required to re-open betting for players who have
    #       already acted."
    # Limit Hold'em 100/200. Alice opens for 200, Bob raises to 400 (200
    # raise increment). Carol goes all-in for 500 - that's a 100 raise
    # increment, which is exactly 50% of the previous 200 raise. Action
    # reopens for Alice and Bob.
    Given a limit Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 1000-chip stacks
    And blinds have been posted bringing the pot to 15
    When Alice bets 200
    And Bob raises to 400
    And Carol goes all-in for 500
    Then the bet is reopened for prior actors

  @EU-1296 @limit
  @wip
  Scenario: Limit - at most 1 bet and 4 raises per round until heads-up
    # Rule: TDA Rule 48 (2024) - "In limit play, there is a limit to raises
    #       even when heads-up until the event is down to 2 players; the
    #       house limit applies." House standard is 1 bet + 4 raises.
    Given a limit Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 10000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 200
    And there has already been 1 bet and 4 raises this round
    When Carol attempts to raise
    Then the raise is refused because the raise cap has been reached
    And the rejection notes the round cap of 4 raises

  # ==========================================================================
  # Stud-Specific Aggregate Rules - TDA Rules 11B, 17A, 20B, 35A, 66, RP-10
  # ==========================================================================
  # Variant definitions live in game_rules.feature (EU-0750..EU-0760). These
  # scenarios cover the hand-level invariants that only apply to stud
  # variants: bring-in mechanics, exposed-card rules, mucking, etc.
  # All variants of stud (Seven Card Stud, Stud Hi/Lo, Razz) share these
  # rules unless noted.

  @EU-1320 @stud
  @wip
  Scenario: HORSE button shifts when game type changes from flop game to stud
    # Rule: TDA Rule 11B (2024) - "In mixed games (ex: HORSE), when the game
    #       shifts from hold'em to stud, after the last hold'em hand the
    #       button moves to the position it would be if the next hand was
    #       hold'em and is frozen there during stud."
    # Rule: WSOP Rule 67b (2025) - same wording for HORSE.
    # 4-handed HORSE table at the end of the Omaha rotation. Button about
    # to advance from seat 0 to seat 1. The shift to Razz freezes the
    # button at seat 1 for the duration of the stud rotation.
    Given a HORSE table with 4 active players Alice, Bob, Carol, and Dave at seats 0, 1, 2, and 3
    And the rotation is on the last hand of Omaha-Hi
    And the dealer button is at seat 0
    When the rotation transitions to Razz
    Then the dealer button is frozen at seat 1
    And the frozen position is recorded for the next flop-game rotation
    When the rotation transitions back to Texas Hold'em after the stud rotation
    Then the dealer button resumes at seat 1

  @EU-1321 @stud
  @wip
  Scenario: 7th-street showdown order - high hand showing tables first
    # Rule: TDA Rule 17A (2024) - "In a non all-in showdown, if cards are
    #       not spontaneously tabled or discarded, the TD may enforce an
    #       order of show. The last aggressive player on the final betting
    #       round (final street) must table first. If there was no final
    #       round bet, the player who would act first in a final betting
    #       round must table first (... high hand showing in stud, low hand
    #       in razz, etc.)."
    # 3-player showdown after a check-around on 7th street. Up cards
    # showing: Alice "Kc 5h 7d 2s", Bob "Th 8c 6d 3s", Carol "Ad Qh Jc 9s".
    # Carol's high hand showing (Ace-high) tables first.
    Given a Seven Card Stud hand at showdown with Alice, Bob, and Carol
    And up cards by player:
      | player | up_cards         |
      | Alice  | Kc 5h 7d 2s      |
      | Bob    | Th 8c 6d 3s      |
      | Carol  | Ad Qh Jc 9s      |
    And there was no aggressive action on 7th street
    When the showdown order is established
    Then the showdown order is Carol, Alice, Bob

  @EU-1322 @stud
  Scenario: Stud odd chip - high card by suit gets the odd chip
    # Rule: TDA Rule 20B (2024) - "Stud, razz, and if 2 or more high or low
    #       hands in stud/8: the odd chip goes to the high card by suit in
    #       the player's 5-card winning hand."
    # Two players tie with full houses Js Js Js 8h 8d. The odd chip goes
    # to the player whose highest card by suit is higher. Suit ranking
    # high to low: spades, hearts, diamonds, clubs.
    Given a Seven Card Stud hand at showdown with Alice's 5-card hand "Js Jh Jd 8h 8d"
    And Bob's 5-card hand "Js Jc Jd 8s 8c"
    # Pot 101, both rank FULL_HOUSE Jacks-over-eights. Tiebreak by highest
    # card by suit.
    When the pot of 101 is split between Alice and Bob
    Then Alice wins 51
    And Bob wins 50

  @EU-1323 @stud
  @wip
  Scenario: Stud - exposed first or second downcard on initial deal is a misdeal
    # Rule: TDA Rule 35A-6 (2024) - "Before SA, a non-standard card for the
    #       game type is found"; specifically: "In flop games, if 1 of the
    #       first 2 cards dealt off the deck or any other 2 downcards are
    #       exposed by dealer error" - extended to stud per the misdeal
    #       taxonomy where "exposed downcards" trigger a redeal pre-SA.
    # Rule: WSOP Rule 88a-6 (2025) - "In stud, if either or both of a
    #       Participant's first 2 down cards are exposed by dealer error."
    Given a Seven Card Stud hand starting with 4 players Alice, Bob, Carol, and Dave
    And no substantial action has occurred
    When the dealer accidentally exposes Alice's first downcard
    Then a misdeal is declared
    And the misdeal reason is the exposed stud downcard
    And the dealer button is preserved
    And no chips have been forfeited

  @EU-1324 @stud
  Scenario: Mucking in stud - proper muck is turning down all up cards and pushing them forward
    # Rule: TDA Rule 66 (2024) - "In stud poker, if a player picks up the
    #       upcards while facing action, the hand is dead. Proper mucking
    #       in stud is turning down all up cards and pushing them all
    #       forward face down."
    Given a Seven Card Stud hand on 5th street with Bob facing a bet
    When Bob attempts to fold by picking up his up cards
    Then the fold is refused because picking up the up cards is not a valid muck in stud

  @EU-1325 @stud
  @wip
  Scenario: RP-10A - downcard exposed on initial deal becomes the player's upcard
    # Rule: TDA RP-10A (2024) - "A downcard exposed on the initial deal
    #       will be the player's upcard and 3rd street will be dealt down
    #       to that player. The player can be the bring-in."
    Given a Seven Card Stud hand starting with 3 players Alice, Bob, and Carol
    And the deal is in progress
    When the dealer exposes Alice's intended second downcard
    Then the exposed downcard becomes Alice's up card
    And Alice has 1 down card and 1 up card after the conversion
    And the next dealt card to Alice (the door card) is dealt face down
    And Alice remains eligible to be the bring-in based on her up card

  @EU-1326 @stud
  @wip
  Scenario: RP-10B - exposed 7th-street card is replaced when betting action remains
    # Rule: TDA RP-10B (2024) - "A card exposed by the dealer on 7th street
    #       will be replaced if betting action remains on the hand. 7th
    #       street should be dealt down even if no betting action remains
    #       on the hand."
    Given a Seven Card Stud hand on 7th street
    And Alice still has betting action remaining
    When the dealer exposes Alice's 7th-street card
    Then Alice's 7th-street card is replaced
    And the original card is removed from play
    And the replacement card is dealt face down to Alice

  @EU-1327 @stud
  Scenario: RP-10C - absent player's cards are killed; no 4th street to non-live hand
    # Rule: TDA RP-10C (2024) - "Cards of a player not at his or her seat
    #       (See Rule 30) for the deal will be killed. No cards will be
    #       dealt to a hand on 4th street that is not live."
    Given a Seven Card Stud hand with Alice, Bob, and Carol
    And Bob was absent for the initial deal
    Then Bob's hand is killed
    When the dealer deals 4th street
    Then 2 cards are dealt on 4th street
    And no card was dealt to Bob

  @EU-1328 @stud
  Scenario: RP-10D - tied stud high-up acts first by suit ranking
    # Rule: TDA RP-10D (2024) - "If there are two or more matching high
    #       hands showing in Stud (or Stud-8) or low hands in Razz, betting
    #       starts on the hand with the high card by suit in both games."
    Given a Seven Card Stud hand on 5th street
    And up cards by player:
      | player | up_cards     |
      | Alice  | As Kh        |
      | Bob    | Ah Kd        |
    When first-to-act on 5th street is determined
    # Both players show Ace-King; Alice's As is higher by suit (spades >
    # hearts). Alice acts first.
    Then the first-to-act player is Alice

  @EU-1329 @stud
  @wip
  Scenario: RP-10E - bring-in player all-in for the ante: betting starts to their left
    # Rule: TDA RP-10E (2024) - "If the player dealt the low card by suit
    #       is all-in for the ante, betting starts to his or her left.
    #       Players with chips must bet at least the bring-in or fold."
    Given a Seven Card Stud hand starting with 3 players Alice, Bob, and Carol
    And Alice was the lowest-card-by-suit but is all-in for the ante
    When the 3rd-street betting begins
    Then the first-to-act player is Bob
    And the minimum bet for Bob and Carol is the bring-in amount

  @EU-1330 @stud
  @wip
  Scenario: RP-10F - open pair on 4th street does NOT enable a doubled bet (TDA standard)
    # Rule: TDA RP-10F (2024) - "Bets will not be doubled on 4th street for
    #       a pair showing." (Note: WSOP-1521/1531 says the OPPOSITE for
    #       seven-card stud at WSOP - they allow either limit. We codify
    #       the TDA default; WSOP-house override is captured in EU-1330b.)
    Given a Seven Card Stud limit hand with small bet 100 and big bet 200
    And Alice has up cards "8h 8d" on 4th street showing an open pair
    When Alice attempts to bet 200 on 4th street
    Then the bet is refused because a doubled bet is not allowed on 4th street
    And the rejection notes the maximum bet of 100

  @EU-1331 @stud
  @wip
  Scenario: RP-10H sub-C - 7th-street short stub (<3 cards) becomes a community card
    # Rule: TDA RP-10H sub-C (2024) - "If the current stub has less than 3
    #       cards, it will be scrambled with the 3 prior burns for a new
    #       stub which will then be cut, a card burned, and the next card
    #       dealt as a community card."
    # Rule: TDA RP-10H sub-D (2024) - "If a community card is in play, the
    #       first player who would act on 6th street will be first to act
    #       on 7th street."
    Given a Seven Card Stud hand on 7th street with 5 active players
    And the stub has 2 cards remaining and the burn pile has 3 prior burns
    When the dealer scrambles the stub with the prior burns
    And one card is burned and the next is dealt as a community card
    Then a stud community card is dealt
    And the community card is shared by all 5 active players
    And the first-to-act on 7th street is the same player who acted first on 6th street

  @EU-1332 @stud
  @wip
  Scenario: RP-10G / RP-5D - premature card in stud returned to stub, reshuffled, no extra burn
    # Rule: TDA RP-10G (2024) - "For premature cards dealt in stud see
    #       RP-5-D."
    # Rule: TDA RP-5D (2024) - "Premature card in stud: the premature card
    #       is returned to the stub, the stub is re-shuffled, and a new
    #       street is dealt from the newly shuffled stub without another
    #       burn."
    Given a Seven Card Stud hand on 4th street with betting in progress
    And the dealer has not yet completed 4th-street betting action
    When the dealer prematurely deals a 5th-street card
    Then a premature stud card is detected
    And the premature card is returned to the stub
    And the stub is reshuffled
    When 4th-street betting completes
    And the dealer deals 5th street
    Then the stud street is dealt
    And no card was burned for this street

  @EU-1333 @stud
  @wip
  Scenario: RP-10H sub-A - short stub: stub + prior burns reaches required count
    # Rule: TDA RP-10H sub-A (2024) - "if the required number can be reached
    #       by adding the 3 prior burn cards (for 4th, 5th, and 6th street)
    #       the current stub will be scrambled with the prior burns to
    #       create a new stub. The new stub will be cut, a card burned, and
    #       one card dealt to each player."
    # 5 active players + 1 burn + 1 undealt-last-card = 7 required cards.
    # Stub has 4 cards; 3 prior burns added = 7 cards total. Sufficient.
    Given a Seven Card Stud hand on 7th street with 5 active players
    And the stub has 4 cards remaining
    And the burn pile has 3 prior burns
    When the dealer scrambles the stub with the prior burns into a new stub
    And one card is burned from the new stub
    Then the stud street is dealt
    And one card is dealt to each of the 5 active players
    And no community card is in play

  @EU-1334 @stud
  @wip
  Scenario: RP-10H sub-B - stub has >=3 but combining with burns is still short -> community card
    # Rule: TDA RP-10H sub-B (2024) - "if there are at least 3 cards in the
    #       current stub but adding the prior burns would not reach the
    #       required number, the dealer will burn the top card of the
    #       current stub and deal the next card as a community card in the
    #       center of the table."
    # 6 active players + 1 burn + 1 undealt-last = 8 required. Stub has 3,
    # burns add 3 more = 6 total. Insufficient. Burn top of stub, next card
    # = community card.
    Given a Seven Card Stud hand on 7th street with 6 active players
    And the stub has 3 cards remaining
    And the burn pile has 3 prior burns
    When the dealer burns the top card of the stub
    And the next card is dealt as a community card
    Then a stud community card is dealt
    And the community card is shared by all 6 active players
    And the first-to-act on 7th street is the same player who acted first on 6th street

  @EU-1335 @stud
  @wip
  Scenario: WSOP - all 3 first cards dealt face down: scramble, randomly turn one face up
    # Rule: WSOP Seven Card Games (2025) - "If a Participant receives each
    #       of the first three cards down, the floor supervisor will
    #       scramble the 3 cards and randomly select one of the cards to
    #       turn over as the Participant's up card."
    Given a Seven Card Stud hand starting with 3 players Alice, Bob, and Carol
    And the dealer accidentally dealt all 3 of Alice's first cards face down
    When the floor scrambles Alice's 3 cards face down
    And the floor randomly selects one card to turn face up as Alice's door card
    Then Alice's door card is selected
    And Alice has 2 down cards and 1 up card

  @EU-1336 @stud
  Scenario: WSOP - wrong bring-in correction window: fix until the next player has acted
    # Rule: WSOP Seven Card Games (2025) - "When the wrong person is
    #       designated as the bring-in and bets, if the next Participant
    #       has not yet acted; the action will be corrected to the correct
    #       bring-in position ... If the next hand has acted after the
    #       incorrect low card action, the wager stands, action continues
    #       from there, and the real low card has no obligations."
    # Rule: Robert's Rules SC Stud #5 - same rule.
    Given a Seven Card Stud hand starting with 3 players Alice, Bob, and Carol
    And Alice was incorrectly designated as the bring-in
    And Alice posted the bring-in
    When Bob (the next to act) has not yet acted
    Then the bring-in is corrected
    And Alice's wager is returned
    And Carol (the actual low card) is now obligated to post the bring-in

  @EU-1337 @stud
  @wip
  Scenario: WSOP - bring-in completion to a full bet does not count as a raise
    # Rule: WSOP Seven Card Games (2025) - "Increasing the amount wagered
    #       by the forced bring-in, up to a full bet does not count as a
    #       raise but merely as a completion of the bet. For example:
    #       Bring-in 100, complete to 400; four raises are then allowed."
    # Rule: Robert's Rules SC Stud #6 - same rule.
    Given a limit Seven Card Stud hand with bring-in 100 and small bet 400
    And Alice posted the bring-in for 100
    When Bob completes the bet to 400
    Then Bob's bet-completion is recorded
    And the bet-completion does not count toward the per-round raise cap
    And up to 4 subsequent raises are allowed

  @EU-1338 @stud
  @wip
  Scenario: WSOP - absent at 3rd-street completion forfeits ante and bring-in
    # Rule: WSOP Seven Card Games (2025) - "If you are not present at the
    #       table when third street has been delivered to the final
    #       Participant position, you forfeit your ante and bring-in, if
    #       any."
    # Rule: Robert's Rules SC Stud #8 - "If you are not present at the
    #       table when it is your turn to act, you forfeit your ante and
    #       your forced bet, if any."
    Given a Seven Card Stud hand starting with 4 players Alice, Bob, Carol, and Dave
    And Bob had posted ante 5 and was the bring-in (10) before the deal
    And Bob is absent when 3rd street is delivered to Dave
    When the deal of 3rd street completes
    Then Bob's hand is killed
    And Bob's ante of 5 is forfeited to the pot
    And Bob's bring-in of 10 is forfeited to the pot
    And the pot is 15

  @EU-1339 @stud
  @wip
  Scenario: WSOP - open pair on 4th street locks lower limit in Stud Hi/Lo and Razz
    # Rule: WSOP Seven Card Stud Hi/Lo 8b (2025) - "On Fourth Street, a
    #       Participant showing an open pair does not have an option of
    #       opening with an upper limit bet."
    # Rule: WSOP Seven Card Razz (2025) - "On Fourth Street, a Participant
    #       showing an open pair does not have an option of opening with
    #       an upper limit bet."
    # Note: Stud Hi (high-only) follows TDA RP-10F (no doubled bet -
    # see EU-1330). Hi/Lo and Razz use the same rule but cite separately.
    Given a limit Seven Card Stud Hi/Lo hand with small bet 100 and big bet 200
    And Alice has up cards "8h 8d" on 4th street showing an open pair
    When Alice attempts to open the betting at the upper limit (200)
    Then the bet is refused because an open pair locks the lower limit

  @EU-1340 @stud
  @wip
  Scenario: Robert's SC Stud #18 - hand with too few or too many cards at showdown is dead
    # Rule: Robert's Rules SC Stud #18 (Ciaffone v11) - "A hand with more
    #       than seven cards is dead. A hand with less than seven cards at
    #       the showdown is dead, except any player missing a seventh card
    #       may have the hand ruled live."
    Given a Seven Card Stud hand at showdown with Alice holding 6 cards
    And the missing card is the 7th street downcard
    When Alice reveals her cards
    Then the outcome depends on floor discretion
    # Default ruling per the rule's exception clause: missing 7th card may
    # be ruled live by the floor. The hand must surface this as a decision
    # rather than silently dead-handing.
    And a floor decision is required because of the missing 7th-street card
    Given a Seven Card Stud hand at showdown with Bob holding 8 cards
    When Bob reveals his cards
    Then the reveal is refused because there are too many cards for stud

  @EU-1341 @stud
  @wip
  Scenario: Robert's RAZZ #3 - open pair on 4th street does not affect the limit (Razz only)
    # Rule: Robert's Rules RAZZ #3 (Ciaffone v11) - "Fixed-limit games use
    #       the lower limit on third and fourth streets and the upper limit
    #       on subsequent streets. An open pair does not affect the limit."
    # In Razz the limit advances by street regardless of any open pair -
    # different from Stud Hi (TDA RP-10F locks to lower limit) and Stud
    # Hi/Lo (locks to lower limit). Razz advances normally.
    Given a limit Razz hand with small bet 100 and big bet 200 on 5th street
    And Alice has up cards "8h 8d 7c" on 5th street showing an open pair on 4th
    When Alice bets at the upper limit (200) on 5th street
    Then Alice's bet of 200 is recorded
    And no rejection is raised based on the open pair

  # ==========================================================================
  # Showdown Disclosure - TDA Rule 18
  # ==========================================================================
  # Real poker (TDA Rule 18): "A: Players not still in possession of cards at
  # showdown, or who have mucked their cards face down without tabling, lose
  # any rights or privileges to ask to see any hand. B: If there was a river
  # bet, any caller has an inalienable right to have the last aggressor's
  # hand tabled on request ('the hand they paid to see') provided the
  # caller tabled or retains his or her cards."

  @EU-1342
  Scenario: River caller can demand last aggressor's hand at showdown
    # Rule: TDA Rule 18B (2024) - caller's "inalienable right" to see the
    #       hand they paid for, provided they retained their cards.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And the river betting closed with Bob as last aggressor and Alice as caller
    And Alice still holds her cards
    When Alice requests to see Bob's hand
    Then Bob is required to table his hand

  @EU-1343
  Scenario: Mucked-without-tabling player loses right to demand a hand
    # Rule: TDA Rule 18A (2024) - players who mucked face-down at showdown
    #       have no right to ask to see any hand.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And the river betting closed with Bob as last aggressor and Alice as caller
    And Alice mucked her cards face-down without tabling
    When Alice requests to see Bob's hand
    Then the request is refused because the hand was mucked without being tabled

  # ==========================================================================
  # Disputed Pots Window - TDA Rule 22
  # ==========================================================================
  # Real poker (TDA Rule 22): "The right to dispute a hand ends when a new
  # hand begins. A hand begins with the first riffle of the deck." Once the
  # next hand begins shuffling, the prior hand's pot distribution is final.

  @EU-1344
  Scenario: Pot dispute window closes when the next hand begins shuffling
    # Rule: TDA Rule 22 (2024) - dispute window ends at first riffle.
    # Rule: WSOP Rule 76 (2025) - same wording.
    Given the prior hand has been completed with the pot of 600 awarded to Alice
    And a new hand has been started and the deck has been shuffled
    When Bob disputes the pot distribution of the prior hand
    Then the dispute is refused because the dispute window has closed

  # ==========================================================================
  # Discretionary Color-Up - TDA Rule 25
  # ==========================================================================
  # Real poker (TDA Rule 25): the TD may color-up smaller-denom chips
  # outside the scheduled chip race. The hand-level effect is that a
  # color-up triggers stack reconciliation at the *next* break or hand
  # boundary; in-hand chips are not retroactively converted.

  @EU-1345
  Scenario: Discretionary color-up is deferred to the next hand boundary
    # Rule: TDA Rule 25 (2024) - color-ups happen between hands, never
    #       mid-hand.
    Given a hand in progress with the current bet at 200 and the pot at 1000
    When the TD issues a discretionary color-up for denomination 25
    Then the color-up is accepted but no stack mutation occurs in this hand
    And the color-up is scheduled to apply at the next hand boundary

  # ==========================================================================
  # Verbal vs Chip Betting Mechanics - TDA Rules 40, 42, 51
  # ==========================================================================
  # Real poker (TDA Rules 40-42, 51): an in-turn verbal declaration is
  # binding. Verbal raise without a stated amount commits the player to at
  # least the minimum legal raise. Chips put forward without verbal context
  # are interpreted by Rules 41 (call) and 44/45 (oversized/multi-chip).

  @EU-1346
  Scenario: In-turn verbal "raise" without amount commits to minimum legal raise
    # Rule: TDA Rule 42 (2024) - "Verbal raise without an amount commits
    #       the player to at least the minimum legal raise."
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    And Bob has bet 50 (a 40 raise increment)
    When Carol verbally declares "raise" without an amount
    Then Carol's action is recorded as a raise
    And Carol's raise totals 90 (50 + the 40 minimum raise increment)

  @EU-1347
  Scenario: In-turn verbal "all-in" is binding even before chips move
    # Rule: TDA Rule 40 (2024) - "Acting in turn verbally is binding."
    # Alice posted the small blind of 5 from her 500 stack so she enters
    # the action with a 5-chip contribution this round and a 495 stack.
    # The verbal all-in commits the remaining 495 chips on top of the SB.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Alice verbally declares "all-in" with no chips yet pushed
    Then Alice's all-in is recorded with a 495-chip commit
    And Alice's stack is 0

  # ==========================================================================
  # Chip-Only Betting - TDA Rules 41, 44, 45, 46
  # ==========================================================================
  # Real poker (TDA Rules 41/44/45/46): silent (no verbal) chip pushes are
  # interpreted by deterministic rules. Single oversized chip = call.
  # Multi-chip pushed silently is a call if every chip is needed; otherwise
  # the 50% threshold (Rule 43A) decides whether it's a raise.

  @EU-1348
  Scenario: Multi-chip silent bet is a call when every chip is needed to call
    # Rule: TDA Rule 41 (2024) - "When facing a bet, unless raise is declared
    #       first, a multiple-chip bet is a call if every chip is needed to
    #       make the call."
    # Rule: WSOP Rule 92 (2025) - same wording.
    # Pot 15, current bet 200 (post-flop opening bet by SB). Bob silently
    # puts out two 100 chips. Both are needed to call 200 -> ruled a call.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 200
    When Bob silently pushes chips totaling 200 (two 100 chips, both required)
    Then Bob's call of 200 is recorded

  @EU-1350
  Scenario: Single oversized chip pushed silently is a call
    # Rule: TDA Rule 44 (2024) - "Putting a single oversized chip into the
    #       pot will be considered a call if the player doesn't verbally
    #       declare a raise."
    # Rule: WSOP Rule 97 (2025) - same wording.
    # current bet 200 (post-flop opening). Bob silently drops a single
    # 1000 chip -> call (200). Change of 800 is implicit.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 5000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 200
    When Bob silently pushes a single 1000 chip
    Then Bob's call of 200 is recorded

  @EU-1351
  Scenario: Multi-chip silent bet meeting the 50% threshold is a full minimum raise
    # Rule: TDA Rule 45 (2024) + Rule 43A (50% rule) - "A multi-chip bet
    #       not all-needed-to-call that meets the 50% raise threshold is
    #       promoted to a full minimum raise."
    # current bet 200 (post-flop opening). Bob silently pushes 400.
    # Excess over call = 200, last raise increment = 200, so 200 == full
    # legal raise -> no promotion needed. Bob commits 400 in total.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 5000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 200
    When Bob silently pushes 400 (two 200 chips, not all required)
    Then Bob's raise of 400 is recorded

  @EU-1352
  Scenario: Prior-bet chips topped silently to >=50% threshold becomes a full raise
    # Rule: TDA Rule 46C (2024) - "If new chip(s) are added silently ... the
    #       combined final chip bet is a raise if reaching the 50% standard
    #       (Rules 43 and 45)."
    # Alice prior bet 100; Bob raises to 300 (+200 increment); Alice
    # silently adds 300 more (total 400 on the table). 100 excess over
    # call meets 50% of 200 -> promoted to full minimum raise. Final
    # absolute commit = 500.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 2000-chip stacks
    And blinds have been posted bringing the pot to 15
    And Alice has already bet 100 this street
    And Bob raised to 300 (200 raise increment)
    When Alice silently adds chips totaling 300 on top of her prior 100
    Then Alice's raise of 400 is recorded
    And the next player owes 500 to call

  @EU-1353
  Scenario: Pulling back a prior-bet chip while facing a raise binds the player to call or raise
    # Rule: TDA Rule 46B (2024) - "If facing a raise, clearly pulling back
    #       a prior bet chip binds a player to call or raise; they may not
    #       put the chip(s) back out and fold."
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 2000-chip stacks
    And blinds have been posted bringing the pot to 15
    And Alice has already bet 100 this street
    And Bob raised to 300 (200 raise increment)
    When Alice pulls back her prior 100 chip while facing the raise
    Then Alice is bound to call or raise
    When Alice attempts to fold
    Then the fold is refused because the player must call or raise

  # ==========================================================================
  # Accepted Action / Undercalls - TDA Rules 49, 51
  # ==========================================================================
  # Real poker (TDA Rules 49/51): the caller bears responsibility to know
  # the bet amount; an in-turn undercall is corrected up to the actual bet
  # before substantial action, otherwise stands as accepted action.

  @EU-1354
  @wip
  Scenario: Verbal undercall in turn is corrected up to the actual bet before SA
    # Rule: TDA Rule 51 (2024) - "An in-turn verbal undercall must be
    #       corrected up to the bet amount provided no substantial action
    #       has occurred. After SA, the undercall stands as accepted."
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 100
    When Bob verbally declares "call 60" in turn (an undercall)
    And no substantial action has occurred since
    Then the undercall is corrected up to 100
    And Bob's call of 100 is recorded

  @EU-1355
  @wip
  Scenario: Verbal undercall in turn stands at the lesser amount after substantial action
    # Rule: TDA Rule 51 (2024) - "After SA the undercall stands."
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 100
    And Bob verbally declared "call 60" in turn (an undercall)
    And Carol then raised (substantial action occurred)
    When the dealer notices the undercall after Carol's raise
    Then no correction is applied
    And Bob's commit for the prior action stands at 60
    And Carol's substantial action stands

  # ==========================================================================
  # Non-Standard Betting - TDA Rules 56, 57, 59
  # ==========================================================================
  # Real poker (TDA Rules 56-57, 59): chips moved in multiple motions
  # ("string bet") are dead money returned to the player. Non-standard
  # declarations are at player's risk; conditional/future-action statements
  # are non-binding when the condition fails.

  @EU-1356
  @wip
  Scenario: String bet - chips beyond the first forward motion are returned
    # Rule: TDA Rule 56 (2024) - "Dealers will be responsible for calling
    #       string bets/raises. Chips beyond the first forward motion are
    #       returned and the bet stands at the first-motion amount."
    # Rule: WSOP Rule 103 (2025) - same wording.
    # Alice (SB, prior bet 5) pushes 30 in the first forward motion. To
    # reach 30 she adds 25 on top of her posted SB. The second motion of
    # 70 is returned.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Alice pushes 30 in a first forward motion
    And Alice then reaches back and adds 70 in a second motion
    Then the dealer rules a string bet
    And the second-motion 70 is returned to Alice
    And Alice's raise puts 25 more chips into the pot
    And the next player owes 30 to call

  @EU-1357
  @wip
  Scenario: Non-standard bet declaration is ruled by the floor with player at risk
    # Rule: TDA Rule 57 (2024) - "Players using non-standard or unclear
    #       betting declarations bear the risk of the floor's interpretation."
    # Rule: WSOP Rule 60 (2025) - same.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 1000-chip stacks
    And blinds have been posted bringing the pot to 15 with the bet at 10
    When Alice verbally declares "I bet a buck" (non-standard)
    Then a floor decision is required because a non-standard declaration requires floor review
    And the action is held pending floor interpretation

  @EU-1358
  Scenario: Conditional declaration referring to future action is non-binding
    # Rule: TDA Rule 59 (2024) - "Conditional and premature declarations are
    #       non-standard and may be binding or non-binding at floor's
    #       discretion." Default: non-binding when the condition fails.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 1000-chip stacks
    And blinds have been posted bringing the pot to 15
    And it is Alice's turn to act
    When Bob out of turn says "if Alice raises, I'm all-in"
    And Alice then checks (no raise - the condition fails)
    Then no action is recorded for Bob
    And Bob still has the option to act in turn

  # ==========================================================================
  # Information Disclosure & Over-Betting - TDA Rules 60, 61
  # ==========================================================================
  # Real poker (TDA Rules 60-61): a player is entitled to a reasonable
  # estimation of opponents' chip stacks. Over-betting expecting change is
  # forbidden - bets are accepted at the chip-tendered amount.

  @EU-1359
  Scenario: Player is entitled to opponent's stack count on request
    # Rule: TDA Rule 60 (2024) - "Players are entitled to a reasonable
    #       estimation of opponents' chip stacks."
    # Rule: WSOP Rule 62 (2025) - same.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 500-chip stacks
    And blinds have been posted bringing the pot to 15
    When Alice requests a stack count for Bob
    Then Bob's stack of 500 is disclosed to Alice

  @EU-1360
  Scenario: Over-betting expecting change is forbidden
    # Rule: TDA Rule 61 (2024) - "Betting action should not be used to
    #       obtain change. Bets are accepted at the chip-tendered amount."
    # Rule: WSOP Rule 99 (2025) - same.
    # Alice silently pushes a 500 chip while declaring "I bet 325" -
    # bet stands at 500, no change is given.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 1000-chip stacks
    And blinds have been posted bringing the pot to 15
    When Alice pushes a single 500 chip declaring "bet 325"
    Then Alice's bet of 500 is recorded
    And no change is returned to Alice

  # ==========================================================================
  # All-In Chips Found Behind - TDA Rule 62
  # ==========================================================================
  # Real poker (TDA Rule 62): "If A bets all-in and a hidden chip is found
  # behind after a Participant has called, the chip(s) found behind are not
  # in play for this hand." Hidden chips do not retroactively join the all-in.

  @EU-1361
  @wip
  Scenario: Hidden chip discovered after a call to all-in is not in play this hand
    # Rule: TDA Rule 62 (2024) - chips found behind after a call do not
    #       retroactively join the all-in.
    # Rule: WSOP Rule 105 (2025) - same.
    Given a Texas Hold'em hand has been dealt to Alice and Bob with 200-chip stacks
    And Alice went all-in for 200
    And Bob called the 200 all-in
    When a hidden 25 chip is discovered behind Alice after the call
    Then the hidden 25 is not added to the current pot
    And Alice's effective stack for the next hand is 25

  # ==========================================================================
  # No Disclosure & Exposing Cards - TDA Rules 67, 68
  # ==========================================================================
  # Real poker (TDA Rules 67-68): one player to a hand. Disclosing hand
  # contents to anyone during a live hand is a penalty. Exposing cards
  # with action pending earns a penalty (Rule 68 + WSOP Rule 117).

  @EU-1362
  Scenario: Disclosing hand contents during a live hand triggers a penalty
    # Rule: TDA Rule 67 (2024) - "One player to a hand. Players in or out of
    #       a hand may not disclose contents."
    # Rule: WSOP Rule 116 (2025) - same.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And the hand is live and the pot is 15
    When Alice discloses her hole cards to a railbird while facing action
    Then Alice is penalised for a disclosure violation
    And the penalty severity is at least missed-hand

  @EU-1363
  @wip
  Scenario: Exposing cards with action pending earns a penalty and the hand stays live
    # Rule: TDA Rule 68 (2024) - "A player exposing his or her cards with
    #       action pending will incur a penalty but the hand will not be
    #       killed. The penalty starts at the end of the hand."
    # Rule: WSOP Rule 117 (2025) - same.
    Given a Texas Hold'em hand has been dealt to Alice, Bob, and Carol with 500-chip stacks
    And it is Alice's turn to act with action pending
    When Alice exposes both her hole cards face-up
    Then Alice is penalised for exposed cards
    And the penalty starts at the end of the current hand
    And Alice's hand remains live this hand

  # ==========================================================================
  # Disordered Stub & Random Tiebreaks - TDA RP-4, RP-14
  # ==========================================================================
  # Real poker (TDA RP-4): "If during the deal the dealer realizes the stub
  # is disordered (fewer cards than expected, an exposed card mid-stub, etc.)
  # the deal is paused and a fresh shuffle of the affected stub portion is
  # made before the deal resumes." (TDA RP-14): "Randomness may be applied
  # to special situations such as tied late-reg seats, tied stack draws."

  @EU-1364
  @wip
  Scenario: Disordered stub triggers reshuffle of the remaining stub
    # Rule: TDA RP-4 (2024) - disordered stub reshuffle.
    Given a hand mid-deal on the river with a disordered stub
    When the dealer detects the stub disorder
    Then a stub reshuffle is required
    And the burn for the next street is taken from the reshuffled stub
    And no community cards already exposed are altered

  @EU-1365
  @wip
  Scenario: Tied late-reg seat picks resolved by deterministic randomness
    # Rule: TDA RP-14 (2024) - randomness for special situations.
    Given two late-registering players Eve and Frank assigned to the same hand number
    And the same arrival timestamp
    When the seating coordinator handles the tie
    Then the seating tiebreak is resolved deterministically
    And exactly one of Eve or Frank is seated first
