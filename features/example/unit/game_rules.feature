# Allocated: EU-0700 .. EU-0740 (in use: 0700..0728, 0729..0732, 0733..0738)

Feature: Game rules (Texas Hold'em, Omaha, Five Card Draw)
  The game_rules module defines polymorphic rule objects for each poker
  variant. Each rule object knows how many hole cards to deal, what the
  valid phase transitions are, and how to evaluate a 5-card poker hand
  from the available cards. These are pure functions — no aggregate state,
  no commands, no events.

  # Why these rules exist:
  # - Different variants deal different numbers of hole cards
  #   (Hold'em=2, Omaha=4, Five Card Draw=5)
  # - Different variants have different phase sequences
  #   (Hold'em has FLOP/TURN/RIVER, Draw has DRAW, Omaha mirrors Hold'em)
  # - Omaha constrains hand selection (must use exactly 2 hole + 3 community)
  # - All standard poker hand rankings (high card through royal flush) must
  #   be recognised and scored for comparison
  #
  # What breaks if this is wrong:
  # - Players get the wrong number of hole cards
  # - Hand evaluation misclassifies ranks, giving pots to the wrong player
  # - Phase transitions skip community card deals
  # - get_game_rules() returns the wrong rules class
  #
  # Card-string format used by these scenarios:
  #   "<rank><suit>" per card, space-separated
  #   rank: 2..9, T (ten), J, Q, K, A
  #   suit: c (clubs), d (diamonds), h (hearts), s (spades)
  # Example: "As Ah Ks Kh" = Ace-spades, Ace-hearts, King-spades, King-hearts

  # ==========================================================================
  # Variant properties (hole-card count, phase list, variant enum)
  # ==========================================================================
  # Each rule object exposes the static properties that define the variant.
  # Collapsed into one outline — the properties are independent of any hand.

  @EU-0700
  Scenario Outline: Variant exposes the correct static properties
    Given <variant> rules
    Then the variant is "<variant_name>"
    And the hole card count is <hole_count>
    And the phases are "<phases>"

    Examples:
      | variant          | variant_name    | hole_count | phases                               |
      | Texas Hold'em    | TEXAS_HOLDEM    | 2          | PREFLOP,FLOP,TURN,RIVER,SHOWDOWN     |
      | Omaha            | OMAHA           | 4          | PREFLOP,FLOP,TURN,RIVER,SHOWDOWN     |
      | Five Card Draw   | FIVE_CARD_DRAW  | 5          | PREFLOP,DRAW,SHOWDOWN                |

  # ==========================================================================
  # Phase transitions
  # ==========================================================================
  # Each variant defines a linear sequence of betting phases. get_next_phase
  # returns the next phase plus how many community cards to deal. SHOWDOWN
  # is terminal — returns None.

  @EU-0701
  Scenario Outline: Texas Hold'em advances through phases
    Given Texas Hold'em rules
    When I get the next phase from <current>
    Then the next phase is <next_phase>
    And the community cards to deal is <deal>
    And is_showdown is <is_showdown>

    Examples:
      | current  | next_phase | deal | is_showdown |
      | PREFLOP  | FLOP       | 3    | False       |
      | FLOP     | TURN       | 1    | False       |
      | TURN     | RIVER      | 1    | False       |
      | RIVER    | SHOWDOWN   | 0    | True        |

  @EU-0702
  Scenario: Texas Hold'em SHOWDOWN has no next phase
    Given Texas Hold'em rules
    When I get the next phase from SHOWDOWN
    Then there is no next phase

  @EU-0703
  Scenario Outline: Five Card Draw advances through phases
    Given Five Card Draw rules
    When I get the next phase from <current>
    Then the next phase is <next_phase>
    And the community cards to deal is <deal>
    And is_showdown is <is_showdown>

    Examples:
      | current  | next_phase | deal | is_showdown |
      | PREFLOP  | DRAW       | 0    | False       |
      | DRAW     | SHOWDOWN   | 0    | True        |

  @EU-0704
  Scenario: Five Card Draw SHOWDOWN has no next phase
    Given Five Card Draw rules
    When I get the next phase from SHOWDOWN
    Then there is no next phase

  # ==========================================================================
  # Hand evaluation — Texas Hold'em (7-card: 2 hole + 5 community)
  # ==========================================================================
  # evaluate_hand returns (rank_type, score, kickers). Every rank category
  # in the 10-class poker hierarchy is exercised below.

  @EU-0705
  Scenario Outline: Texas Hold'em evaluates the best 5-card hand
    Given Texas Hold'em rules
    And hole cards "<hole>"
    And community cards "<community>"
    When the best hand is evaluated
    Then the rank is <rank>

    Examples:
      | hole  | community              | rank            |
      | As 2h | 3d 4c 5s 9h Td         | STRAIGHT        |
      | As Ks | Qs Js Ts 2h 3d         | ROYAL_FLUSH     |
      | Ts Th | Td Tc 5s 6h 7d         | FOUR_OF_A_KIND  |
      | 2s 4s | 6s 8s Ts Ah Kd         | FLUSH           |
      | Ts Th | Td 5c 6s 7h 8d         | THREE_OF_A_KIND |
      | Ts Th | 8d 8c 5s 6h 7d         | TWO_PAIR        |
      | Ts Th | 2d 4c 6s 8h Qd         | PAIR            |
      | As 2h | 4d 6c 8s Th Qd         | HIGH_CARD       |

  @EU-0706
  Scenario: Texas Hold'em royal flush scores 10000000
    Given Texas Hold'em rules
    And hole cards "As Ks"
    And community cards "Qs Js Ts 2h 3d"
    When the best hand is evaluated
    Then the rank is ROYAL_FLUSH
    And the score is 10000000

  @EU-0707
  Scenario: Texas Hold'em four of a kind has the highest remaining card as kicker
    # Real poker (Robert's Rules §31): with 7 cards available the kicker for
    # FOUR_OF_A_KIND is the *highest* remaining card, not the lowest. Two
    # players who both have AAAA on a board with AAAA-x are still ranked by
    # their hole-card kicker — the legacy "first combo wins" implementation
    # was a real-rule violation. Score formula must embed this kicker.
    Given Texas Hold'em rules
    And hole cards "Ts Th"
    And community cards "Td Tc 5s 6h 7d"
    When the best hand is evaluated
    Then the rank is FOUR_OF_A_KIND
    And the kickers are 7

  @EU-0708
  Scenario: Texas Hold'em two pair carries the highest remaining card as kicker
    # Real poker: TWO_PAIR ties break on (high pair, low pair, kicker). The
    # kicker is the *highest* remaining card from the 7 available. Best 5
    # from "Ts Th 8d 8c 5s 6h 7d" is TT-88-7. The legacy assertion of "5"
    # ignored the kicker entirely; pinning 7 forces the evaluator to pick
    # the highest non-pair card.
    Given Texas Hold'em rules
    And hole cards "Ts Th"
    And community cards "8d 8c 5s 6h 7d"
    When the best hand is evaluated
    Then the rank is TWO_PAIR
    And the kickers are 7

  @EU-0709
  Scenario: Texas Hold'em one pair has three kickers
    Given Texas Hold'em rules
    And hole cards "Ts Th"
    And community cards "2d 4c 6s 8h Qd"
    When the best hand is evaluated
    Then the rank is PAIR
    And the score is 2010000
    And the kickers are 6, 4, 2

  @EU-0710
  Scenario: _find_best_hand returns HIGH_CARD with score 0 for fewer than five cards
    Given Texas Hold'em rules
    When the best hand is evaluated from only "As Kh Qd Jc"
    Then the rank is HIGH_CARD
    And the score is 0

  # Boundary: exactly 5 cards. Catches `if len(cards) < 5` → `<= 5` (would
  # incorrectly return the empty default) and `< 5` → `< 6` (same issue).
  Scenario: _find_best_hand evaluates the lower boundary of exactly five cards
    Given Texas Hold'em rules
    When the best hand is evaluated from only "As Ks Qs Js Ts"
    Then the rank is ROYAL_FLUSH
    And the score is 10000000

  # ==========================================================================
  # Hand evaluation — Omaha (must use exactly 2 hole + 3 community)
  # ==========================================================================
  # Omaha's evaluation enforces that every best-hand candidate uses exactly
  # two of the four hole cards plus three of the five community cards. The
  # scenarios below check that the constraint is honoured.

  @EU-0711
  Scenario: Omaha uses two hole cards and three community cards (full house)
    Given Omaha rules
    And hole cards "As Ah Ks Kh"
    And community cards "Qs Qh Qd Tc 9c"
    When the best hand is evaluated
    Then the rank is FULL_HOUSE

  @EU-0712
  Scenario: Omaha recognises a straight flush built from two hole cards
    Given Omaha rules
    And hole cards "Ts Js 2h 3h"
    And community cards "8s 9s Qs 4h 5d"
    When the best hand is evaluated
    Then the rank is STRAIGHT_FLUSH

  @EU-0713
  Scenario: Omaha high-card when no hole pair combines for strength
    Given Omaha rules
    And hole cards "2s 4h 6d 8c"
    And community cards "As Kh Jd 9c 7s"
    When the best hand is evaluated
    Then the rank is HIGH_CARD

  # ==========================================================================
  # Hand evaluation — Five Card Draw (uses only hole cards)
  # ==========================================================================

  @EU-0714
  Scenario: Five Card Draw evaluates a pair from hole cards
    Given Five Card Draw rules
    And hole cards "Ts Th 8d 6c 4s"
    When the best hand is evaluated
    Then the rank is PAIR

  @EU-0715
  Scenario: Five Card Draw evaluates a full house from hole cards
    Given Five Card Draw rules
    And hole cards "Ts Th Td 8c 8s"
    When the best hand is evaluated
    Then the rank is FULL_HOUSE

  @EU-0716
  Scenario: Five Card Draw ignores any community cards passed in
    Given Five Card Draw rules
    And hole cards "Ah Kd Qc Js Tc"
    And community cards "Ah Ah"
    When the best hand is evaluated
    Then the rank is STRAIGHT

  # ==========================================================================
  # Edge cases: wheel straight (A-2-3-4-5) evaluates correctly
  # ==========================================================================

  @EU-0717
  Scenario: Wheel straight (A-2-3-4-5) is recognised as STRAIGHT
    Given Texas Hold'em rules
    And hole cards "As 2h"
    And community cards "3d 4c 5s 9h Td"
    When the best hand is evaluated
    Then the rank is STRAIGHT

  # ==========================================================================
  # Five Card Draw — execute_draw
  # ==========================================================================
  # The draw phase lets players discard selected hole cards and draw
  # replacements from the top of the deck. Hand size stays 5 unless the
  # deck runs out.

  @EU-0718
  Scenario: Draw replaces the selected hole cards
    Given Five Card Draw rules
    And a deck of "As Kh Qd"
    And current hole cards "2c 3c 4c 5c 6c"
    When I execute a draw discarding indices "0,1"
    Then the new hand has 5 cards
    And 2 cards were drawn
    And the remaining deck has 1 card
    And the new hand retains "4c"
    And the new hand retains "5c"
    And the new hand retains "6c"

  @EU-0719
  Scenario: Drawing zero cards keeps the existing hand unchanged
    Given Five Card Draw rules
    And a deck of "As"
    And current hole cards "Tc Jc Qc Kc Ac"
    When I execute a draw discarding indices ""
    Then the new hand equals "Tc Jc Qc Kc Ac"
    And 0 cards were drawn
    And the remaining deck has 1 card

  @EU-0720
  Scenario: Drawing all five cards replaces every hole card
    Given Five Card Draw rules
    And a deck of "Ts Js Qs Ks As"
    And current hole cards "2c 3c 4c 5c 6c"
    When I execute a draw discarding indices "0,1,2,3,4"
    Then the new hand has 5 cards
    And 5 cards were drawn
    And the remaining deck has 0 cards
    And the new hand does not contain "2c"
    # Pin actual contents so ``new_hole.append(card)`` → ``append(None)`` is caught.
    # Deck pops from end, so cards arrive in reverse: As, Ks, Qs, Js, Ts.
    And the new hand equals "As Ks Qs Js Ts"

  @EU-0721
  Scenario: Draw caps at deck size when deck is shorter than discard count
    Given Five Card Draw rules
    And a deck of "As"
    And current hole cards "2c 3c 4c 5c 6c"
    When I execute a draw discarding indices "0,1,2"
    Then the new hand has 3 cards
    And 1 cards were drawn
    And the remaining deck has 0 cards

  # ==========================================================================
  # Deck creation and dealing
  # ==========================================================================

  @EU-0722
  Scenario: A freshly created deck has 52 cards
    Given Texas Hold'em rules
    When I create a deck
    Then the deck has 52 cards

  @EU-0723
  Scenario: Deterministic seeded shuffle produces identical decks
    Given Texas Hold'em rules
    When I create a deck with seed "test_seed_value"
    And I create another deck with seed "test_seed_value"
    Then the two decks are identical

  @EU-0724
  Scenario: Dealing Omaha hole cards gives each player 4 cards
    Given Omaha rules
    When I deal hole cards to 2 players with seed "seed1234"
    Then each player has 4 hole cards
    And the remaining deck has 44 cards

  @EU-0725
  Scenario: Dealing Five Card Draw hole cards gives each player 5 cards
    Given Five Card Draw rules
    When I deal hole cards to 2 players with seed "seed1234"
    Then each player has 5 hole cards
    And the remaining deck has 42 cards

  @EU-0726
  Scenario: Dealing from an existing (non-empty) deck draws from the top
    Given Texas Hold'em rules
    And an existing deck of "As Ah Ad Ac Ks Kh"
    When I deal hole cards to 2 players from the existing deck
    Then each player has 2 hole cards
    And the remaining deck has 2 cards

  # ==========================================================================
  # get_game_rules() factory
  # ==========================================================================
  # The factory dispatches the GameVariant enum to the matching rules class.
  # Unknown variants fall through to TexasHoldemRules.

  @EU-0727
  Scenario Outline: get_game_rules returns the class for a known variant
    When I get game rules for variant <variant_enum>
    Then the rules class is <rules_class>
    And the variant is "<variant_name>"

    Examples:
      | variant_enum   | rules_class       | variant_name    |
      | TEXAS_HOLDEM   | TexasHoldemRules  | TEXAS_HOLDEM    |
      | OMAHA          | OmahaRules        | OMAHA           |
      | FIVE_CARD_DRAW | FiveCardDrawRules | FIVE_CARD_DRAW  |

  @EU-0728
  Scenario: get_game_rules falls back to Texas Hold'em for an unknown variant
    When I get game rules for an unknown variant
    Then the rules class is TexasHoldemRules

  # ==========================================================================
  # Hand evaluation — exact score per rank category
  # ==========================================================================
  # Score formulas (TexasHoldemRules._evaluate_five) embed magic offsets and
  # multipliers; without scenarios that pin the exact score, mutations that
  # swap +/- or shift constants survive silently.

  Scenario: Texas Hold'em straight flush score embeds the high-card rank
    Given Texas Hold'em rules
    And hole cards "9s 8s"
    And community cards "7s 6s 5s 2h 3d"
    When the best hand is evaluated
    Then the rank is STRAIGHT_FLUSH
    And the score is 9000009

  Scenario: Texas Hold'em full house score embeds trip rank * 100 + pair rank
    Given Texas Hold'em rules
    And hole cards "Ts Th"
    And community cards "Td 5h 5s 2c 3d"
    When the best hand is evaluated
    Then the rank is FULL_HOUSE
    And the score is 7001005

  Scenario: Texas Hold'em flush score adds rank-weighted total
    Given Texas Hold'em rules
    And hole cards "As Ks"
    And community cards "Qs Js 9s 2h 3d"
    When the best hand is evaluated
    Then the rank is FLUSH
    And the score is 6755499

  Scenario: Texas Hold'em straight score embeds high rank
    Given Texas Hold'em rules
    And hole cards "9s 8h"
    And community cards "7d 6c 5s 2h 3d"
    When the best hand is evaluated
    Then the rank is STRAIGHT
    And the score is 5000009

  Scenario: Texas Hold'em three of a kind score embeds trip rank * 1000
    Given Texas Hold'em rules
    And hole cards "Ts Th"
    And community cards "Td 5s 6h 2c 3d"
    When the best hand is evaluated
    Then the rank is THREE_OF_A_KIND
    And the score is 4010000
    And the kickers are 6, 5

  Scenario: Texas Hold'em high card score adds rank-weighted total
    Given Texas Hold'em rules
    And hole cards "As Kh"
    And community cards "Qd Jc 9s 2h 3d"
    When the best hand is evaluated
    Then the rank is HIGH_CARD
    And the score is 1755499

  Scenario: Texas Hold'em royal flush emits no kickers
    Given Texas Hold'em rules
    And hole cards "As Ks"
    And community cards "Qs Js Ts 2h 3d"
    When the best hand is evaluated
    Then the rank is ROYAL_FLUSH
    And the score is 10000000
    And the kicker count is 0

  Scenario: Texas Hold'em straight flush emits no kickers
    Given Texas Hold'em rules
    And hole cards "9s 8s"
    And community cards "7s 6s 5s 2h 3d"
    When the best hand is evaluated
    Then the rank is STRAIGHT_FLUSH
    And the kicker count is 0

  # ==========================================================================
  # Intra-class ordering (same rank category, different strength)
  # ==========================================================================
  # Same-class comparisons are where evaluators most often regress: a single
  # field swap (e.g. comparing pair rank instead of trip rank in a full house)
  # silently mis-awards pots without any rank label changing. Each scenario
  # below pins the higher hand's score above the lower hand's so a bad
  # comparator can't slip past with the same rank label.

  @EU-0729
  Scenario: Higher straight beats lower straight (A-high vs K-high)
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Ah Qh" and community "Kd Jc Ts 4h 2c"
    And I evaluate hand B with hole "Kh Qd" and community "Jc Ts 9h 4c 2s"
    Then both hands rank STRAIGHT
    And hand A score is greater than hand B score

  @EU-0730
  Scenario: Higher flush beats lower flush (A-high spades vs K-high spades)
    Given Texas Hold'em rules
    When I evaluate hand A with hole "As 7s" and community "2s 4s 6s Kc Qd"
    And I evaluate hand B with hole "Ks 7s" and community "2s 4s 6s Ac Qd"
    Then both hands rank FLUSH
    And hand A score is greater than hand B score

  @EU-0731
  Scenario: Full house tiebreak uses trip rank, not pair rank
    # JJJ-22 must beat TTT-AA: trip rank dominates pair rank. A buggy formula
    # like (pair * 100 + trip) instead of (trip * 100 + pair) would invert
    # this and silently award pots backwards.
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Jh Jd" and community "Js 2c 2h 7c 4d"
    And I evaluate hand B with hole "Ts Td" and community "Tc Ah Ad 7s 4c"
    Then both hands rank FULL_HOUSE
    And hand A score is greater than hand B score

  @EU-0732
  Scenario: Three of a kind tiebreak uses trip rank
    # KKK with low kickers beats QQQ with higher kickers — trip rank is the
    # primary tiebreaker. Catches a comparator that summed kickers before
    # weighting trip rank.
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Kh Kd" and community "Ks 4c 2h 5d 7c"
    And I evaluate hand B with hole "Qh Qd" and community "Qs Ah Jc 9d 8c"
    Then both hands rank THREE_OF_A_KIND
    And hand A score is greater than hand B score

  # ==========================================================================
  # Kicker tiebreaks (matching primary rank, different kickers)
  # ==========================================================================
  # When two hands share the same primary structure (same quads, same trips,
  # same two pair), real poker breaks the tie by the *highest* remaining
  # card. These scenarios exercise each rank category that can have kicker
  # ties — they're the cases an implementation that drops kickers will
  # silently mis-award.

  @EU-0733
  Scenario: Four of a kind with quads on board — kicker decides the winner
    # Board has AAAA. Both players have quads-aces; the higher hole-card
    # kicker wins. K beats Q.
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Kh 2c" and community "As Ah Ad Ac 5s"
    And I evaluate hand B with hole "Qh 3d" and community "As Ah Ad Ac 5s"
    Then both hands rank FOUR_OF_A_KIND
    And hand A score is greater than hand B score

  @EU-0734
  Scenario: Two pair with same pairs on board — kicker decides the winner
    # Board has KK 88 + low. Both players have two pair K-K-8-8; the higher
    # hole-card kicker wins. A-kicker beats Q-kicker.
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Ah 2c" and community "Ks Kh 8d 8c 4s"
    And I evaluate hand B with hole "Qh 3d" and community "Ks Kh 8d 8c 4s"
    Then both hands rank TWO_PAIR
    And hand A score is greater than hand B score

  @EU-0735
  Scenario: Full house tiebreak uses pair rank when trip rank is equal
    # Both players have AAA full house: A-tripped from board. Pair rank
    # decides — KK beats QQ.
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Kh Kd" and community "Ah Ad As Qc 4s"
    And I evaluate hand B with hole "Qh Qd" and community "Ah Ad As Kc 4s"
    Then both hands rank FULL_HOUSE
    And hand A score is greater than hand B score

  @EU-0736
  Scenario: Three of a kind with trips on board — kicker decides the winner
    # Board has AAA. Both players have trips-aces; higher hole-card kicker
    # wins. K beats J.
    Given Texas Hold'em rules
    When I evaluate hand A with hole "Kh 2c" and community "As Ah Ad 5c 4s"
    And I evaluate hand B with hole "Jh 3d" and community "As Ah Ad 5c 4s"
    Then both hands rank THREE_OF_A_KIND
    And hand A score is greater than hand B score

  @EU-0737
  Scenario: Steel wheel — A-2-3-4-5 of one suit is the lowest STRAIGHT_FLUSH
    # The wheel is recognised as STRAIGHT (EU-0717). Suited it is also a
    # STRAIGHT_FLUSH, ranked above all FOUR_OF_A_KIND but below higher
    # straight flushes. 5-high SF is the lowest possible STRAIGHT_FLUSH.
    Given Texas Hold'em rules
    And hole cards "As 2s"
    And community cards "3s 4s 5s 9h Td"
    When the best hand is evaluated
    Then the rank is STRAIGHT_FLUSH
    # Higher SFs (e.g. 9-high) must outrank the wheel SF.
    And the score is less than the score of "9s 8s" with community "7s 6s 5s 2h 3d"

  @EU-0738
  Scenario: Pot-limit Omaha — maximum legal bet is the size of the pot
    # PLO: a bet/raise is capped at the size of the pot after the call would
    # be made. Pot=100, current_bet=20 facing a $20 call: max raise-to is
    # 20 (call) + 100 + 20 (the call you would make, doubled) = 140 total
    # ("pot-sized raise"). Actions exceeding that are rejected.
    Given Pot-Limit Omaha rules
    And the pot is 100 and current_bet is 20
    When I compute the maximum raise-to amount
    Then the maximum raise-to is 140

    When I attempt a raise-to of 141
    Then the raise is rejected with code "EXCEEDS_POT_LIMIT"
    And the rejection field "got" equals "141"
    And the rejection field "bound" equals "140"
