# Allocated: EU-1520 .. EU-1529
Feature: The deterministic shoe
  # Rule: AHR-3
  Every table shuffles its shoe from a seed, and every implementation of the
  example must produce exactly the same card order from the same seed. That
  makes rounds reproducible in tests, lets a cluster scenario name a seed
  that is known to deal a blackjack, and lets six languages prove they agree
  card for card. The shuffle is pinned in cards.proto: SplitMix64 drives a
  descending Fisher–Yates shuffle through unbiased bounded draws.

  The recorded order is part of the ShoeShuffled event, so replaying a table
  never re-runs the shuffle; these vectors guard the moment a shoe is made.

  Cards are written rank then suit: A, 2..10, J, Q, K and ♣ ♦ ♥ ♠.

  @EU-1520
  Scenario Outline: A seed always produces the same shoe
    When a shoe of <decks> decks is shuffled with seed <seed>
    Then the first 12 cards dealt are "<first_twelve>"
    And the last card dealt is "<last>"

    Examples:
      | seed | decks | first_twelve                                  | last |
      | 1    | 1     | 7♦ 9♣ 4♦ 8♥ 8♦ 5♠ J♦ 6♦ 9♠ J♣ 5♦ K♦           | 7♠   |
      | 42   | 1     | 7♣ 3♥ K♣ A♠ 2♠ A♣ A♥ K♦ 10♦ 5♣ 8♠ J♥          | 10♣  |
      | 7    | 1     | 4♦ 5♣ J♥ 3♠ 4♥ 10♥ K♠ 6♦ 4♠ 7♥ 9♦ 2♣          | Q♣   |
      | 1    | 6     | 6♠ A♣ 7♥ 3♣ 6♠ J♥ 3♥ Q♠ Q♣ 6♥ 6♦ 7♦           | 7♠   |
      | 42   | 6     | 7♠ K♠ 2♦ Q♣ 7♣ 7♥ 3♣ 7♥ 6♣ 7♦ 7♠ 4♦           | 10♣  |
      | 7    | 6     | A♦ K♣ 4♦ 3♦ 9♣ 6♣ K♦ J♠ Q♠ J♦ A♥ 8♣           | Q♣   |

  @EU-1521
  Scenario: The complete one-deck shoe for seed 1
    When a shoe of 1 deck is shuffled with seed 1
    Then the shoe deals in this order:
      | cards | in order                                     |
      | 1-13  | 7♦ 9♣ 4♦ 8♥ 8♦ 5♠ J♦ 6♦ 9♠ J♣ 5♦ K♦ 3♣       |
      | 14-26 | 2♦ J♥ 5♥ 7♥ 4♥ 2♣ A♦ 6♠ K♣ K♥ 10♥ 10♠ J♠    |
      | 27-39 | 10♦ 8♠ Q♣ 4♠ 6♣ 7♣ A♠ 5♣ A♥ K♠ 6♥ Q♠ Q♥     |
      | 40-52 | Q♦ 9♦ 3♦ 3♠ A♣ 4♣ 2♥ 8♣ 10♣ 3♥ 2♠ 9♥ 7♠     |

  @EU-1522
  Scenario Outline: A shuffled shoe holds every card once per deck
    When a shoe of <decks> decks is shuffled with seed <seed>
    Then the shoe holds <cards> cards
    And every one of the 52 cards appears exactly <decks> times

    Examples:
      | seed | decks | cards |
      | 1    | 1     | 52    |
      | 42   | 6     | 312   |
      | 7    | 8     | 416   |

  @EU-1523
  Scenario Outline: Each new shoe's seed follows from the previous shoe's seed
    Given a shoe was shuffled with seed <seed>
    When the next shoe is needed
    Then the next shoe is shuffled with seed <next_seed>

    Examples:
      | seed | next_seed            |
      | 1    | 10451216379200822465 |
      | 42   | 13679457532755275413 |
      | 7    | 7191089600892374487  |

  @EU-1524
  Scenario Outline: The random source matches the published SplitMix64 reference
    When the random source starts from seed <seed>
    Then its first three values are <first> <second> <third>

    Examples:
      | seed    | first                | second               | third                |
      | 1234567 | 6457827717110365317  | 3203168211198807973  | 9817491932198370423  |
      | 1       | 10451216379200822465 | 13757245211066428519 | 17911839290282890590 |

  @EU-1525
  Scenario: A bounded draw discards values that would bias the result
    # Only bounds near 2^64 discard values often enough to observe; with
    # bound 9223372036854775809 the 4th and 5th raw values from seed 1 fall
    # below the threshold and are redrawn.
    Given the random source starts from seed 1
    When five values below 9223372036854775809 are drawn
    Then the draws are:
      | draw | value               |
      | 1    | 1227844342346046656 |
      | 2    | 4533873174211652710 |
      | 3    | 8688467253428114781 |
      | 4    | 4849545566009754239 |
      | 5    | 6960854651289091236 |
