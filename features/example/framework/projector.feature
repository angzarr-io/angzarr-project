# Allocated: EU-0500 .. EU-0530
Feature: Game display rendering
  Game events are rendered as human-readable text for observers. The display
  builds up a running narrative of the game without coupling the game logic
  to any specific output format.

  # Why this exists:
  # - Aggregates focus on business rules, not presentation
  # - The same game can drive multiple displays (text, JSON, WebSocket)
  # - The display can evolve independently of the game itself

  # What this display demonstrates:
  # - Names of registered players appear in the running narrative
  # - Cards, blinds, and actions each render in a clear, consistent style
  # - Unfamiliar events do not crash the display

  # ==========================================================================
  # Player Event Rendering
  # ==========================================================================
  # Player events establish context (names, balances) used throughout
  # the game display.

  @EU-0500
  Scenario: A registered player appears in the display
    Given the game display
    When Alice registers
    Then the display shows "Alice registered"

  @EU-0501
  Scenario: A deposit appears in the display with the new balance
    Given the game display
    When Alice deposits 1000 chips bringing her balance to 1000
    Then the display shows "$1,000"
    And the display shows "balance: $1,000"

  @EU-0502
  Scenario: A withdrawal appears in the display
    Given the game display
    When Alice withdraws 500 chips bringing her balance to 500
    Then the display shows "Withdrew $500"

  @EU-0503
  Scenario: A reservation appears in the display
    Given the game display
    When Alice reserves 200 chips
    Then the display shows "Reserved $200"

  # ==========================================================================
  # Table Event Rendering
  # ==========================================================================
  # Table events describe the game structure: table creation, player seating,
  # and hand lifecycle.

  @EU-0504
  Scenario: A newly created table appears in the display
    Given the game display
    When a table is created with:
      | table_name | game_variant   | small_blind | big_blind | min_buy_in | max_buy_in |
      | Main Table | TEXAS_HOLDEM   | 5           | 10        | 200        | 1000       |
    Then the display shows "Main Table"
    And the display shows "TEXAS_HOLDEM"
    And the display shows "$5/$10"
    And the display shows "$200 - $1,000"

  @EU-0505
  Scenario: A player joining a table appears in the display
    Given the game display knows Bob
    When Bob joins at seat 3 with a buy-in of 500
    Then the display shows "Bob joined at seat 3"
    And the display shows "$500"

  @EU-0506
  Scenario: A player leaving a table appears in the display
    Given the game display knows Bob
    When Bob leaves cashing out 750 chips
    Then the display shows "Bob left"
    And the display shows "$750"

  @EU-0507
  Scenario: The start of a hand appears in the display
    Given the game display
    When hand 5 starts with dealer at seat 2 and blinds 5/10
    And the active players are "Alice", "Bob", "Charlie" at seats 0, 1, 2
    Then the display shows "HAND #5"
    And the display shows "Dealer: Seat 2"
    And the display shows "Alice"
    And the display shows "Bob"
    And the display shows "Charlie"

  @EU-0508
  Scenario: The end of a hand appears in the display with results
    Given the game display knows Alice and Bob
    When the hand ends with Alice winning 100
    Then the display shows "Alice wins $100"

  # ==========================================================================
  # Hand Event Rendering
  # ==========================================================================
  # Hand events are the most frequent and detailed. Each betting action,
  # community card, and showdown reveal needs clear, consistent formatting.

  @EU-0509
  Scenario: Dealt hole cards appear in the display
    Given the game display knows Alice
    When Alice is dealt As Kh
    Then the display shows "Alice: [As Kh]"

  @EU-0510
  Scenario: A posted blind appears in the display
    Given the game display knows Alice
    When Alice posts the small blind of 5
    Then the display shows "Alice posts SMALL $5"

  @EU-0511
  Scenario: A fold appears in the display
    Given the game display knows Alice
    When Alice folds
    Then the display shows "Alice folds"

  @EU-0512
  Scenario: A call appears in the display with the pot total
    Given the game display knows Alice
    When Alice calls 10 making the pot 25
    Then the display shows "Alice calls $10"
    And the display shows "pot: $25"

  @EU-0513
  Scenario: A raise appears in the display
    Given the game display knows Alice
    When Alice raises to 30 making the pot 55
    Then the display shows "Alice raises to $30"

  @EU-0514
  Scenario: An all-in appears in the display
    Given the game display knows Alice
    When Alice goes all-in for 500 making the pot 600
    Then the display shows "Alice all-in $500"

  @EU-0515
  Scenario: The flop appears in the display
    Given the game display
    When the flop is dealt Ah Kd 7s
    Then the display shows "Flop: [Ah Kd 7s]"
    And the display shows "Board:"

  @EU-0516
  Scenario: The turn appears in the display
    Given the game display
    When the turn is dealt 2c
    Then the display shows "Turn: [2c]"

  @EU-0517
  Scenario: The start of the showdown appears in the display
    Given the game display
    When the showdown begins
    Then the display shows "SHOWDOWN"

  @EU-0518
  Scenario: Revealed cards appear in the display with the ranking
    Given the game display knows Alice
    When Alice reveals As Ad with a pair
    Then the display shows "Alice shows [As Ad]"
    And the display shows "Pair"

  @EU-0519
  Scenario: Mucked cards appear in the display
    Given the game display knows Alice
    When Alice mucks her cards
    Then the display shows "Alice mucks"

  @EU-0520
  Scenario: A pot award appears in the display
    Given the game display knows Alice
    When Alice wins a pot of 150
    Then the display shows "Alice wins $150"

  @EU-0521
  Scenario: The final stacks at the end of a hand appear in the display
    Given the game display knows Alice and Bob
    When the hand finishes with final stacks:
      | player | stack | has_folded |
      | Alice  | 600   | false      |
      | Bob    | 400   | true       |
    Then the display shows "Final stacks"
    And the display shows "Alice: $600"
    And the display shows "Bob: $400 (folded)"

  @EU-0522
  Scenario: A timeout and its automatic action appear in the display
    Given the game display knows Alice
    When Alice times out and is auto-folded
    Then the display shows "Alice timed out"
    And the display shows "auto folds"

  # ==========================================================================
  # Card Formatting
  # ==========================================================================
  # Cards use standard short notation: rank letter or digit, then suit letter.

  @EU-0523
  Scenario: Every suit renders with its short letter
    Given the game display
    When cards are shown for each suit:
      | suit     | rank |
      | CLUBS    | 14   |
      | DIAMONDS | 13   |
      | HEARTS   | 12   |
      | SPADES   | 11   |
    Then the display shows "Ac Kd Qh Js"

  @EU-0524
  Scenario: Every rank renders with its short symbol
    Given the game display
    Then a 2 displays as "2"
    And a 9 displays as "9"
    And a 10 displays as "T"
    And a Jack displays as "J"
    And a Queen displays as "Q"
    And a King displays as "K"
    And an Ace displays as "A"

  # ==========================================================================
  # Player Name Resolution
  # ==========================================================================
  # The display remembers the friendly name of each player from when they
  # registered, and uses that name everywhere instead of a raw identifier.

  @EU-0525
  Scenario: A registered player is shown by name
    Given the game display
    And player "player-abc123" is registered as "Alice"
    When an event references "player-abc123"
    Then the display uses "Alice"

  @EU-0526
  Scenario: An unknown player is shown by a short fallback label
    Given the game display
    When an event references an unknown player "player-xyz789"
    Then the display falls back to a short label starting with "Player_xyz789"

  # ==========================================================================
  # Timestamp Display
  # ==========================================================================
  # Timestamps are useful for debugging but can clutter normal output. The
  # display can be configured to include or omit them.

  @EU-0527
  Scenario: Timestamps appear when enabled
    Given the game display with timestamps enabled
    When an event happens at 14:30:00
    Then the display line starts with "[14:30:00]"

  @EU-0528
  Scenario: Timestamps are omitted when disabled
    Given the game display with timestamps disabled
    When an event happens
    Then the display line does not start with "[14:"

  # ==========================================================================
  # Event Batch Processing
  # ==========================================================================
  # A single business action often produces several events. The display
  # renders them all, in order, and degrades gracefully when an event is
  # something the display does not recognise.

  @EU-0529
  Scenario: A batch of events is rendered in order
    Given the game display
    When a batch of a PlayerJoined and a BlindPosted event is rendered
    Then both events appear in the display in order

  @EU-0530
  Scenario: An unfamiliar event is indicated gracefully
    Given the game display
    When the display encounters an unfamiliar event
    Then the display shows "[Unknown event type:"
