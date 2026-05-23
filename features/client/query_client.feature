# docs:start:query_client_contract
Feature: Querying aggregate event histories
  Clients need read access to an aggregate's recorded history so they can
  reconstruct state, catch up read models, and investigate what happened.
  The query surface supports asking for everything, a range, a point in time,
  a separate edition of history, or all activity tied to a correlation.

  Without this access, clients cannot reconstruct aggregate state,
  catch up projectors, or debug what happened in the system.
# docs:end:query_client_contract

  Background:
    Given a query surface available

  # ==========================================================================
  # Basic Event Retrieval
  # ==========================================================================

  # docs:start:client_query
  @wip
  Scenario: A query against an unknown aggregate returns nothing
    Given an aggregate "orders" with root "order-new"
    When I query events for "orders" root "order-new"
    Then the history is empty and the next sequence is 0

  @wip
  Scenario: A query returns the full history of an aggregate
    Given an aggregate "orders" with root "order-001" has 5 events
    When I query events for "orders" root "order-001"
    Then I receive 5 events
    And the events are in sequence order 0 to 4

  @wip
  Scenario: A query preserves event types and payloads exactly
    Given an aggregate "orders" with root "order-002" has event "OrderCreated" with data "test-payload"
    When I query events for "orders" root "order-002"
    Then the first event has type "OrderCreated"
    And the first event has payload "test-payload"
  # docs:end:client_query

  # ==========================================================================
  # Range Queries
  # ==========================================================================

  @wip
  Scenario: A range query starting at a sequence returns the tail of history
    Given an aggregate "orders" with root "order-003" has 10 events
    When I query events for "orders" root "order-003" from sequence 5
    Then I receive 5 events
    And the first event has sequence 5

  @wip
  Scenario: A range query with an upper bound includes both endpoints
    Given an aggregate "orders" with root "order-004" has 10 events
    When I query events for "orders" root "order-004" from sequence 3 to 7
    # The upper bound is inclusive: sequences 3, 4, 5, 6, 7 -> 5 events.
    Then I receive 5 events
    And the first event has sequence 3
    And the last event has sequence 7

  @wip
  Scenario: A range query starting past the end of history returns nothing
    Given an aggregate "orders" with root "order-005" has 5 events
    When I query events for "orders" root "order-005" from sequence 100
    Then I receive no events

  # ==========================================================================
  # Temporal Queries
  # ==========================================================================

  @wip
  Scenario: A query as of a sequence returns history up to that point
    Given an aggregate "orders" with root "order-006" has 10 events
    When I query events for "orders" root "order-006" as of sequence 5
    Then I receive 6 events
    And the last event has sequence 5

  @wip
  Scenario: A query as of a timestamp returns history up to that moment
    Given an aggregate "orders" with root "order-007" has events at known timestamps
    When I query events for "orders" root "order-007" as of time "2024-01-15T10:30:00Z"
    Then I receive events up to that timestamp

  # ==========================================================================
  # Edition Queries
  # ==========================================================================

  @wip
  Scenario: A query in a named edition returns only that edition's history
    Given an aggregate "orders" with root "order-008" in edition "test-branch"
    When I query events for "orders" root "order-008" in edition "test-branch"
    Then I receive events from that edition only

  @wip
  Scenario: An edition's history is isolated from the main timeline
    Given an aggregate "orders" with root "order-009" has 3 events in main
    And an aggregate "orders" with root "order-009" has 2 events in edition "branch"
    When I query events for "orders" root "order-009"
    Then I receive 3 events
    When I query events for "orders" root "order-009" in edition "branch"
    Then I receive 2 events

  # ==========================================================================
  # Correlation ID Queries
  # ==========================================================================

  @wip
  Scenario: A correlation query gathers events across every aggregate it touched
    Given events with correlation ID "workflow-123" exist in multiple aggregates
    When I query events by correlation ID "workflow-123"
    Then I receive events from all correlated aggregates

  @wip
  Scenario: A correlation query with no matches returns nothing
    When I query events by correlation ID "nonexistent-correlation"
    Then I receive no events

  # ==========================================================================
  # Snapshot Integration
  # ==========================================================================

  @wip
  Scenario: A query surfaces the latest snapshot alongside the history
    Given an aggregate "orders" with root "order-010" has a snapshot at sequence 5 and 10 events
    When I query events for "orders" root "order-010"
    Then the result carries a snapshot taken at sequence 5

  # ==========================================================================
  # Error Handling
  # ==========================================================================

  @wip
  Scenario: A query with an empty domain is refused
    When I query events with empty domain
    Then the query is refused because a domain is required

  @wip
  Scenario: A query fails clearly when the backend is unreachable
    Given the query service is unavailable
    When I attempt to query events
    Then the query fails because the backend is unreachable
