Feature: Unified domain access
  A single entry point for reading and writing a domain over one connection.
  Most applications want both queries (read-side projections) and commands
  (write-side aggregates) against the same domain, and want them to share a
  channel for resource efficiency and simpler dependency injection.

  Why this matters:
  - Production services run for days — two separate connections doubles the
    socket count and the failure surface for no real benefit
  - Operators expect one endpoint per domain — splitting reads and writes
    across two client objects forces every caller to know which is which
  - The fluent builder pattern only works if reads and writes hang off the
    same object — otherwise every call site re-resolves the domain

  When to reach past this and wire reads and writes separately:
  - The read path and write path scale on different machines
  - Queries target a projection at a different endpoint than the aggregate
    coordinator
  Both cases are rare; the unified path is the default.

  Background:
    Given a running aggregate coordinator for domain "test"
    And a registered aggregate handler for domain "test"

  Scenario: Connecting to a domain exposes both query and command access
    When I create a domain client for the coordinator endpoint
    Then I should be able to query events
    And I should be able to send commands

  Scenario: Sending a command through the fluent builder
    When I create a domain client for domain "test"
    And I use the command builder to send a command
    Then I should receive a command response

  Scenario: Fetching events through the fluent query builder
    Given an aggregate "test" with root "550e8400-e29b-41d4-a716-446655440000" has 5 events
    When I create a domain client for domain "test"
    And I use the query builder to fetch events for that root
    Then I should receive 5 event pages

  Scenario: Reads and writes share the underlying connection
    When I create a domain client for the coordinator endpoint
    And I send a command
    And I query for the resulting events
    Then both operations should succeed on the same connection

  Scenario: Closing the client severs both read and write paths
    Given a connected domain client
    When I close the domain client
    Then subsequent commands should fail with a connection error
    And subsequent queries should fail with a connection error

  Scenario: Connecting via environment variable
    Given environment variable "TEST_DOMAIN_ENDPOINT" is set to the coordinator endpoint
    When I create a domain client from environment variable "TEST_DOMAIN_ENDPOINT"
    Then the domain client should be connected
