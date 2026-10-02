Feature: Connection - Client Connection Management
  Clients connect to angzarr services via TCP or Unix Domain Sockets.
  Connection configuration supports environment variables, explicit
  endpoints, and channel reuse for efficiency.

  # ==========================================================================
  # TCP Connection
  # ==========================================================================

  @C-0319
  Scenario: Connect via TCP with host and port
    When I connect to "localhost:1310"
    Then the connection should succeed
    And the client should be ready for operations

  @C-0320
  Scenario: Connect via TCP with http scheme
    When I connect to "http://localhost:1310"
    Then the connection should succeed
    And the scheme should be treated as insecure

  @C-0321
  Scenario: Connect via TCP with https scheme
    When I connect to "https://localhost:1310"
    Then the connection should use TLS

  @C-0322
  Scenario: Connect to non-existent host fails
    When I connect to "nonexistent.invalid:1310"
    Then the connection should fail
    And the error should indicate DNS or connection failure

  @C-0323
  Scenario: Connect to closed port fails
    When I connect to "localhost:59999"
    Then the connection should fail
    And the error should indicate connection refused

  # ==========================================================================
  # Unix Domain Socket Connection
  # ==========================================================================

  @C-0324
  Scenario: Connect via Unix socket path
    Given a Unix socket at "/tmp/angzarr.sock"
    When I connect to "/tmp/angzarr.sock"
    Then the connection should succeed
    And the client should use UDS transport

  @C-0325
  Scenario: Connect via Unix socket with scheme
    Given a Unix socket at "/tmp/angzarr.sock"
    When I connect to "unix:///tmp/angzarr.sock"
    Then the connection should succeed

  @C-0326
  Scenario: Connect to non-existent socket fails
    When I connect to "/tmp/nonexistent.sock"
    Then the connection should fail
    And the error should indicate socket not found

  # ==========================================================================
  # Environment Variable Configuration
  # ==========================================================================

  @C-0327
  Scenario: Connect from environment variable
    Given environment variable "ANGZARR_ENDPOINT" set to "localhost:1310"
    When I call from_env("ANGZARR_ENDPOINT", "default:9999")
    Then the connection should use "localhost:1310"

  @C-0328
  Scenario: Environment variable not set uses default
    Given environment variable "ANGZARR_ENDPOINT" is not set
    When I call from_env("ANGZARR_ENDPOINT", "localhost:1310")
    Then the connection should use "localhost:1310"

  @C-0329
  Scenario: Empty environment variable uses default
    Given environment variable "ANGZARR_ENDPOINT" set to ""
    When I call from_env("ANGZARR_ENDPOINT", "localhost:1310")
    Then the connection should use "localhost:1310"

  # ==========================================================================
  # Channel Reuse
  # ==========================================================================

  @C-0330
  Scenario: Create client from existing channel
    Given an existing gRPC channel
    When I call from_channel(channel)
    Then the client should reuse that channel
    And no new connection should be created

  @C-0331
  Scenario: Multiple clients share channel
    Given an existing gRPC channel
    When I create QueryClient from the channel
    And I create CommandHandlerClient from the same channel
    Then both clients should share the connection
    And the connection should only be established once

  # ==========================================================================
  # Client Types
  # ==========================================================================

  @C-0332
  Scenario: QueryClient connects successfully
    When I create a QueryClient connected to "localhost:1310"
    Then the client should be able to query events

  @C-0333
  Scenario: CommandHandlerClient connects successfully
    When I create a CommandHandlerClient connected to "localhost:1310"
    Then the client should be able to execute commands

  @C-0334
  Scenario: SpeculativeClient connects successfully
    When I create a SpeculativeClient connected to "localhost:1310"
    Then the client should be able to perform speculative operations

  @C-0335
  Scenario: DomainClient combines query and aggregate
    When I create a DomainClient connected to "localhost:1310"
    Then the client should have aggregate and query sub-clients
    And both should share the same connection

  # ==========================================================================
  # Connection Options
  # ==========================================================================

  @C-0336
  Scenario: Connection with timeout
    When I connect with timeout of 5 seconds
    Then the connection should respect the timeout
    And slow connections should fail after timeout

  @C-0337
  Scenario: Connection with keep-alive
    When I connect with keep-alive enabled
    Then the connection should send keep-alive probes
    And idle connections should remain open

  # ==========================================================================
  # Error Handling
  # ==========================================================================

  @C-0338
  Scenario: Invalid endpoint format
    When I connect to "not a valid endpoint"
    Then the connection should fail
    And the error should indicate invalid format

  @C-0339
  Scenario: Connection lost mid-operation
    Given an established connection
    When the server disconnects
    And I attempt an operation
    Then the operation should fail
    And the error should indicate connection lost

  @C-0340
  Scenario: Reconnection after failure
    Given a connection that failed
    When I create a new client with the same endpoint
    Then the new connection should be independent
    And the new connection should succeed if server is available
