Feature: What-if execution
  A what-if execution surface previews command, projector, saga, and process
  manager outcomes without committing them. The projected execution leaves no
  trace on real state.

  Use cases:
  - UI previews: show the user what will happen before confirming
  - Validation: check whether a command would succeed before sending
  - Testing: verify behavior without side effects
  - Simulation: model hypothetical scenarios

  Background:
    Given a what-if execution surface available

  # ==========================================================================
  # Speculative Aggregate Execution
  # ==========================================================================

  @wip
  Scenario: Speculative command returns projected events
    Given an aggregate "orders" with root "order-001" has 3 events
    When I speculatively execute a command against "orders" root "order-001"
    Then the response should contain the projected events
    And the events should NOT be persisted

  @wip
  Scenario: Speculative command respects temporal query
    Given an aggregate "orders" with root "order-002" has 10 events
    When I speculatively execute a command as of sequence 5
    Then the command should execute against the historical state
    And the response should reflect state at sequence 5

  @wip
  Scenario: Speculative command validates business rules
    Given an aggregate "orders" with root "order-003" in state "shipped"
    When I speculatively execute a "CancelOrder" command
    Then the response should indicate rejection
    And the rejection reason should be "cannot cancel shipped order"

  @wip
  Scenario: Speculative command with invalid input fails fast
    Given an aggregate "orders" with root "order-004"
    When I speculatively execute a command with invalid payload
    Then the operation should fail with validation error
    And no events should be produced

  @wip
  Scenario: Speculative execution leaves no trace
    Given an aggregate "orders" with root "order-005" has 5 events
    When I speculatively execute a command
    Then the projected execution leaves no trace

  # ==========================================================================
  # Speculative Projector Execution
  # ==========================================================================

  @wip
  Scenario: Speculative projector returns projection without side effects
    Given events for "orders" root "order-006"
    When I speculatively execute projector "order-summary" against those events
    Then the response should contain the projection
    And no external systems should be updated

  @wip
  Scenario: Speculative projector handles event sequence
    Given 5 events for "orders" root "order-007"
    When I speculatively execute projector "order-summary"
    Then the projector should process all 5 events in order
    And the final projection state should be returned

  # ==========================================================================
  # Speculative Saga Execution
  # ==========================================================================

  @wip
  Scenario: Speculative saga returns commands without sending
    Given events for "orders" root "order-008"
    When I speculatively execute saga "order-fulfillment"
    Then the response should contain the commands the saga would emit
    And the commands should NOT be sent to the target domain

  @wip
  Scenario: Speculative saga respects saga origin
    Given events with saga origin from "inventory" aggregate
    When I speculatively execute saga "inventory-order"
    Then the response should preserve the saga origin chain

  # ==========================================================================
  # Speculative Process Manager Execution
  # ==========================================================================

  @wip
  Scenario: Speculative PM returns orchestrated commands
    Given correlated events from multiple domains
    When I speculatively execute process manager "order-workflow"
    Then the response should contain the PM's command decisions
    And the commands should NOT be executed

  @wip
  Scenario: Speculative PM requires correlation ID
    Given events without correlation ID
    When I speculatively execute process manager "order-workflow"
    Then the speculative PM operation should fail
    And the error should indicate missing correlation ID

  # ==========================================================================
  # State Isolation
  # ==========================================================================

  @wip
  Scenario: Speculative execution does not affect real state
    Given a speculative aggregate "orders" with root "order-009" has 3 events
    When I speculatively execute a command producing 2 events
    And I verify the real events for "orders" root "order-009"
    Then I should receive only 3 events
    And the speculative events should not be present

  @wip
  Scenario: Multiple speculative executions are independent
    Given an aggregate "orders" with root "order-010" has 3 events
    When I speculatively execute command A
    And I speculatively execute command B
    Then each speculation should start from the same base state
    And results should be independent

  # ==========================================================================
  # Error Handling
  # ==========================================================================

  @wip
  Scenario: Speculative execution of unavailable service fails
    Given the speculative service is unavailable
    When I attempt speculative execution
    Then the speculative operation should fail with connection error

  @wip
  Scenario: Invalid speculative request returns error
    When I attempt speculative execution with missing parameters
    Then the speculative operation should fail with invalid argument error
