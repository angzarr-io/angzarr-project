# docs:start:command_builder_contract
Feature: CommandBuilder - Fluent Command Construction
  The CommandBuilder provides a fluent API for constructing commands.
  It handles serialization, caller-set correlation IDs, expected sequences, and
  type URLs while providing compile-time and runtime validation. A built
  command is sent with execute_async, execute or execute_sync, named after
  the coordinator RPCs HandleAsync, Handle and HandleSync.

  The builder pattern enables both OO-style client usage and can be
  adapted for router-based implementations.
# docs:end:command_builder_contract

  Background:
    Given a mock CommandHandlerClient for testing

  # ==========================================================================
  # Basic Command Construction
  # ==========================================================================

  @C-0303
  Scenario: Build command with all required fields
    When I build a command for domain "orders" root "order-001"
      And I set the command type to "CreateOrder"
      And I set the command payload
    Then the built command should have domain "orders"
    And the built command should have root "order-001"
    And the built command should have type URL containing "CreateOrder"

  @C-0304
  Scenario: Build command for new aggregate (auto-generates client-side UUID)
    # Per audit decision 2026-04-27 (finding #20 / P2.4a closed):
    # `command_new(domain)` auto-generates a fresh UUID v4 for the
    # root. Aggregate roots are always client-assigned across all
    # languages — you cannot create an aggregate without a root.
    When I build a command for new aggregate in domain "orders"
      And I set the command type to "CreateOrder"
      And I set the command payload
    Then the built command should have domain "orders"
    And the built command should have an auto-generated UUID root
    And the auto-generated root should be a valid UUID

  @C-0305
  Scenario: Build leaves the correlation ID unset when not provided
    # The coordinator applies the rule for an absent correlation: it is
    # the command id (itself minted as a UUIDv7 when absent).
    When I build a command for domain "orders"
      And I set the command type and payload
    Then the built command should have no correlation ID

  # ==========================================================================
  # Optional Fields
  # ==========================================================================

  @C-0306
  Scenario: Build with explicit correlation ID
    When I build a command for domain "orders"
      And I set correlation ID to "0192f3a4-5b6c-7d8e-9f01-23456789ab01"
      And I set the command type and payload
    Then the built command should have correlation ID "0192f3a4-5b6c-7d8e-9f01-23456789ab01"

  @C-0307
  Scenario: Build with an expected sequence
    When I build a command for domain "orders" root "order-002"
      And I set the expected sequence to 5
      And I set the command type and payload
    Then the built command should have expected sequence 5

  @C-0308
  Scenario: Build without an expected sequence leaves it unset
    # The coordinator stamps the head it decides against; there is no
    # default of 0.
    When I build a command for domain "orders"
      And I set the command type and payload
    Then the built command should have no expected sequence

  # ==========================================================================
  # Validation
  # ==========================================================================

  @C-0309
  Scenario: Build without command type fails
    When I build a command for domain "orders"
      And I do NOT set the command type
    Then building should fail
    And the error should indicate missing type URL

  @C-0310
  Scenario: Build without payload fails
    When I build a command for domain "orders"
      And I set the command type to "CreateOrder"
      And I do NOT set the payload
    Then building should fail
    And the error should indicate missing payload

  # ==========================================================================
  # Fluent Chaining
  # ==========================================================================

  @C-0311
  Scenario: Builder methods can be chained
    When I build a command using fluent chaining:
      """
      client.command("orders", root)
        .with_correlation_id("0192f3a4-5b6c-7d8e-9f01-23456789ab02")
        .with_expected_sequence(3)
        .with_command("CreateOrder", payload)
        .build()
      """
    Then the build should succeed
    And all chained values should be preserved

  @C-0312
  Scenario: Builder is immutable-friendly
    Given a builder configured for domain "orders"
    When I create two commands with different roots
    Then each command should have its own root
    And builder reuse should not cause cross-contamination

  # ==========================================================================
  # Execute Integration
  # ==========================================================================

  @C-0313
  Scenario: Builder can execute directly
    When I build and execute a command for domain "orders"
    Then the command should be sent to the gateway
    And the response should be returned

  @C-0314
  Scenario: Execute without building explicitly
    When I use the builder to execute directly:
      """
      client.command("orders", root)
        .with_command("CreateOrder", payload)
        .execute()
      """
    Then the command should be built and executed in one call

  # ==========================================================================
  # Batches
  # ==========================================================================

  @C-0572
  Scenario: A batch shares the caller's correlation ID across its commands
    When I build a batch of 3 commands for domain "orders" with correlation ID "0192f3a4-5b6c-7d8e-9f01-23456789ab05"
    Then every command in the batch should have correlation ID "0192f3a4-5b6c-7d8e-9f01-23456789ab05"

  @C-0573
  Scenario: A batch without a caller's correlation ID shares one it mints
    When I build a batch of 3 commands for domain "orders"
    Then every command in the batch should have the same correlation ID
    And that correlation ID should be a UUIDv7

  @C-0574
  Scenario: A batch can opt out of a shared correlation ID
    # Each command then defaults, at the coordinator, to its own command ID.
    When I build a batch of 3 commands for domain "orders" opting out of a shared correlation ID
    Then no command in the batch should have a correlation ID

  @C-0575
  Scenario: A single command never gets a minted correlation ID
    When I build one command for domain "orders" outside a batch
    Then the built command should have no correlation ID

  # ==========================================================================
  # Conflict Resolution
  # ==========================================================================

  @C-0315
  Scenario: Default conflict resolution is UNSPECIFIED
    # UNSPECIFIED means the coordinator applies the configured default.
    When I build a command without specifying a conflict resolution
    Then the command's handling should have conflict resolution CONFLICT_RESOLUTION_UNSPECIFIED

  @C-0316
  Scenario: Build with explicit conflict resolution
    When I build a command with conflict resolution STRICT
    Then the command's handling should have conflict resolution CONFLICT_RESOLUTION_STRICT

  # ==========================================================================
  # Extension Traits
  # ==========================================================================

  @C-0317
  Scenario: Client provides command builder shortcut
    Given a CommandHandlerClient implementation
    When I call client.command("orders", root)
    Then I should receive a CommandBuilder for that domain and root

  @C-0318
  Scenario: Client provides command_new shortcut
    # Per finding #20 / P2.4a closed: command_new auto-generates a
    # client-side UUID v4 for the root in every language. Shortcut
    # returns a CommandBuilder with both domain and root populated.
    Given a CommandHandlerClient implementation
    When I call client.command_new("orders")
    Then I should receive a CommandBuilder for that domain and an auto-generated root
