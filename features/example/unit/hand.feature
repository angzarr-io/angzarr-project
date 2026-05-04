# Allocated: EU-0001 .. EU-0099, EU-0568, EU-1008, EU-1009, EU-1100 .. EU-1124
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
    # amount_to_call is the absolute new current_bet level — the threshold any
    # subsequent actor must reach to call. A consumer computes their owed
    # amount as amount_to_call - their.bet_this_round. The raise totalled to
    # 30, so current_bet := 30. (Emitting chips_put_in here would shadow the
    # `amount` field and lose the absolute threshold needed for replay.)
    And the action event has amount_to_call 30

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
    Then the command fails with status "FAILED_PRECONDITION"
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
    And I capture player "player-1" hole cards as "pre_draw"
    When I handle a RequestDraw command for player "player-1" discarding indices [0, 2, 4]
    Then the result is a angzarr_client.proto.examples.DrawCompleted event
    And the draw event has cards_discarded 3
    And the draw event has cards_drawn 3
    And player "player-1" has 5 hole cards
    # Discarding indices [0, 2, 4] must replace exactly those positions and
    # leave indices 1 and 3 unchanged. (A buggy applier that slices off the
    # first N hole cards and appends new ones would fail this — it would
    # change positions 1 and 3 to whatever was at original positions 4 and N1.)
    And player "player-1" hole card at index 1 matches "pre_draw" index 1
    And player "player-1" hole card at index 3 matches "pre_draw" index 3

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
    Then the command fails with status "FAILED_PRECONDITION"
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
    Then the command fails with status "FAILED_PRECONDITION"
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
    Then the command fails with status "INVALID_ARGUMENT"
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
    Then the command fails with status "INVALID_ARGUMENT"
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
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "at least"

  @EU-0068
  Scenario: Invalid action type rejected
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15 and current_bet 10
    When I handle a PlayerAction command for player "player-1" with unknown action type
    Then the command fails with status "INVALID_ARGUMENT"
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
    # short-stacked-blinds step posts SB 5 from initial stack 100, leaving
    # player-1 with stack 95 going into FLOP. BET 95 == remaining stack, so
    # the handler reclassifies the action as ALL_IN. Pin amount and resulting
    # stack so a buggy classifier (e.g. emitting BET amount 95 with
    # player_stack 0) is caught here, not just by the action label check.
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 100
    And short-stacked blinds posted with small 5 big 10 and stack 100
    And a BettingRoundComplete event for preflop
    And a CommunityCardsDealt event for FLOP
    When I handle a PlayerAction command for player "player-1" action BET amount 95
    Then the result is an angzarr_client.proto.examples.ActionTaken event
    And the action event has action "ALL_IN"
    And the action event has amount 95
    And the action event has player_stack 0

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
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "Must deal at least"

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
    Then the command fails with status "INVALID_ARGUMENT"
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

  @EU-1009
  Scenario: AwardPot splits pot evenly between two winners with identical hands
    # Identical-hand split: pot 100, two winners each take 50. EU-0044
    # confirms the rankings are equal but never asserts the pot is actually
    # divided. Without this scenario, an evaluator that picks a single winner
    # by enumeration order on ties would silently overpay one player and
    # stiff the other — the rank labels would still match.
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 100
    When I handle an AwardPot command with awards:
      | player_root | amount |
      | player-1    | 50     |
      | player-2    | 50     |
    Then the result is a angzarr_client.proto.examples.PotAwarded event
    And the award event has 2 winners
    And the award event has winner "player-1" with amount 50
    And the award event has winner "player-2" with amount 50

  @EU-1008
  Scenario: AwardPot rejects when sum exceeds pot total
    # The under-award case (EU-0087) is silently corrected, but the over-award
    # case must reject — paying out chips that don't exist would corrupt the
    # ledger. The handler raises AwardsExceedPot (BoundViolation) which
    # surfaces as FAILED_PRECONDITION + AWARDS_EXCEED_POT.
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle an AwardPot command with winner "player-1" amount 50
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "AWARDS_EXCEED_POT"
    And the rejection field "got" equals "50"
    And the rejection field "bound" equals "15"

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

  # ==========================================================================
  # Side Pots — Layered Awards When Stacks Differ
  # ==========================================================================
  # Real poker (TDA Rule 42): when a player goes all-in for less than the
  # current bet, a side pot is created from the additional chips contributed
  # by the players with deeper stacks. The all-in player is eligible only for
  # the main pot; the side pot is contested only among the remaining bettors.
  # The proto already exposes ``PotAward.pot_type`` and ``PotWinner.pot_type``
  # ("main", "side_1", "side_2", ...) — these scenarios exercise that surface.

  @EU-1100
  Scenario: Three-way all-in at different stacks creates a main pot and one side pot
    # A=100, B=200, C=500. A all-in for 100. B all-in for 200. C calls 200.
    # Main pot = 100 * 3 = 300, eligible {A,B,C}.
    # Side pot = (200 - 100) * 2 = 200, eligible {B,C} only.
    # C's uncontested chips (300) return to C — not part of any pot.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And a ActionTaken event for player "player-A" with action ALL_IN amount 100
    And a ActionTaken event for player "player-B" with action ALL_IN amount 200
    And a ActionTaken event for player "player-C" with action CALL amount 200
    When the side pots are computed
    Then there are 2 pots
    And pot "main" has amount 300 and eligible players "player-A,player-B,player-C"
    And pot "side_1" has amount 200 and eligible players "player-B,player-C"

  @EU-1101
  Scenario: Side pot is contested only by players who could match the higher all-in
    # Same setup as EU-1100. If player-A wins the showdown, A takes only the
    # main pot (300); the side pot (200) is awarded to whichever of B/C has
    # the better hand among them, since A was not eligible for it.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And all three players are all-in with totals 100/200/200
    And the side pots are computed:
      | pot_type | amount | eligible                            |
      | main     | 300    | player-A,player-B,player-C          |
      | side_1   | 200    | player-B,player-C                   |
    When I handle an AwardPot command with awards:
      | player_root | amount | pot_type |
      | player-A    | 300    | main     |
      | player-C    | 200    | side_1   |
    Then the result is a angzarr_client.proto.examples.PotAwarded event
    And the award event has 2 winners
    And the award event winner 0 has player_root "player-A" amount 300 pot_type "main"
    And the award event winner 1 has player_root "player-C" amount 200 pot_type "side_1"

  @EU-1102
  Scenario: Award rejects a winner who is not eligible for the pot they were assigned
    # Player-A is all-in for the main pot only; awarding player-A any chips
    # from "side_1" must be rejected — A could not have matched those chips.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And the side pots are computed:
      | pot_type | amount | eligible                            |
      | main     | 300    | player-A,player-B,player-C          |
      | side_1   | 200    | player-B,player-C                   |
    When I handle an AwardPot command with awards:
      | player_root | amount | pot_type |
      | player-A    | 200    | side_1   |
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "WINNER_NOT_ELIGIBLE_FOR_POT"
    And the rejection field "pot_type" equals "side_1"
    And the rejection field "player_root" contains "player-A"

  @EU-1103
  Scenario: Four-way all-in produces a main pot and two distinct side pots
    # A=50, B=150, C=300, D=300. All four all-in.
    # Main pot   = 50  * 4 = 200, eligible {A,B,C,D}
    # Side pot 1 = 100 * 3 = 300, eligible {B,C,D}
    # Side pot 2 = 150 * 2 = 300, eligible {C,D}
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 50    |
      | player-B    | 1        | 150   |
      | player-C    | 2        | 300   |
      | player-D    | 3        | 300   |
    And blinds posted with pot 15
    And all four players are all-in with totals 50/150/300/300
    When the side pots are computed
    Then there are 3 pots
    And pot "main" has amount 200 and eligible players "player-A,player-B,player-C,player-D"
    And pot "side_1" has amount 300 and eligible players "player-B,player-C,player-D"
    And pot "side_2" has amount 300 and eligible players "player-C,player-D"

  @EU-1104
  Scenario: Folded player contributions stay in the pot they were already part of
    # Folding does not refund chips. If a player put in 80 and then folded
    # before an opponent went all-in for 100, that 80 still counts toward
    # the main pot. The main pot is sized to the smallest still-contesting
    # all-in (100), not to the folded player's contribution (80).
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And player "player-B" has invested 80 then folded
    And player "player-A" is all-in for 100
    And player "player-C" called 100
    When the side pots are computed
    Then there is 1 pot
    And pot "main" has amount 280 and eligible players "player-A,player-C"

  @EU-1105
  Scenario: Uncontested over-bet by the deepest stack is returned, not pooled
    # If C bets 500 but the next-deepest stack is 200 (B all-in), the
    # uncontested 300 of C's bet is NOT placed into any pot — it returns to
    # C's stack. Only chips that at least two players can match form a pot.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And player-A all-in for 100, player-B all-in for 200, player-C bets 500
    When the side pots are computed
    Then the uncontested return to "player-C" is 300
    And the sum of all pot amounts equals 500

  @EU-1106
  Scenario: AwardPot routes pot_type per-pot and pot_total reflects each pot's amount
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And the side pots are computed:
      | pot_type | amount |
      | main     | 300    |
      | side_1   | 200    |
    When I handle an AwardPot command with awards:
      | player_root | amount | pot_type |
      | player-A    | 300    | main     |
      | player-B    | 200    | side_1   |
    Then a PotAwarded event is emitted
    And the award event winner 0 has pot_type "main"
    And the award event winner 1 has pot_type "side_1"

  @EU-1107
  Scenario: HandComplete after multi-pot award lists every winner across pots
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And the side pots are computed:
      | pot_type | amount |
      | main     | 300    |
      | side_1   | 200    |
    When I handle an AwardPot command with awards:
      | player_root | amount | pot_type |
      | player-A    | 300    | main     |
      | player-C    | 200    | side_1   |
    Then a HandComplete event is emitted
    And the HandComplete event has 2 winners
    And the HandComplete winners include "player-A" with pot_type "main"
    And the HandComplete winners include "player-C" with pot_type "side_1"

  @EU-1108
  Scenario: Split within a side pot when two eligible players tie
    # B and C are eligible for side_1. Both have identical hands. The pot
    # (200) splits 100/100. A is ineligible and receives nothing from side_1.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
      | player-C    | 2        | 500   |
    And blinds posted with pot 15
    And the side pots are computed:
      | pot_type | amount |
      | main     | 300    |
      | side_1   | 200    |
    When I handle an AwardPot command with awards:
      | player_root | amount | pot_type |
      | player-A    | 300    | main     |
      | player-B    | 100    | side_1   |
      | player-C    | 100    | side_1   |
    Then a PotAwarded event is emitted
    And the award event has 3 winners

  @EU-1109
  Scenario: All-in for less than min-raise does not create a side pot when only one other caller remains
    # When only one player has chips left to bet after a short all-in, no
    # side pot can form (a pot needs at least two contestable bettors).
    # Main pot just absorbs both contributions.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 30    |
      | player-B    | 1        | 500   |
    And blinds posted with pot 15
    And player-A all-in for 30, player-B called 30
    When the side pots are computed
    Then there is 1 pot
    And pot "main" has amount 60 and eligible players "player-A,player-B"

  # ==========================================================================
  # Antes — Forced Per-Player Bets Before Blinds
  # ==========================================================================
  # Real poker (TDA Rule 7 + level structure): tournaments commonly require
  # every player to post an ante in addition to the blinds. Modern WSOP /
  # TDA structures more often use the "BB ante" — a single ante posted by
  # the BB equal to the BB amount. Either form must contribute to the pot
  # before the deal-deciding action begins. ``BlindLevel.ante`` already
  # exists in the proto; ``BlindPosted.blind_type`` accepts "ante".

  @EU-1110
  Scenario: Each player posts an ante before the small blind
    # Per-player ante. Three players each post ante 2 (total 6) before SB/BB
    # are posted. Pot after antes = 6, after SB+BB = 21.
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
      | player-3    | 2        | 500   |
    When I handle a PostBlind command for player "player-1" type "ante" amount 2
    And I handle a PostBlind command for player "player-2" type "ante" amount 2
    And I handle a PostBlind command for player "player-3" type "ante" amount 2
    Then 3 BlindPosted events are emitted with blind_type "ante"
    And the hand state pot_total is 6
    And player "player-1" has stack 498
    And player "player-2" has stack 498
    And player "player-3" has stack 498

  @EU-1111
  Scenario: Big-blind ante is posted once by the BB seat for the whole table
    # BB ante = the BB amount, posted by the BB seat in addition to the BB.
    # With BB=10 and a BB-ante structure, the BB seat puts 20 in (10 BB +
    # 10 ante), other seats post no ante.
    Given a CardsDealt event for TEXAS_HOLDEM with 3 players at stacks 500
    When I handle a PostBlind command for player "player-2" type "bb_ante" amount 10
    Then the result is a angzarr_client.proto.examples.BlindPosted event
    And the blind event has blind_type "bb_ante"
    And the blind event has amount 10
    And the blind event has player_stack 490
    And the hand state pot_total is 10

  @EU-1112
  Scenario: Short-stacked player posts an all-in ante for less than the full ante
    # A short stack with chips below the ante still posts what they have and
    # is marked all-in for the hand. The ante they did post still contributes
    # to the main pot (parallel to short-stacked blinds, EU-0009).
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-1    | 0        | 1     |
      | player-2    | 1        | 500   |
    When I handle a PostBlind command for player "player-1" type "ante" amount 5
    Then the result is a angzarr_client.proto.examples.BlindPosted event
    And the blind event has blind_type "ante"
    And the blind event has amount 1
    And the blind event has player_stack 0
    And player "player-1" is all-in

  @EU-1113
  Scenario: Posting an ante does not start the betting round on its own
    # Antes are forced bets but do NOT establish current_bet (only the BB
    # does). After ante and SB are posted, current_bet is the SB amount.
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    When I handle a PostBlind command for player "player-1" type "ante" amount 2
    Then the result is a angzarr_client.proto.examples.BlindPosted event
    And the hand state current_bet is 0

  @EU-1114
  Scenario: Cannot post an ante after blinds are already posted
    # Procedural ordering: antes are collected before blinds. Posting an
    # ante after the BB is up is rejected.
    Given a CardsDealt event for TEXAS_HOLDEM with 2 players at stacks 500
    And blinds posted with pot 15
    When I handle a PostBlind command for player "player-1" type "ante" amount 2
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "ante"

  @EU-1115
  Scenario: Ante contributes to the main pot for side-pot accounting
    # An ante from a player who later folds still belongs to the main pot,
    # exactly like blinds (parallel to EU-1104).
    Given a CardsDealt event for TEXAS_HOLDEM with players:
      | player_root | position | stack |
      | player-A    | 0        | 100   |
      | player-B    | 1        | 200   |
    And player "player-A" posts ante 5 then folds before the flop
    And player "player-B" posts ante 5
    When the side pots are computed
    Then pot "main" includes the 5 ante from "player-A"
    And pot "main" includes the 5 ante from "player-B"

  # ==========================================================================
  # Showdown Reveal Order
  # ==========================================================================
  # Real poker (TDA Rule 36 + Robert's Rules §36): at showdown the player
  # who took the last aggressive action (bet or raise) on the river must
  # show first. If there was no betting on the river, the first un-folded
  # seat clockwise of the dealer button shows first; remaining players
  # follow in clockwise order. The proto's ``ShowdownStarted.players_to_show``
  # is a repeated bytes field — these scenarios pin the order.

  @EU-1120
  Scenario: Last aggressor on the river shows cards first
    # Three-handed: dealer at seat 0 (player-A), SB at 1 (player-B), BB at 2
    # (player-C). On the river, player-B bets, player-C calls, player-A
    # calls. Last aggressor was player-B. Showdown order: B, then C clockwise,
    # then A.
    Given a hand at showdown with:
      | player_root | seat | folded |
      | player-A    | 0    | false  |
      | player-B    | 1    | false  |
      | player-C    | 2    | false  |
    And the last aggressive action on the river was by "player-B"
    When the ShowdownStarted event is emitted
    Then the showdown players_to_show order is "player-B,player-C,player-A"

  @EU-1121
  Scenario: With no river betting, the first seat clockwise of the dealer shows first
    # Dealer at seat 0. Round was checked through. Seat 1 (SB) is the first
    # un-folded clockwise seat from the dealer, so SB shows first; the rest
    # follow clockwise.
    Given a hand at showdown with:
      | player_root | seat | folded |
      | player-A    | 0    | false  |
      | player-B    | 1    | false  |
      | player-C    | 2    | false  |
    And there was no aggressive action on the river
    And the dealer is at seat 0
    When the ShowdownStarted event is emitted
    Then the showdown players_to_show order is "player-B,player-C,player-A"

  @EU-1122
  Scenario: Folded players are excluded from the showdown order
    # player-C folded on the turn. They do not appear in players_to_show
    # even though they were dealt in.
    Given a hand at showdown with:
      | player_root | seat | folded |
      | player-A    | 0    | false  |
      | player-B    | 1    | false  |
      | player-C    | 2    | true   |
      | player-D    | 3    | false  |
    And the last aggressive action on the river was by "player-A"
    When the ShowdownStarted event is emitted
    Then the showdown players_to_show order is "player-A,player-B,player-D"

  @EU-1123
  Scenario: An out-of-order reveal is rejected
    # The hand aggregate enforces showdown order: a RevealCards from a player
    # whose turn has not yet come up must be rejected. (Once the player
    # ahead has shown or mucked, the next player can act.)
    Given a hand at showdown with players_to_show order "player-A,player-B,player-C"
    When I handle a RevealCards command for player "player-B" with muck false
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message contains "out of order"

  @EU-1124
  Scenario: A muck advances the showdown to the next player in order
    # When the leading player mucks (without showing), the next player in
    # players_to_show becomes the active showdown player. They may show or
    # muck in turn.
    Given a hand at showdown with players_to_show order "player-A,player-B,player-C"
    When I handle a RevealCards command for player "player-A" with muck true
    Then the result is a angzarr_client.proto.examples.CardsMucked event
    And the next showdown player is "player-B"
