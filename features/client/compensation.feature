# docs:start:compensation_contract
Feature: Compensation - Saga Rejection Handling
  When saga commands are rejected by target aggregates, the compensation
  flow carries the rejected command and its context back to the source
  aggregate so it can react to the downstream failure.

  Compensation enables:
  - Source aggregates to handle downstream failures
  - Maintaining consistency across domain boundaries
  - Tracking rejection chains for debugging
# docs:end:compensation_contract

  Background:
    Given a compensation handling context

  # ==========================================================================
  # CompensationContext Construction
  # ==========================================================================

  Scenario: Build context from rejected command
    Given a saga command that was rejected
    When the compensation context is constructed from the rejection
    Then the context carries the rejected command
    And the context carries the rejection reason
    And the context carries the saga origin

  Scenario: Context preserves saga origin details
    Given a saga "order-fulfillment" triggered by "orders" aggregate at sequence 5
    And the saga command was rejected
    When the compensation context is constructed from the rejection
    Then the saga origin is preserved

  Scenario: Context preserves correlation ID
    Given a saga command with correlation ID "workflow-123"
    And the command was rejected
    When the compensation context is constructed from the rejection
    Then the correlation ID is preserved

  # ==========================================================================
  # RejectionNotification Building
  # ==========================================================================

  Scenario: Build rejection notification from context
    Given a CompensationContext for rejected command
    When I build a RejectionNotification
    Then the notification carries the rejected command
    And the notification carries the rejection reason

  Scenario: Rejection notification includes source aggregate
    Given a CompensationContext from "orders" aggregate at sequence 5
    When I build a RejectionNotification
    Then the source aggregate and sequence are recorded

  Scenario: Rejection notification has correct issuer name
    Given a CompensationContext from saga "order-fulfillment"
    When I build a RejectionNotification
    Then the notification identifies the issuing saga as "order-fulfillment"

  # ==========================================================================
  # Notification Building
  # ==========================================================================

  Scenario: Build notification wrapper for rejection
    Given a CompensationContext for rejected command
    When I build a Notification from the context
    Then the notification has a cover
    And the notification payload contains a RejectionNotification

  Scenario: Notification has sent_at timestamp
    When I build a Notification from a CompensationContext
    Then the notification carries its dispatch time

  # ==========================================================================
  # Command Book Building
  # ==========================================================================

  Scenario: Build notification command book for routing
    Given a CompensationContext for rejected command
    When I build a notification CommandBook
    Then the command book targets the source aggregate
    And the command book preserves the correlation ID

  Scenario: Command book targets triggering aggregate
    Given a CompensationContext from "orders" aggregate root "order-123"
    When I build a notification CommandBook
    Then the command book targets the source aggregate

  # ==========================================================================
  # Rejection Reason Handling
  # ==========================================================================

  Scenario: Rejection reason is preserved exactly
    Given a command rejected with reason "insufficient_funds"
    When I build a RejectionNotification
    Then the rejection reason equals "insufficient_funds"

  Scenario: Complex rejection reason
    Given a command rejected with structured reason
    When I build a RejectionNotification
    Then the rejection reason carries the full error details

  # ==========================================================================
  # Chain of Command Tracking
  # ==========================================================================

  Scenario: Rejected command is preserved for debugging
    Given a saga command with specific payload
    And the command was rejected
    When I build a RejectionNotification
    Then the rejected command is the original command
    And all command fields are preserved

  Scenario: Saga origin chain is maintained
    Given a nested saga scenario
    And an inner saga command was rejected
    When I build a RejectionNotification
    Then the full saga origin chain is preserved
    And the root cause can be traced through the chain

  Scenario: Saga rejections produce a compensation notification
    Given a saga router handling rejections
    When a command execution fails with precondition error
    Then saga rejections produce a compensation notification

  Scenario: Process manager rejections produce a compensation notification
    Given a process manager router
    When a PM command is rejected
    Then process manager rejections produce a compensation notification
