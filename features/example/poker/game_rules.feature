# Allocated: EU-0700 .. EU-0740 (in use: 0700..0728, 0729..0732, 0733..0738),
#            EU-0750 .. EU-0760 (stud variants)

Feature: Game rules (Texas Hold'em, Omaha, Five Card Draw, Stud)
  The game_rules module defines polymorphic rule objects for each poker
  variant. Each rule object knows how many hole cards to deal, what the
  valid phase transitions are, and how to evaluate a 5-card poker hand
  from the available cards. These are pure functions — no aggregate state,
  no commands, no events.

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  # Hand-evaluation scenarios cite Robert's Rules §1 (universal hand
  # hierarchy: royal flush > straight flush > four of a kind > full house
  # > flush > straight > three of a kind > two pair > one pair > high card).
  # Variant scenarios cite WSOP Section IX game format definitions and
  # TDA-RP-10 (stud), with Robert's §SC Hold'em / §SC Omaha / §SC Draw /
  # §SC Stud / §RAZZ filling in tiebreaks the TDA delegates to "house."
  # See features/example/RULES.md for the full rule cross-reference.

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
  # Rule: WSOP §IX (2025) — variant definitions for Hold'em / Omaha / Draw.
  #       Robert's §SC Hold'em / §SC Omaha / §SC Draw — hole-card counts.
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
  # Rule: WSOP §IX Texas Hold'em / Omaha (2025) — preflop/flop/turn/river.
  #       WSOP §IX Draw Games — single-draw / triple-draw structures.
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
  # Rule: Robert's Rules §1 (Ciaffone v11) — universal 10-rank hand
  #       hierarchy: royal flush > straight flush > four of a kind > full
  #       house > flush > straight > three of a kind > two pair > one pair
  #       > high card.
  # Rule: Robert's §SC Hold'em — best 5-card hand from any combination of
  #       the 7 available cards (2 hole + 5 community).
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
  Scenario: Texas Hold'em one pair carries the three highest remaining kickers
    # Real poker: PAIR tiebreaks on (pair_rank, k1, k2, k3) where k1..k3 are
    # the *highest* three remaining cards. Best 5 from "Ts Th 2 4 6 8 Q" is
    # TT + Q + 8 + 6 — not TT + 6 + 4 + 2 (the legacy "first combo wins"
    # implementation pinned the wrong kickers).
    Given Texas Hold'em rules
    And hole cards "Ts Th"
    And community cards "2d 4c 6s 8h Qd"
    When the best hand is evaluated
    Then the rank is PAIR
    And the score is 2010000
    And the kickers are 12, 8, 6

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
  # Rule: Robert's §SC Omaha-1 (Ciaffone v11) — "All the rules of holdem
  #       apply to Omaha except the rule on playing the board, which is
  #       not possible in Omaha (because you must use two cards from your
  #       hand and three cards from the board)."
  # Rule: WSOP §IX Omaha (2025) — same.
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
  # Rule: Robert's §SC Draw / WSOP §IX Draw Games — best 5-card hand from
  #       the player's 5 hole cards; no community cards.

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
  # Rule: Robert's Rules §1 (Ciaffone v11) — universal: ace-to-five (the
  #       "wheel") ranks as a 5-high straight; suited it is the lowest
  #       possible straight flush ("steel wheel").

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
  # Rule: WSOP §IX Draw Games (2025) — discard/draw mechanics; "If a
  #       Participant wishes to draw an entirely new hand, the Participant
  #       will receive all five cards consecutively."
  # Rule: TDA RP-17 (2024) — limping allowed in single-draw games.
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
  # (Framework: 52-card deck construction + deterministic shuffle. Backs
  # all variants. Not a poker rule — supports the rules above.)

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
  # (Framework: variant→rules-class dispatch. Not a poker rule itself —
  # this is the polymorphism backbone that lets the Hand aggregate run any
  # of the variants whose rules ARE codified above.)
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
  # Rule: Robert's Rules §1 (Ciaffone v11) — universal hand hierarchy is
  #       encoded in the score formula: each rank category occupies a
  #       distinct score range so any higher-rank hand always outscores
  #       any lower-rank hand regardless of kickers.
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
  # Rule: Robert's §31 (Ciaffone v11) — within a rank class, primary-rank
  #       ordering applies (e.g. higher straight > lower straight; full
  #       house with higher trip > full house with lower trip).
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
  # Rule: Robert's §31 (Ciaffone v11) — when primary ranks tie, the highest
  #       remaining card(s) decide the winner.
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

  # ==========================================================================
  # Stud variants — Seven Card Stud, Stud Hi/Lo (8 or better), Razz
  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this section)
  #   TDA       = Poker Tournament Directors Association Rules, 2024 v1.0
  #   TDA-RP    = TDA Recommended Procedures (longform addendum)
  #   WSOP      = WSOP Official Tournament Rules, 2025 (Section IX)
  #   Robert's  = Robert's Rules of Poker, Bob Ciaffone v11
  #
  # Stud is fundamentally different from board games:
  #   - No community cards. Each player has their own 7 cards.
  #   - Forced bets are ANTE + BRING-IN, not blinds.
  #   - Initial deal is 3 cards: 2 down + 1 up (the "door card").
  #   - Streets 4, 5, 6 each deal 1 up card; 7th street deals 1 down card.
  #   - First-to-act on 3rd street is the LOW card by rank-then-suit (high
  #     stud) or HIGH card by rank-then-suit (razz).
  #   - First-to-act on subsequent streets is the HIGH hand showing (high
  #     stud / stud-8) or LOW hand showing (razz).
  #   - In Razz, A is low, straights and flushes don't count, best is wheel.
  #   - Stud Hi/Lo (8 or better) splits the pot between best high and best
  #     qualifying low (5 cards 8-or-lower, no pair).
  #
  # Why "hole_count" doesn't apply:
  #   The board-game "hole_count" + "phases" schema (EU-0700) doesn't fit
  #   stud. Stud variants expose initial_deal_count (3), total_card_count
  #   (7), forced_bet_type (ANTE_AND_BRINGIN), and phase list separately.

  @EU-0750
  Scenario Outline: Stud variant exposes the correct static properties
    # Rule: TDA-RP-10 (2024) — stud format definitions.
    # Rule: WSOP Section IX, Seven Card Games (2025).
    Given <variant> rules
    Then the variant is "<variant_name>"
    And the initial_deal_count is 3
    And the total_card_count is 7
    And the forced_bet_type is "ANTE_AND_BRINGIN"
    And has_community_cards is False
    And the phases are "<phases>"

    Examples:
      | variant                    | variant_name              | phases                                                                              |
      | Seven Card Stud            | SEVEN_CARD_STUD           | THIRD_STREET,FOURTH_STREET,FIFTH_STREET,SIXTH_STREET,SEVENTH_STREET,SHOWDOWN        |
      | Seven Card Stud Hi/Lo 8b   | STUD_HI_LO_8B             | THIRD_STREET,FOURTH_STREET,FIFTH_STREET,SIXTH_STREET,SEVENTH_STREET,SHOWDOWN        |
      | Razz                       | RAZZ                      | THIRD_STREET,FOURTH_STREET,FIFTH_STREET,SIXTH_STREET,SEVENTH_STREET,SHOWDOWN        |

  @EU-0751
  Scenario Outline: Stud advances through streets one card at a time
    # Rule: WSOP Section IX, Seven Card Games (2025) — "two down cards followed
    #       by one up card to start the hand. There are then three more
    #       up-cards and a final down card, with a betting round after each."
    Given Seven Card Stud rules
    When I get the next phase from <current>
    Then the next phase is <next_phase>
    And the per-player cards to deal is <deal>
    And the dealt card is_up is <is_up>

    Examples:
      | current        | next_phase     | deal | is_up |
      | THIRD_STREET   | FOURTH_STREET  | 1    | True  |
      | FOURTH_STREET  | FIFTH_STREET   | 1    | True  |
      | FIFTH_STREET   | SIXTH_STREET   | 1    | True  |
      | SIXTH_STREET   | SEVENTH_STREET | 1    | False |
      | SEVENTH_STREET | SHOWDOWN       | 0    | False |

  @EU-0752
  Scenario: Stud has no community cards; players hold their own 7
    # Rule: WSOP Section IX, Seven Card Games (2025) — no community cards.
    Given Seven Card Stud rules
    When I check community card support
    Then has_community_cards is False
    And total_card_count is 7

  @EU-0753
  Scenario Outline: 3rd-street bring-in is the low card by rank-then-suit (Stud high)
    # Rule: WSOP §Seven Card Stud (2025) — "the lowest card by rank and suit."
    # Rule: TDA-RP-10D (2024) — tiebreak by suit.
    # Suit ranking high→low: spades, hearts, diamonds, clubs.
    # Among the listed up-cards, the lowest by rank-then-suit is the
    # bring-in. With "2c, 2d, 5h" the lowest is 2c (clubs is lowest suit).
    Given Seven Card Stud rules
    And players have door cards "<door_cards>"
    When I determine the bring-in
    Then the bring-in player is at index <bring_in_index>

    Examples:
      | door_cards       | bring_in_index |
      | 2c 2d 5h         | 0              |
      | 5s 4s 3c         | 2              |
      | Th Ks Qd 9c      | 3              |
      | 2d 2h 2s 2c      | 3              |

  @EU-0754
  Scenario Outline: Razz 3rd-street bring-in is the high card by rank-then-suit
    # Rule: WSOP §Seven Card Razz (2025) — "the high card, with the king of
    #       spades being the highest card by rank and suit, is required to
    #       make the forced bet on the first round."
    Given Razz rules
    And players have door cards "<door_cards>"
    When I determine the bring-in
    Then the bring-in player is at index <bring_in_index>

    Examples:
      | door_cards       | bring_in_index |
      | 2c 5h Kd Ah      | 2              |
      | Ks Kh Kd Kc      | 0              |
      | Ah As Ad Ac      | 1              |

  @EU-0755
  Scenario: Stud high — first-to-act on 4th street and beyond is the high hand showing
    # Rule: WSOP §Seven Card Stud (2025) — "On subsequent betting rounds,
    #       the high hand on board initiates the action, a tie is broken by
    #       high card by suit."
    Given Seven Card Stud rules
    And up cards by player:
      | player | up_cards     |
      | Alice  | 2h           |
      | Bob    | Kc           |
      | Carol  | 5d           |
    When I determine the first-to-act on 4th street
    Then the first-to-act player is "Bob"

  @EU-0756
  Scenario: Razz — first-to-act on 4th street and beyond is the low hand showing
    # Rule: WSOP §Seven Card Razz (2025) — "The low hand acts first on all
    #       subsequent rounds."
    Given Razz rules
    And up cards by player:
      | player | up_cards     |
      | Alice  | 2h           |
      | Bob    | Kc           |
      | Carol  | 5d           |
    When I determine the first-to-act on 4th street
    Then the first-to-act player is "Alice"

  @EU-0757
  Scenario Outline: Seven Card Stud hand evaluation — best 5 of 7 standard ranking
    # Rule: Robert's Rules §1 (Ciaffone v11) — universal high hand hierarchy.
    Given Seven Card Stud rules
    And player cards "<seven>"
    When the best high hand is evaluated
    Then the rank is <rank>

    Examples:
      | seven                          | rank             |
      | Ks Kh Kd Kc 5s 6h 7d           | FOUR_OF_A_KIND   |
      | As Ad 8s 8h 8d 4c 2h           | FULL_HOUSE       |
      | Ah 7h 5h 3h 2h Kd 9c           | FLUSH            |
      | 9s 8h 7d 6c 5s 2h Kd           | STRAIGHT         |
      | Js Jc Jh 8d 7c 5s 2h           | THREE_OF_A_KIND  |
      | Ts Th 7h 7d 5s 4c 2h           | TWO_PAIR         |
      | Ah Ac Kd Js 9h 4c 2d           | PAIR             |

  @EU-0758
  Scenario: Razz hand evaluation — wheel A-2-3-4-5 is the best possible hand
    # Rule: WSOP §Seven Card Razz (2025) — "the best possible hand is
    #       5-4-3-2-A". Aces are low; straights and flushes don't count.
    Given Razz rules
    And player cards "Ah 2h 3h 4h 5h Kc Qd"
    When the best low hand is evaluated
    Then the razz rank is "WHEEL"
    And the razz rank value is 1

  @EU-0759
  Scenario: Razz tiebreak — among non-wheel lows, compare highest card downward
    # Rule: WSOP §Seven Card Razz (2025) — "Aces are low only, and two aces
    #       are the lowest pair." Among non-paired/non-flush 5-card lows,
    #       the lower hand is the one with the lower highest card; ties
    #       broken by next-highest, etc.
    # Hand A: best 5 = 7-5-4-3-2 (a "seven low")
    # Hand B: best 5 = 8-5-4-3-2 (an "eight low") — A wins, lower top card.
    Given Razz rules
    When I evaluate hand A with cards "7h 5d 4c 3s 2h Kd Qc"
    And I evaluate hand B with cards "8h 5d 4c 3s 2h Kd Qc"
    Then both hands rank as razz lows
    And hand A is lower than hand B

  @EU-0760
  Scenario: Stud Hi/Lo (8 or better) — qualifier requires 5 unpaired cards each ≤ 8
    # Rule: WSOP §Seven Card Stud Hi/Lo 8 or Better (2025) — "to win the low
    #       half of the pot, a Participant's hand at showdown must have five
    #       cards of different ranks that are an eight or lower in rank."
    # Hand A: cards 9c 9d 8s 7h 6d 5c 4c — best high is the 9-high straight
    #         (9-8-7-6-5); the qualifying low is 8-7-6-5-4 (an "8-low").
    #         Note: TWO_PAIR + an 8-low qualifier is structurally impossible
    #         from 7 cards (the 5 distinct low ranks 8-7-6-5-4 are a straight,
    #         which beats two pair as the best high).
    # Hand B: cards Ks Kh 9d 7s 5c 3h 2d — high pair Ks; no low qualifier
    #         (only 4 distinct ranks ≤ 8: 7, 5, 3, 2 — need 5).
    Given Seven Card Stud Hi/Lo rules
    When I evaluate hand A with cards "9c 9d 8s 7h 6d 5c 4c"
    Then hand A high rank is "STRAIGHT"
    And hand A has a qualifying low
    And hand A low best 5 is "8 7 6 5 4"
    When I evaluate hand B with cards "Ks Kh 9d 7s 5c 3h 2d"
    Then hand B high rank is "PAIR"
    And hand B has no qualifying low
