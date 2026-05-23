# Allocated: EU-0300 .. EU-0399
Feature: Cross-domain event translations
  When one part of the game finishes a step, other parts need to react. A
  hand starting at a table means cards must be dealt. A hand finishing
  means the table can move on and the winners' bankrolls must be credited.
  These translations happen automatically without players or tables
  knowing about each other.

  # Why this exists:
  # - Players, tables, and hands each own their own rules
  # - When something happens in one area, the right follow-up should happen elsewhere
  # - A failure in one follow-up should not block unrelated follow-ups
  # - New reactions can be added without changing existing rules

  # Why poker exercises this well:
  # - Clear separation: a player owns money, a table owns seating, a hand owns gameplay
  # - Obvious follow-ups: starting a hand means dealing cards; awarding a pot means crediting a player
  # - One event can trigger multiple follow-ups in different areas
  # - Rejected actions must release the funds they reserved

  # The translators exercised here:
  # - table-to-hand translator: a hand starting at a table triggers card dealing;
  #   a hand finishing triggers the table to wrap up the round
  # - hand-to-player translator: pot awards credit winners; hand-end releases
  #   the chips back to the participants' bankrolls

  # ==========================================================================
  # Table-to-Hand Translations
  # ==========================================================================
  # When a table starts a hand, the hand is dealt. When the hand finishes,
  # the table is told to end the round.

  @wip
  @EU-0300
  Scenario: When a hand starts at a table, cards are dealt
    Given a hand "hand-1" begins as hand number 1 with TEXAS_HOLDEM and dealer at position 0
    And the active players are:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    When the hand-start is translated for the hand
    Then the hand is dealt as hand number 1 with TEXAS_HOLDEM for 2 players
    # The deal is reproducible from the hand's identifier, so acceptance
    # tests can assert specific cards across runs.
    And the deal is reproducible from the hand's identifier

  @wip
  @EU-0301
  Scenario: When a hand finishes, the table is told to end the round
    Given a hand at table "table-1" completes with pot total 100
    And the winners are:
      | player_root | amount |
      | player-1    | 100    |
    When the hand-completion is translated for the table
    Then the table ends the round with 1 result
    And the result records "player-1" winning 100

  # ==========================================================================
  # Hand-to-Player Translations
  # ==========================================================================
  # When a hand ends or pots are awarded, players' bankrolls need updating.

  @wip
  @EU-0302
  Scenario: When a hand ends, each participant's reserved chips are released
    Given hand "hand-1" ends with the following stack changes:
      | player_root | change |
      | player-1    | 50     |
      | player-2    | -50    |
    When the hand-end is translated for the players
    Then 2 players have their reserved chips released

  @wip
  @EU-0303
  Scenario: When a pot is awarded, each winner's bankroll is credited
    Given a pot of 100 is awarded with winners:
      | player_root | amount |
      | player-1    | 60     |
      | player-2    | 40     |
    When the pot-award is translated for the players
    Then 2 players receive deposits
    And "player-1" is credited 60
    And "player-2" is credited 40

  # ==========================================================================
  # Translation Dispatch
  # ==========================================================================
  # An event only triggers the translators that care about it. Unrelated
  # translators are not invoked, and a failure in one translator does not
  # prevent the others from running.

  @EU-0304
  Scenario: An event only triggers the translators that care about it
    Given both the table-to-hand and hand-to-player translators are active
    And a hand-start event occurs
    When the event is processed
    Then only the table-to-hand translator reacts

  @EU-0305
  Scenario: A sequence of events is translated in order
    Given the table-to-hand translator is active
    And the following events occur in order:
      | event_type   |
      | HandStarted  |
      | HandStarted  |
    When the events are processed
    Then 2 hands are dealt

  @EU-0306
  Scenario: A failing translator does not prevent others from running
    Given a failing translator is active alongside the table-to-hand translator
    And a hand-start event occurs
    When the event is processed
    Then the table-to-hand translator still reacts
    And no error escapes to the caller

  # ==========================================================================
  # Edge Cases on the Original Translators
  # ==========================================================================
  # Empty or no-op inputs must not crash. Zero-change participants are still
  # released so their reservation is cleared.

  @wip
  @EU-0307
  Scenario: A hand ending with no participants releases nothing
    Given hand "hand-1" ends with no stack changes
    When the hand-end is translated for the players
    Then no chips are released

  @wip
  @EU-0308
  Scenario: A hand ending releases every participant, even those with no net change
    Given hand "hand-1" ends with the following stack changes:
      | player_root | change |
      | player-1    | 100    |
      | player-2    | 0      |
    When the hand-end is translated for the players
    Then 2 players have their reserved chips released

  # ==========================================================================
  # End-to-End Translation Through the Production Dispatcher
  # ==========================================================================
  # These scenarios exercise the same translations through the dispatcher
  # used in production, with explicit destinations for the resulting actions.

  @EU-0309
  Scenario: A hand starting at a table results in the hand being dealt
    Given the table-to-hand-start translator is registered
    And a hand "hand-1" begins as hand number 1 with TEXAS_HOLDEM and dealer at position 0
    And the active players are:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    When the event is processed for the hand
    Then the hand is dealt as hand number 1 with TEXAS_HOLDEM for 2 players

  @EU-0310
  Scenario: A hand completing results in the table being told to end the round
    Given the table-to-hand-complete translator is registered
    And a hand at table "table-1" completes
    And the winners are:
      | player_root | amount |
      | player-1    | 100    |
    When the event is processed for the table
    Then the table ends the round with 1 result for "player-1" with amount 100

  @EU-0311
  Scenario: A hand ending results in each participant's reserved chips being released
    Given the hand-results translator is registered
    And hand "hand-1" ends with the following stack changes:
      | player_root | change |
      | player-1    | 50     |
      | player-2    | -50    |
    When the event is processed for the players
    Then 2 players have their reserved chips released

  @EU-0312
  Scenario: A pot award results in each winner's bankroll being credited
    Given the hand-payout translator is registered
    And a pot of 100 is awarded with winners:
      | player_root | amount |
      | player-1    | 60     |
      | player-2    | 40     |
    When the event is processed for the players
    Then 2 players receive deposits
    And the first deposit credits "player-1" with 60
    And the second deposit credits "player-2" with 40

  @EU-0313
  Scenario: When several translators are registered, only those matching the event react
    Given the table-to-hand-start, hand-results, and hand-payout translators are registered
    And a hand "hand-1" begins as hand number 1 with TEXAS_HOLDEM and dealer at position 0
    And the active players are:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
    When the event is processed for the hand, table, and players
    Then only the hand is dealt

  @EU-0314
  Scenario: A hand ending with no participants results in no releases
    Given the hand-results translator is registered
    And hand "hand-1" ends with no stack changes
    When the event is processed for the players
    Then no action results

  @EU-0315
  Scenario: A hand ending releases every participant including those with no net change
    Given the hand-results translator is registered
    And hand "hand-1" ends with the following stack changes:
      | player_root | change |
      | player-1    | 100    |
      | player-2    | 0      |
    When the event is processed for the players
    Then 2 players have their reserved chips released

  # ==========================================================================
  # Translation Edge Cases — Empty Inputs and Detail Propagation
  # ==========================================================================
  # An empty player list still leads to a deal (just with no players). An
  # empty winners list leads to a no-op end-of-round. Winning-hand details
  # carry through to the result so the table can record how the hand was won.

  @EU-0316
  Scenario: A hand starting with no active players is still dealt with no players
    Given the table-to-hand-start translator is registered
    And a hand "hand-1" begins as hand number 1 with TEXAS_HOLDEM and dealer at position 0
    And there are no active players
    When the event is processed for the hand
    Then the hand is dealt as hand number 1 with TEXAS_HOLDEM for 0 players

  @EU-0317
  Scenario: A hand completing with no winners is still ended at the table with no results
    Given the table-to-hand-complete translator is registered
    And a hand at table "table-1" completes
    And there are no winners
    When the event is processed for the table
    Then the table ends the round with no results

  @EU-0318
  Scenario: The winning hand detail is carried through to the table's end-of-round result
    Given the table-to-hand-complete translator is registered
    And a hand at table "table-1" completes
    And the winners include winning-hand detail:
      | player_root | amount |
      | player-1    | 999    |
    When the event is processed for the table
    Then the table's first end-of-round result records the winning hand

  @EU-0319
  Scenario: A pot award with no winners credits nobody
    Given the hand-payout translator is registered
    And a pot of 0 is awarded with no winners
    When the event is processed for the players
    Then no action results

  @EU-0320
  Scenario: A pot award with a single winner credits that winner
    Given the hand-payout translator is registered
    And a pot of 500 is awarded with winners:
      | player_root | amount |
      | player-1    | 500    |
    When the event is processed for the players
    Then 1 player receives a deposit
    And "player-1" is credited 500
