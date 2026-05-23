# docs:start:aggregate_client_contract
Feature: Executing commands against aggregates
  Clients send commands to aggregates to change their state. Commands are
  validated, processed, and result in events being persisted. Callers can
  fire and forget, wait for the write to land, or wait for downstream
  reactions to complete before returning.

  Without command execution, the system cannot accept user actions or
  change aggregate state.
# docs:end:aggregate_client_contract

  Background:
    Given a client connected to the test backend

  # ==========================================================================
  # Basic Command Execution
  # ==========================================================================

  # docs:start:client_command
  Scenario: Executing a command on a brand-new aggregate
    Given a new aggregate root in domain "orders"
    When I send a "CreateOrder" command with data "customer-123"
    Then the command is accepted
    And a single "OrderCreated" event is recorded

  Scenario: Executing a command on an existing aggregate
    Given an aggregate "orders" with root "order-001" at sequence 3
    When I send an "AddItem" command at sequence 3
    Then the command is accepted
    And the new events continue the history from sequence 3

  Scenario: Commands carry a correlation ID through to their events
    Given a new aggregate root in domain "orders"
    When I send a command tagged with correlation ID "trace-456"
    Then the command is accepted
    And the resulting events carry correlation ID "trace-456"
  # docs:end:client_command

  # ==========================================================================
  # Optimistic Concurrency
  # ==========================================================================

  # docs:start:client_concurrency
  Scenario: Sending a command at the wrong sequence is refused
    Given an aggregate "orders" with root "order-002" at sequence 5
    When I send a command at sequence 3
    Then the command is refused because the aggregate has moved on

  Scenario: Only one of two concurrent writes can land
    Given an aggregate "orders" with root "order-003" at sequence 0
    When two commands are sent concurrently at sequence 0
    Then one command is accepted
    And the other is refused because the aggregate has moved on

  Scenario: Retrying at the current sequence after a stale write succeeds
    Given an aggregate "orders" with root "order-004" at sequence 5
    When I send a command at sequence 3
    Then the command is refused because the aggregate has moved on
    When I look up the current sequence for "orders" root "order-004"
    And I retry the command at that sequence
    Then the command is accepted
  # docs:end:client_concurrency

  # ==========================================================================
  # Sync Modes
  # ==========================================================================

  Scenario: A fire-and-forget command returns before downstream work runs
    Given a new aggregate root in domain "orders"
    When I send a command without waiting for downstream work
    Then the response returns before any projectors have caught up

  Scenario: Waiting for projectors before returning
    Given a new aggregate root in domain "orders"
    And projectors are configured for "orders" domain
    When I send a command and wait for projectors
    Then the response reflects the projectors having processed the event

  Scenario: Waiting for the full saga chain before returning
    Given a new aggregate root in domain "orders"
    And sagas are configured for "orders" domain
    When I send a command and wait for downstream sagas
    Then the response reflects the downstream sagas having completed

  # ==========================================================================
  # Command Validation
  # ==========================================================================

  Scenario: A malformed command is refused as invalid
    Given an aggregate "orders" with root "order-005"
    When I send a command with a malformed payload
    Then the command is refused as invalid

  Scenario: A command missing required fields is refused with the field name
    Given a new aggregate root in domain "orders"
    When I send a command missing required fields
    Then the command is refused as invalid
    And the refusal names the missing field

  Scenario: A command for an unknown domain is refused
    When I send a command to domain "nonexistent"
    Then the command is refused because the domain is unknown

  # ==========================================================================
  # Multi-Event Commands
  # ==========================================================================

  Scenario: A single command can produce multiple events
    Given an aggregate "orders" with root "order-006" at sequence 0
    When I send a command that produces 3 events
    Then 3 events are recorded
    And the events occupy consecutive sequences starting at 0

  Scenario: A multi-event command lands atomically
    Given an aggregate "orders" with root "order-007" at sequence 0
    When I send a command that produces 3 events
    And I read back the events for "orders" root "order-007"
    Then either all 3 events are present or none of them are

  # ==========================================================================
  # Connection Handling
  # ==========================================================================

  Scenario: The client surfaces a connection failure
    Given the aggregate service is unavailable
    When I attempt to send a command
    Then the call fails because the service cannot be reached

  Scenario: The client surfaces a timeout when the service is slow
    Given the aggregate service does not respond in time
    When I send a command with a short timeout
    Then the call fails because the deadline was exceeded

  # ==========================================================================
  # New Aggregate Creation
  # ==========================================================================

  Scenario: The first command on an aggregate creates it
    Given no aggregate exists for domain "orders" root "order-new"
    When I send a "CreateOrder" command for root "order-new" at sequence 0
    Then the command is accepted
    And the aggregate now exists with one event

  Scenario: The first command on an aggregate must start at sequence 0
    Given no aggregate exists for domain "orders" root "order-new2"
    When I send a command at sequence 5
    Then the command is refused because the aggregate has moved on
