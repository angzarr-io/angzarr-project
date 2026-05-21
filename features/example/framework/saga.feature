# Allocated: EU-0300 .. EU-0399
Feature: Saga logic
  Sagas translate events from one domain into commands for another. They're
  stateless domain bridges that enable loose coupling between aggregates.
  Each saga handles one direction: table→hand or hand→player.

  # Why sagas exist:
  # - Aggregates shouldn't know about each other directly
  # - Domain translation logic has a clear home
  # - Saga failures can be compensated independently
  # - Adding new sagas extends functionality without changing aggregates

  # Patterns enabled by sagas:
  # - Domain decoupling: Table doesn't import Hand types; saga translates. Same
    # pattern applies to order→fulfillment, payment→ledger, user→notification.
  # - Event-driven choreography: Events trigger sagas; sagas emit commands. No
    # central orchestrator needed. Same pattern applies to microservice integration.
  # - Fan-out reactions: One event can trigger multiple sagas targeting different
    # domains. PotAwarded triggers both player balance updates AND table state updates.

  # Why poker exercises saga patterns well:
  # - Clear domain boundaries: player (money), table (seating), hand (gameplay)
  # - Obvious translations: HandStarted→DealCards, PotAwarded→DepositFunds
  # - Multi-target fan-out: HandComplete triggers hand-player-saga AND hand-table-saga
  # - Compensation scenarios: JoinTable rejection requires FundsReleased via saga

  # The poker example sagas:
  # - table-hand-saga: table events → hand commands (HandStarted → DealCards)
  # - hand-player-saga: hand events → player commands (PotAwarded → DepositFunds)
  # - hand-table-saga: hand events → table commands (HandComplete → EndHand)

  # ==========================================================================
  # TableSyncSaga - Table to Hand Bridge
  # ==========================================================================
  # When a table starts a hand, the saga translates this into commands for
  # the hand aggregate. When a hand completes, it signals the table to end.

  @EU-0300
  Scenario: Table sync saga routes HandStarted to Shuffle + DealCards
    Given a TableSyncSaga
    And a HandStarted event from table domain with:
      | hand_root   | hand_number | game_variant   | dealer_position |
      | hand-1      | 1           | TEXAS_HOLDEM   | 0               |
    And active players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    When the saga handles the event
    # Saga emits Shuffle first (hand_root as seed for replay-
    # deterministic per-hand deck order), then DealCards.
    Then the saga emits a Shuffle command to hand domain
    And the Shuffle command has seed equal to the hand_root
    And the saga emits a DealCards command to hand domain
    And the command has game_variant TEXAS_HOLDEM
    And the command has 2 players
    And the command has hand_number 1

  @EU-0301
  Scenario: Table sync saga routes HandComplete to EndHand
    Given a TableSyncSaga
    And a HandComplete event from hand domain with:
      | table_root | pot_total |
      | table-1    | 100       |
    And winners:
      | player_root | amount |
      | player-1    | 100    |
    When the saga handles the event
    Then the saga emits an EndHand command to table domain
    And the command has 1 result
    And the result has winner "player-1" with amount 100

  # ==========================================================================
  # HandResultsSaga - Hand to Player Bridge
  # ==========================================================================
  # When a hand ends or pots are awarded, players' bankrolls need updating.
  # This saga emits DepositFunds/ReleaseFunds commands to the player domain.

  @EU-0302
  Scenario: Hand results saga routes HandEnded to ReleaseFunds
    Given a HandResultsSaga
    And a HandEnded event from table domain with:
      | hand_root |
      | hand-1    |
    And stack_changes:
      | player_root | change |
      | player-1    | 50     |
      | player-2    | -50    |
    When the saga handles the event
    Then the saga emits 2 ReleaseFunds commands to player domain

  @EU-0303
  Scenario: Hand results saga routes PotAwarded to DepositFunds
    Given a HandResultsSaga
    And a PotAwarded event from hand domain with:
      | pot_total |
      | 100       |
    And winners:
      | player_root | amount |
      | player-1    | 60     |
      | player-2    | 40     |
    When the saga handles the event
    Then the saga emits 2 DepositFunds commands to player domain
    And the first command has amount 60 for "player-1"
    And the second command has amount 40 for "player-2"

  # ==========================================================================
  # SagaRouter Infrastructure
  # ==========================================================================
  # The SagaRouter dispatches events to matching saga handlers. Multiple
  # sagas can be registered; only those matching the event type are invoked.

  @EU-0304
  Scenario: Saga router dispatches to matching sagas only
    Given a SagaRouter with TableSyncSaga and HandResultsSaga
    And a HandStarted event
    When the router routes the event
    Then only TableSyncSaga handles the event

  @EU-0305
  Scenario: Saga router handles multiple events in event book
    Given a SagaRouter with TableSyncSaga
    And an event book with:
      | event_type   |
      | HandStarted  |
      | HandStarted  |
    When the router routes the events
    Then the saga emits 2 DealCards commands

  @EU-0306
  Scenario: Saga router continues after saga failure
    Given a SagaRouter with a failing saga and TableSyncSaga
    And a HandStarted event
    When the router routes the event
    Then TableSyncSaga still emits its command
    And no exception is raised

  # ==========================================================================
  # Saga Error Handling
  # ==========================================================================
  # Sagas must handle edge cases gracefully. Empty or invalid input should
  # not cause crashes; instead, sagas emit no commands or log errors.

  @EU-0307
  Scenario: Saga handles empty player list gracefully
    Given a HandResultsSaga
    And a HandEnded event from table domain with:
      | hand_root |
      | hand-1    |
    And stack_changes:
      | player_root | change |
    When the saga handles the event
    Then the saga emits 0 ReleaseFunds commands to player domain

  @EU-0308
  Scenario: Hand results saga skips players with zero change
    Given a HandResultsSaga
    And a HandEnded event from table domain with:
      | hand_root |
      | hand-1    |
    And stack_changes:
      | player_root | change |
      | player-1    | 100    |
      | player-2    | 0      |
    When the saga handles the event
    Then the saga emits 2 ReleaseFunds commands to player domain

  # ==========================================================================
  # Unified Router API - SagaHandleRequest Dispatch (EU-0309..)
  # ==========================================================================
  # These scenarios exercise the production sagas via the unified Router
  # using SagaHandleRequest with explicit destination_sequences. This is
  # the same shape the orchestrator uses in production.

  @EU-0309
  Scenario: TableSyncStartSaga dispatched via Router emits DealCards
    Given a TableSyncStartSaga registered in a Router
    And a HandStarted event from table domain with:
      | hand_root | hand_number | game_variant | dealer_position |
      | hand-1    | 1           | TEXAS_HOLDEM | 0               |
    And active players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
      | player-2    | 1        | 500   |
    When I dispatch the event via SagaHandleRequest with destination_sequences "hand=0"
    Then the result is a angzarr_client.proto.examples.DealCards command to hand domain
    And the command DealCards has hand_number 1 and 2 players
    And the command DealCards has game_variant TEXAS_HOLDEM

  @EU-0310
  Scenario: TableSyncCompleteSaga dispatched via Router emits EndHand
    Given a TableSyncCompleteSaga registered in a Router
    And a HandComplete event from hand domain with:
      | table_root |
      | table-1    |
    And winners:
      | player_root | amount |
      | player-1    | 100    |
    When I dispatch the event via SagaHandleRequest with destination_sequences "table=0"
    Then the result is a angzarr_client.proto.examples.EndHand command to table domain
    And the EndHand command has 1 result with winner "player-1" amount 100

  @EU-0311
  Scenario: HandResultsSaga dispatched via Router emits ReleaseFunds per player
    Given a HandResultsSaga registered in a Router
    And a HandEnded event from table domain with:
      | hand_root |
      | hand-1    |
    And stack_changes:
      | player_root | change |
      | player-1    | 50     |
      | player-2    | -50    |
    When I dispatch the event via SagaHandleRequest with destination_sequences "player=0"
    Then 2 commands are emitted to player domain
    And each command is a angzarr_client.proto.examples.ReleaseFunds

  @EU-0312
  Scenario: HandPayoutSaga dispatched via Router emits DepositFunds per winner
    Given a HandPayoutSaga registered in a Router
    And a PotAwarded event from hand domain with:
      | pot_total |
      | 100       |
    And winners:
      | player_root | amount |
      | player-1    | 60     |
      | player-2    | 40     |
    When I dispatch the event via SagaHandleRequest with destination_sequences "player=0"
    Then 2 commands are emitted to player domain
    And each command is a angzarr_client.proto.examples.DepositFunds
    And DepositFunds 0 has amount 60 for "player-1"
    And DepositFunds 1 has amount 40 for "player-2"

  @EU-0313
  Scenario: Router routes table event only to sagas matching table source
    Given a Router with TableSyncStartSaga, HandResultsSaga, and HandPayoutSaga
    And a HandStarted event from table domain with:
      | hand_root | hand_number | game_variant | dealer_position |
      | hand-1    | 1           | TEXAS_HOLDEM | 0               |
    And active players:
      | player_root | position | stack |
      | player-1    | 0        | 500   |
    When I dispatch the event via SagaHandleRequest with destination_sequences "hand=0,table=0,player=0"
    Then only TableSyncStartSaga emits a DealCards command

  @EU-0314
  Scenario: HandResultsSaga emits no commands for empty stack_changes
    Given a HandResultsSaga registered in a Router
    And a HandEnded event from table domain with:
      | hand_root |
      | hand-1    |
    And stack_changes:
      | player_root | change |
    When I dispatch the event via SagaHandleRequest with destination_sequences "player=0"
    Then no commands are emitted

  @EU-0315
  Scenario: HandResultsSaga emits ReleaseFunds for all players including zero change
    Given a HandResultsSaga registered in a Router
    And a HandEnded event from table domain with:
      | hand_root |
      | hand-1    |
    And stack_changes:
      | player_root | change |
      | player-1    | 100    |
      | player-2    | 0      |
    When I dispatch the event via SagaHandleRequest with destination_sequences "player=0"
    Then 2 commands are emitted to player domain
    And each command is a angzarr_client.proto.examples.ReleaseFunds

  # ==========================================================================
  # Saga Edge Cases — Empty Inputs and Field Propagation
  # ==========================================================================
  # Empty trigger inputs must still produce sensible outputs: the
  # TableSync saga emits one command even when its lists are empty, while
  # payout/result sagas correctly emit zero commands when there is nothing
  # to do. Field propagation (winning_hand) is also verified.

  @EU-0316
  Scenario: TableSyncStartSaga emits DealCards with no players when active_players is empty
    Given a TableSyncStartSaga registered in a Router
    And a HandStarted event from table domain with:
      | hand_root | hand_number | game_variant | dealer_position |
      | hand-1    | 1           | TEXAS_HOLDEM | 0               |
    And active players:
      | player_root | position | stack |
    When I dispatch the event via SagaHandleRequest with destination_sequences "hand=0"
    Then the result is a angzarr_client.proto.examples.DealCards command to hand domain
    And the command DealCards has hand_number 1 and 0 players

  @EU-0317
  Scenario: TableSyncCompleteSaga emits EndHand with no results when winners is empty
    Given a TableSyncCompleteSaga registered in a Router
    And a HandComplete event from hand domain with:
      | table_root |
      | table-1    |
    And winners:
      | player_root | amount |
    When I dispatch the event via SagaHandleRequest with destination_sequences "table=0"
    Then the result is a angzarr_client.proto.examples.EndHand command to table domain
    And the EndHand command has 0 results

  @EU-0318
  Scenario: TableSyncCompleteSaga propagates winning_hand onto EndHand results
    Given a TableSyncCompleteSaga registered in a Router
    And a HandComplete event from hand domain with:
      | table_root |
      | table-1    |
    And winners with winning_hand:
      | player_root | amount |
      | player-1    | 999    |
    When I dispatch the event via SagaHandleRequest with destination_sequences "table=0"
    Then the result is a angzarr_client.proto.examples.EndHand command to table domain
    And the EndHand command result 0 has winning_hand populated

  @EU-0319
  Scenario: HandPayoutSaga emits no commands when winners is empty
    Given a HandPayoutSaga registered in a Router
    And a PotAwarded event from hand domain with:
      | pot_total |
      | 0         |
    And winners:
      | player_root | amount |
    When I dispatch the event via SagaHandleRequest with destination_sequences "player=0"
    Then no commands are emitted

  @EU-0320
  Scenario: HandPayoutSaga targets the winner player_root for a single winner
    Given a HandPayoutSaga registered in a Router
    And a PotAwarded event from hand domain with:
      | pot_total |
      | 500       |
    And winners:
      | player_root | amount |
      | player-1    | 500    |
    When I dispatch the event via SagaHandleRequest with destination_sequences "player=0"
    Then 1 commands are emitted to player domain
    And each command is a angzarr_client.proto.examples.DepositFunds
    And DepositFunds 0 has amount 500 for "player-1"
