# Allocated: EU-0001 .. EU-0099, EU-0568
Feature: Hand aggregate logic
  The Hand aggregate manages a single poker hand: dealing, betting rounds,
  community cards, and showdown. Each hand is an isolated consistency
  boundary with its own event stream.

  Why this aggregate exists:
  - Hands have complex, well-defined state machines (phases, betting rounds)
  - Hand-level events (ActionTaken, CardsDealt) are high-frequency
  - Hand logic is game-variant-specific (Hold'em vs Omaha vs Draw)
  - Separating from table enables parallel hand processing (multi-table)

  What breaks if this is wrong:
  - Players could act out of turn
  - Betting amounts could violate minimum raise rules
  - Community cards could be dealt in wrong phases
  - Showdown could award pots incorrectly

  Patterns enabled by this aggregate:
  - State machine enforcement: DEALING→BLINDS→BETTING→FLOP→... Each phase has
    valid transitions; invalid actions rejected. Same pattern applies to
    order fulfillment, insurance claims, approval workflows.
  - Turn-based action tracking: Only one player can act at a time. Same pattern
    applies to board games, auction rounds, approval chains.
  - High-frequency event streams: 20+ events per hand exercises snapshot
    optimization. Same pattern applies to IoT sensors, trading systems.
  - Variant polymorphism: Same aggregate handles Hold'em/Omaha/Draw with
    different rules. Same pattern applies to payment methods, shipping carriers.

  Why poker exercises these patterns well:
  - State transitions are unambiguous: can't deal turn before flop
  - Turn order is strictly enforced: only position 2 can act when action_on=2
  - Event frequency is high: BlindPosted, ActionTaken×N, CommunityCardsDealt×3
  - Rules vary by variant: 2 hole cards (Hold'em) vs 4 (Omaha) vs 5 (Draw)

  # ==========================================================================
  # Card Dealing
  # ==========================================================================
  # Dealing initializes the hand with hole cards for each player. The number
  # of hole cards depends on game variant (2 for Hold'em, 4 for Omaha, 5 for Draw).
  # Deterministic seeding enables reproducible tests.

  @EU-0001
  Scenario: Deal Texas Hold'em hand to 2 players
    Given no prior events for the hand aggregate
    When I handle a DealCards command for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    Then the result is a angzarr_client.proto.examples.CardsDealt event
    And each player has 2 hole cards
    And the remaining deck has 48 cards

  @EU-0002
  Scenario: Deal Omaha hand to 3 players
    Given no prior events for the hand aggregate
    When I handle a DealCards command for OMAHA with players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
      | player-3    | 2        | 500   |
    Then the result is a angzarr_client.proto.examples.CardsDealt event
    And each player has 4 hole cards
    And the remaining deck has 40 cards

  @EU-0003
  Scenario: Deal Five Card Draw hand to 4 players
    Given no prior events for the hand aggregate
    When I handle a DealCards command for FIVE_CARD_DRAW with players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
      | player-3    | 2        | 500   |
      | player-4    | 3        | 500   |
    Then the result is a angzarr_client.proto.examples.CardsDealt event
    And each player has 5 hole cards
    And the remaining deck has 32 cards

  @EU-0004
  Scenario: Deterministic shuffle with seed
    Given no prior events for the hand aggregate
    When I handle a DealCards command with seed "test-seed-123" and players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    Then the result is a angzarr_client.proto.examples.CardsDealt event
    And player "player-1" has specific hole cards for seed "test-seed-123"

  @EU-0005
  Scenario: Cannot deal cards twice
    Given a CardsDealt event for hand 1
    When I handle a DealCards command for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already dealt"

  @EU-0006
  Scenario: Cannot deal with fewer than 2 players
    Given no prior events for the hand aggregate
    When I handle a DealCards command for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "at least 2 players"

  # ==========================================================================
  # Blind Posting
  # ==========================================================================
  # Blinds are forced bets that seed the pot and drive action. Small blind
  # is posted first, then big blind. Short-stacked players post all-in blinds.

  @EU-0007
  Scenario: Post small blind
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a PostBlind command for player "player-1" type "small" amount 5
    Then the result is a angzarr_client.proto.examples.BlindPosted event
    And the blind event has blind_type "small"
    And the blind event has amount 5
    And the blind event has player_stack 495
    And the blind event has pot_total 5

  @EU-0008
  Scenario: Post big blind
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a BlindPosted event for player "player-1" amount 5
    When I handle a PostBlind command for player "player-2" type "big" amount 10
    Then the result is a angzarr_client.proto.examples.BlindPosted event
    And the blind event has blind_type "big"
    And the blind event has amount 10
    And the blind event has pot_total 15

  @EU-0009
  Scenario: Post all-in blind when short-stacked
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 3     |
      | player-2    | 1        | 500   |
    When I handle a PostBlind command for player "player-1" type "small" amount 5
    Then the result is a angzarr_client.proto.examples.BlindPosted event
    And the blind event has amount 3
    And the blind event has player_stack 0

  # ==========================================================================
  # Player Actions
  # ==========================================================================
  # Actions are the core gameplay: fold, check, call, bet, raise, all-in.
  # Each action has validation rules (can't check when facing a bet, minimum
  # raise amounts). Invalid actions are rejected, not auto-corrected.

  @EU-0010
  Scenario: Player folds
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle a PlayerAction command for player "player-1" action FOLD
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "FOLD"

  @EU-0011
  Scenario: Player checks when no bet
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action CHECK
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "CHECK"

  @EU-0012
  Scenario: Player calls the big blind
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action CALL amount 5
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "CALL"
    And the action event has amount 5
    And the action event has pot_total 20

  @EU-0013
  Scenario: Player bets
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action BET amount 20
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "BET"
    And the action event has amount 20
    And the action event has amount_to_call 20

  @EU-0014
  Scenario: Player raises
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action RAISE amount 30
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "RAISE"
    # amount on the event is chips_put_in: 30 total - 5 SB already posted = 25
    And the action event has amount 25

  @EU-0015
  Scenario: Player goes all-in
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 50    |
      | player-2    | 1        | 500   |
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action ALL_IN amount 50
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "ALL_IN"
    And the action event has player_stack 0

  @EU-0016
  Scenario: Cannot check when facing a bet
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action CHECK
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Cannot check"

  @EU-0017
  Scenario: Cannot bet less than minimum
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action BET amount 5
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "at least"

  # ==========================================================================
  # Community Cards
  # ==========================================================================
  # Community cards are shared by all players. Hold'em/Omaha have flop (3),
  # turn (1), river (1). Draw games have no community cards. Dealing community
  # cards transitions between betting rounds.

  @EU-0018
  Scenario: Deal the flop
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    When I handle a DealCommunityCards command with count 3
    Then the result is a angzarr_client.proto.examples.CommunityCardsDealt event
    And the event has 3 cards dealt
    And the event has phase "FLOP"
    And the remaining deck decreases by 3

  @EU-0019
  Scenario: Deal the turn
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players
    And the flop has been dealt
    And a BettingRoundComplete event for flop
    When I handle a DealCommunityCards command with count 1
    Then the result is a angzarr_client.proto.examples.CommunityCardsDealt event
    And the event has 1 card dealt
    And the event has phase "TURN"
    And all_community_cards has 4 cards

  @EU-0020
  Scenario: Deal the river
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players
    And the flop and turn have been dealt
    And a BettingRoundComplete event for turn
    When I handle a DealCommunityCards command with count 1
    Then the result is a angzarr_client.proto.examples.CommunityCardsDealt event
    And the event has phase "RIVER"
    And all_community_cards has 5 cards

  @EU-0021
  Scenario: Cannot deal community cards in Five Card Draw
    Given a CardsDealt event for FIVE_CARD_DRAW with 2 players
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    When I handle a DealCommunityCards command with count 3
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "community cards"

  # ==========================================================================
  # Draw Phase (Five Card Draw)
  # ==========================================================================
  # In draw games, players discard and receive new cards. Standing pat means
  # keeping all cards. Draw is only valid in draw game variants.

  @EU-0022
  Scenario: Player discards and draws cards
    Given a CardsDealt event for FIVE_CARD_DRAW with 2 players
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    When I handle a RequestDraw command for player "player-1" discarding indices [0, 2, 4]
    Then the result is a angzarr_client.proto.examples.DrawCompleted event
    And the draw event has cards_discarded 3
    And the draw event has cards_drawn 3
    And player "player-1" has 5 hole cards

  @EU-0023
  Scenario: Player stands pat (no discard)
    Given a CardsDealt event for FIVE_CARD_DRAW with 2 players
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    When I handle a RequestDraw command for player "player-1" discarding indices []
    Then the result is a angzarr_client.proto.examples.DrawCompleted event
    And the draw event has cards_discarded 0
    And the draw event has cards_drawn 0

  @EU-0024
  Scenario: Cannot draw in Texas Hold'em
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players
    And blinds posted with pot 15
    When I handle a RequestDraw command for player "player-1" discarding indices [0]
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "not supported"

  # ==========================================================================
  # Showdown - Card Reveal
  # ==========================================================================
  # At showdown, remaining players reveal or muck their cards. Revealing
  # triggers hand evaluation; mucking concedes without showing.

  @EU-0025
  Scenario: Player reveals cards at showdown
    Given a completed betting for TEXAS_HOLDEM with 2 players
    And a ShowdownStarted event for the hand
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the reveal event has cards for player "player-1"
    And the reveal event has a hand ranking

  @EU-0026
  Scenario: Player mucks cards
    Given a completed betting for TEXAS_HOLDEM with 2 players
    And a ShowdownStarted event for the hand
    When I handle a RevealCards command for player "player-1" with muck true
    Then the result is a angzarr_client.proto.examples.CardsMucked event

  # ==========================================================================
  # Pot Award
  # ==========================================================================
  # Pots are awarded after showdown (best hand) or when all but one player
  # folds. Awarding the pot triggers HandComplete and returns control to table.

  @EU-0027
  Scenario: Award pot to single winner
    Given a completed betting for TEXAS_HOLDEM with 2 players
    And a CardsRevealed event for player "player-1" with ranking FLUSH
    And a CardsMucked event for player "player-2"
    When I handle an AwardPot command with winner "player-1" amount 15
    Then the result is a angzarr_client.proto.examples.PotAwarded event
    And the award event has winner "player-1" with amount 15

  @EU-0028
  Scenario: Award pot generates HandComplete
    Given a completed betting for TEXAS_HOLDEM with 2 players
    When I handle an AwardPot command with winner "player-1" amount 15
    Then a HandComplete event is emitted
    And the hand status is "complete"

  # ==========================================================================
  # Hand Evaluation Logic
  # ==========================================================================
  # Hand ranking (high card through royal flush) determines winners. These
  # scenarios verify the evaluator correctly ranks hands and compares kickers.

  @EU-0029
  Scenario: Royal flush beats straight flush
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | As Ks      | Qs Js Ts 2c 3d     |
      | player-2 | 9s 8s      | Qs Js Ts 2c 3d     |
    When hands are evaluated
    Then player "player-1" has ranking "ROYAL_FLUSH"
    And player "player-2" has ranking "STRAIGHT_FLUSH"
    And player "player-1" wins

  @EU-0030
  Scenario: Full house beats flush
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | Ah Ad      | Ac 2d 2h 4h 6h     |
      | player-2 | Kh 7h      | Ac 2d 2h 4h 6h     |
    When hands are evaluated
    Then player "player-1" has ranking "FULL_HOUSE"
    And player "player-2" has ranking "FLUSH"
    And player "player-1" wins

  @EU-0031
  Scenario: High card comparison with kickers
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | Ah Qc      | Kd Jc 9s 4h 2d     |
      | player-2 | Ah Jd      | Kd Jc 9s 4h 2d     |
    When hands are evaluated
    Then player "player-1" has ranking "HIGH_CARD"
    And player "player-2" has ranking "PAIR"
    And player "player-2" wins

  # ==========================================================================
  # Handler-Level Hand Evaluation
  # ==========================================================================
  # These scenarios verify that RevealCards handlers correctly invoke the
  # evaluator and populate the CardsRevealed event with rankings.

  @EU-0032
  Scenario: Handler detects straight
    Given a hand at showdown with player "player-1" holding "Th 9c" and community "8d 7s 6h 2c 3d"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "STRAIGHT"

  @EU-0033
  Scenario: Handler detects wheel straight (A-2-3-4-5)
    Given a hand at showdown with player "player-1" holding "Ah 2c" and community "3d 4s 5h Kc Qd"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "STRAIGHT"

  @EU-0034
  Scenario: Handler detects straight flush
    Given a hand at showdown with player "player-1" holding "9h 8h" and community "7h 6h 5h 2c 3d"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "STRAIGHT_FLUSH"

  @EU-0035
  Scenario: Handler detects royal flush
    Given a hand at showdown with player "player-1" holding "As Ks" and community "Qs Js Ts 2c 3d"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "ROYAL_FLUSH"

  @EU-0036
  Scenario: Handler detects four of a kind
    Given a hand at showdown with player "player-1" holding "Kh Kd" and community "Ks Kc 2h 3d 4s"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "FOUR_OF_A_KIND"

  @EU-0037
  Scenario: Handler detects full house
    Given a hand at showdown with player "player-1" holding "Ah Ad" and community "Ac 2d 2h 4s 6c"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "FULL_HOUSE"

  @EU-0038
  Scenario: Handler detects flush
    Given a hand at showdown with player "player-1" holding "Ah 7h" and community "2h 4h 6h Kc Qd"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "FLUSH"

  @EU-0039
  Scenario: Handler detects three of a kind
    Given a hand at showdown with player "player-1" holding "Jh Jd" and community "Js 2c 4d 6h 8s"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "THREE_OF_A_KIND"

  @EU-0040
  Scenario: Handler detects two pair
    Given a hand at showdown with player "player-1" holding "Th Td" and community "5s 5c 2h 3d Ks"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "TWO_PAIR"

  @EU-0041
  Scenario: Handler detects pair
    Given a hand at showdown with player "player-1" holding "Ah Ac" and community "Kd Js 9h 4c 2d"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "PAIR"

  @EU-0042
  Scenario: Handler detects high card
    Given a hand at showdown with player "player-1" holding "Ah Qc" and community "Kd Js 9h 4c 2d"
    When I handle a RevealCards command for player "player-1" with muck false
    Then the result is a angzarr_client.proto.examples.CardsRevealed event
    And the revealed ranking is "HIGH_CARD"

  # ==========================================================================
  # Error Paths - Betting Validation
  # ==========================================================================
  # The hand aggregate enforces strict betting rules. Invalid actions are
  # rejected with clear error messages rather than auto-corrected.

  @EU-0043
  Scenario: Cannot raise less than minimum raise amount
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    And a ActionTaken event for player "player-1" with action CALL amount 5
    When I handle a PlayerAction command for player "player-2" action RAISE amount 15
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "raise"

  # ==========================================================================
  # Split Pot and Kicker Resolution
  # ==========================================================================
  # Multiple players can share a pot when hands are identical, or a kicker
  # can determine the winner when hand rankings match.

  @EU-0044
  Scenario: Split pot when hands are identical
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | As Kd      | Ah Kh 2c 5d 9s     |
      | player-2 | Ac Ks      | Ah Kh 2c 5d 9s     |
    When hands are evaluated
    Then player "player-1" has ranking "TWO_PAIR"
    And player "player-2" has ranking "TWO_PAIR"

  @EU-0045
  Scenario: Kicker determines winner with matching pairs
    Given a showdown with player hands:
      | player   | hole_cards | community_cards    |
      | player-1 | As Kd      | Ah 2c 5d 9s 3h     |
      | player-2 | Ac Qd      | Ah 2c 5d 9s 3h     |
    When hands are evaluated
    Then player "player-1" has ranking "PAIR"
    And player "player-2" has ranking "PAIR"
    And player "player-1" wins

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # Hand state includes phase, community cards, player stacks, and who has
  # folded. These scenarios verify correct state rebuilding from events.

  @EU-0046
  Scenario: Rebuild state after dealing
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I rebuild the hand state
    Then the hand state has phase "PREFLOP"
    And the hand state has status "betting"
    And the hand state has 2 players

  @EU-0047
  Scenario: Rebuild state with community cards
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players
    And the flop has been dealt
    When I rebuild the hand state
    Then the hand state has 3 community cards
    And the hand state has phase "FLOP"

  @EU-0048
  Scenario: Rebuild state tracks folded players
    Given a CardsDealt event for TEXAS_HOLDEM with 3 players
    And blinds posted with pot 15
    And player "player-1" folded
    When I rebuild the hand state
    Then player "player-1" has_folded is true
    And active player count is 2

  # ==========================================================================
  # Deal Command — Additional Edge Cases
  # ==========================================================================
  # Validation failures around dealing: empty player list, minimum players,
  # and deterministic reproducibility via deck_seed.

  @EU-0049
  Scenario: Cannot deal with empty player list
    Given no prior events for the hand aggregate
    When I handle a DealCards command for TEXAS_HOLDEM with no players
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "No players"

  @EU-0050
  Scenario: Deterministic deal produces identical hole cards for the same seed
    Given no prior events for the hand aggregate
    When I deal the same TEXAS_HOLDEM hand twice with seed "seed123"
    Then both deals produce identical hole cards

  # ==========================================================================
  # PostBlind Command — Edge Cases
  # ==========================================================================
  # Validation gates: hand must be dealt, player_root required, player must
  # exist, amount must be positive.

  @EU-0051
  Scenario: Cannot post blind before hand is dealt
    Given no prior events for the hand aggregate
    When I handle a PostBlind command for player "player-1" type "small" amount 5
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Hand not dealt"

  @EU-0052
  Scenario: Cannot post blind without player_root
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a PostBlind command with no player_root type "small" amount 5
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "player_root"

  @EU-0053
  Scenario: Cannot post blind for player not in hand
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a PostBlind command for player "ghost" type "small" amount 5
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not in hand"

  @EU-0054
  Scenario: Cannot post blind with zero or negative amount
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a PostBlind command for player "player-1" type "small" amount 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "positive"

  @EU-0055
  Scenario: Cannot post blind after hand complete
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a HandComplete event for the hand
    When I handle a PostBlind command for player "player-1" type "small" amount 5
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "complete"

  @EU-0056
  Scenario: Cannot post blind by folded player
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And player "player-1" folded
    When I handle a PostBlind command for player "player-1" type "small" amount 5
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "folded"

  # ==========================================================================
  # PlayerAction Command — Edge Cases
  # ==========================================================================
  # Pre-action validation: hand must exist, player must exist, cannot act
  # while folded or all-in. Action-specific validations follow.

  @EU-0057
  Scenario: Cannot act before hand is dealt
    Given no prior events for the hand aggregate
    When I handle a PlayerAction command for player "player-1" action FOLD
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Hand not dealt"

  @EU-0058
  Scenario: Cannot act without player_root
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command with no player_root action FOLD
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "player_root"

  @EU-0059
  Scenario: Cannot act for player not in hand
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "ghost" action FOLD
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not in hand"

  @EU-0060
  Scenario: Folded player cannot act again
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    And player "player-1" folded
    When I handle a PlayerAction command for player "player-1" action CHECK
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "folded"

  @EU-0061
  Scenario: Cannot take actions outside betting phase
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a ShowdownStarted event for the hand
    When I handle a PlayerAction command for player "player-1" action FOLD
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Not in betting"

  @EU-0062
  Scenario: Cannot call when there is nothing to call
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    And a ActionTaken event for player "player-1" with action CALL amount 5
    When I handle a PlayerAction command for player "player-2" action CALL
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Nothing to call"

  @EU-0063
  Scenario: Cannot bet when there is already a bet
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action BET amount 20
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already a bet"

  @EU-0064
  Scenario: Cannot bet more than stack
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action BET amount 5000
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "exceeds stack"

  @EU-0065
  Scenario: Cannot raise when there is no bet
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action RAISE amount 20
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "no bet"

  @EU-0066
  Scenario: Cannot raise more than stack
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action RAISE amount 5000
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "exceeds stack"

  @EU-0067
  Scenario: Raise below minimum increment rejected
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action RAISE amount 12
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "at least"

  @EU-0068
  Scenario: Invalid action type rejected
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" with unknown action type
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Invalid action"

  @EU-0069
  Scenario: All-in action uses the entire remaining stack
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 1000
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" action ALL_IN
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "ALL_IN"
    And the action event has player_stack 0

  @EU-0070
  Scenario: Bet for entire remaining stack becomes all-in
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 100
    And short-stacked blinds posted with small 5 big 10 and stack 100
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action BET amount 95
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "ALL_IN"

  @EU-0071
  Scenario: Raise for entire remaining stack becomes all-in
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 100
    And short-stacked blinds posted with small 5 big 10 and stack 100
    When I handle a PlayerAction command for player "player-1" action RAISE amount 100
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "ALL_IN"

  @EU-0072
  Scenario: All-in player cannot act again
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 1000
    And blinds posted with pot 15 and current_bet 10
    And a ActionTaken event for player "player-1" with action ALL_IN amount 995
    When I handle a PlayerAction command for player "player-1" action CHECK
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "all-in"

  # ==========================================================================
  # DealCommunityCards Command — Edge Cases
  # ==========================================================================

  @EU-0073
  Scenario: Cannot deal community cards before the hand
    Given no prior events for the hand aggregate
    When I handle a DealCommunityCards command with count 3
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Hand not dealt"

  @EU-0074
  Scenario: Cannot deal zero community cards
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a DealCommunityCards command with count 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message contains "at least 1"

  @EU-0075
  Scenario: Wrong count for phase transition is rejected
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    When I handle a DealCommunityCards command with count 1
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Expected"

  @EU-0076
  Scenario: Cannot deal community cards after hand complete
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a HandComplete event for the hand
    When I handle a DealCommunityCards command with count 3
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "complete"

  # ==========================================================================
  # RevealCards Command — Edge Cases
  # ==========================================================================

  @EU-0077
  Scenario: Cannot reveal before hand is dealt
    Given no prior events for the hand aggregate
    When I handle a RevealCards command for player "player-1" with muck false
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Hand not dealt"

  @EU-0078
  Scenario: Cannot reveal outside of showdown
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a RevealCards command for player "player-1" with muck false
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Not in showdown"

  @EU-0079
  Scenario: Cannot reveal without player_root
    Given a completed betting for TEXAS_HOLDEM with 2 players
    And a ShowdownStarted event for the hand
    When I handle a RevealCards command with no player_root and muck false
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "player_root"

  @EU-0080
  Scenario: Cannot reveal for player not in hand
    Given a completed betting for TEXAS_HOLDEM with 2 players
    And a ShowdownStarted event for the hand
    When I handle a RevealCards command for player "ghost" with muck false
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not in hand"

  @EU-0081
  Scenario: Folded player cannot reveal cards
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And player "player-1" folded
    And a ShowdownStarted event for the hand
    When I handle a RevealCards command for player "player-1" with muck false
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "folded"

  # ==========================================================================
  # AwardPot Command — Edge Cases
  # ==========================================================================

  @EU-0082
  Scenario: Cannot award pot before hand is dealt
    Given no prior events for the hand aggregate
    When I handle an AwardPot command with winner "player-1" amount 100
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Hand not dealt"

  @EU-0083
  Scenario: Cannot award with empty awards list
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle an AwardPot command with no awards
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "No awards"

  @EU-0084
  Scenario: Cannot award to player not in hand
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle an AwardPot command with winner "ghost" amount 15
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not in hand"

  @EU-0085
  Scenario: Cannot award to folded player
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    And player "player-1" folded
    When I handle an AwardPot command with winner "player-1" amount 15
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Folded"

  @EU-0086
  Scenario: Cannot award pot after hand complete
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a HandComplete event for the hand
    When I handle an AwardPot command with winner "player-1" amount 15
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "already complete"

  @EU-0087
  Scenario: Award adjusts mismatched total to the actual pot
    # When the sum of awards doesn't match the pot, the first winner's
    # amount is adjusted so the total matches the pot.
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle an AwardPot command with winner "player-1" amount 10
    Then the result is a angzarr_client.proto.examples.PotAwarded event
    And the award event has winner "player-1" with amount 15

  # ==========================================================================
  # BettingRoundComplete Applier — Per-Round State Reset
  # ==========================================================================
  # The BettingRoundComplete event resets per-round betting state (bet_this_round,
  # current_bet, has_acted) and can carry stack snapshots. For Five Card Draw,
  # completing preflop advances the phase to DRAW.

  @EU-0088
  Scenario: BettingRoundComplete resets per-round betting state
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 1000
    And blinds posted with pot 15 and current_bet 10
    And a BettingRoundComplete event for preflop
    When I rebuild the hand state
    Then the hand state current_bet is 0
    And each player has bet_this_round 0

  @EU-0089
  Scenario: BettingRoundComplete updates player stack snapshots
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 1000
    And a BettingRoundComplete event with stack snapshots:
      | player_root | stack | is_all_in | has_folded |
      | player-1    | 800   | false     | false      |
      | player-2    | 0     | true      | false      |
    When I rebuild the hand state
    Then player "player-1" has stack 800
    And player "player-2" has stack 0
    And player "player-2" is all-in

  @EU-0090
  Scenario: Five Card Draw advances preflop to draw phase
    Given a CardsDealt event for FIVE_CARD_DRAW with 2 players
    And a BettingRoundComplete event for preflop
    When I rebuild the hand state
    Then the hand state has phase "DRAW"

  @EU-0091
  Scenario: Five Card Draw does not re-enter draw phase on draw completion
    Given a CardsDealt event for FIVE_CARD_DRAW with 2 players
    And a BettingRoundComplete event for preflop
    And a BettingRoundComplete event for draw
    When I rebuild the hand state
    Then the hand state has phase "DRAW"

  @EU-0092
  Scenario: Texas Hold'em ignores draw transition on preflop complete
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players
    And a BettingRoundComplete event for preflop
    When I rebuild the hand state
    Then the hand state has phase "PREFLOP"

  # ==========================================================================
  # State Accessors and Event Appliers
  # ==========================================================================

  @EU-0093
  Scenario: Hand id combines table_root hex and hand_number
    Given a CardsDealt event with table_root "aabbccdd" and hand_number 5
    When I rebuild the hand state
    Then the hand state has hand_id "aabbccdd_5"

  @EU-0094
  Scenario: PotAwarded applier increases winner stack
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a PotAwarded event awarding player "player-1" amount 100
    When I rebuild the hand state
    Then player "player-1" has stack 600

  @EU-0095
  Scenario: HandComplete applier sets status to complete
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And a HandComplete event for the hand
    When I rebuild the hand state
    Then the hand state has status "complete"

  @EU-0096
  Scenario: Event book records every emitted event
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 1000
    And a BlindPosted event for player "player-1" amount 5
    And a BlindPosted event for player "player-2" amount 10
    When I rebuild the hand state
    Then the hand event book has 3 pages

  @EU-0097
  Scenario: small_blind and big_blind accessors reflect posted blinds
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 1000
    And a BlindPosted event for player "player-1" amount 5
    And a BlindPosted event for player "player-2" amount 10
    When I rebuild the hand state
    Then the hand state small_blind is 5
    And the hand state big_blind is 10
    And the hand state min_raise is 10

  @EU-0098
  Scenario: get_active_players excludes folded and all-in players
    Given a CardsDealt event for TEXAS_HOLDEM with 3 players
    And blinds posted with pot 15
    And player "player-3" folded
    When I rebuild the hand state
    Then the hand state has 2 active players

  @EU-0099
  Scenario: Cannot award to winner whose root is unknown
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle an AwardPot command with winner "unknown-player" amount 15
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "not in hand"

  # ==========================================================================
  # RequestDraw Command — Duplicate Indices
  # ==========================================================================

  @EU-0568
  Scenario: RequestDraw rejects duplicate card indices
    Given a CardsDealt event for FIVE_CARD_DRAW with 2 players
    And blinds posted with pot 15
    And a BettingRoundComplete event for preflop
    When I handle a RequestDraw command for player "player-1" discarding indices [0, 0, 1]
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Duplicate"
