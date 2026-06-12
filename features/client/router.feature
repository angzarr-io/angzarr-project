# docs:start:router_contract
Feature: Router - Command and Event Routing
  Routers dispatch incoming commands/events to appropriate handlers.
  Each component type (aggregate, saga, projector, PM) has its own
  router pattern, but all share common routing concepts.

  Routers enable:
  - Type-based dispatch to handlers
  - State reconstruction before handling
  - Event emission after handling
  - Error handling and compensation
# docs:end:router_contract

  # ==========================================================================
  # Aggregate Router
  # ==========================================================================

  Scenario: Aggregate router dispatches by command type
    Given an aggregate router with handlers for "CreateOrder" and "AddItem"
    When I receive a "CreateOrder" command
    Then the CreateOrder handler should be invoked
    And the AddItem handler should NOT be invoked

  Scenario: Command handlers see previously recorded history
    Given an aggregate router
    And an aggregate with existing events
    When I receive a command for that aggregate
    Then the handler should receive state reflecting all previously recorded events

  Scenario: Aggregate router returns emitted events
    Given an aggregate router
    When a handler emits 2 events
    Then the router should return those events
    And the events should carry consecutive sequences continuing the aggregate's history

  Scenario: Unknown command type returns error
    Given an aggregate router with handlers for "CreateOrder"
    When I receive an "UnknownCommand" command
    Then the router should return an error
    And the error should indicate unknown command type

  # ==========================================================================
  # Saga Router
  # ==========================================================================

  Scenario: Saga router dispatches by event type
    Given a saga router with handlers for "OrderCreated" and "OrderShipped"
    When I receive an "OrderCreated" event
    Then the OrderCreated handler should be invoked
    And the OrderShipped handler should NOT be invoked

  Scenario: Saga commands are sequenced for their destination
    Given a saga router
    When I receive an event that triggers command to "inventory"
    Then the emitted command should be sequenced to follow the current history of "inventory"

  Scenario: Saga router handles rejection
    Given a saga router with a rejected command
    When the router processes the rejection
    Then a rejection notification should be emitted
    And compensation should be initiated for the rejected command

  Scenario: Saga router is stateless
    Given a saga router
    When I process two events with same type
    Then each should be processed independently
    And no state should carry over between events

  # ==========================================================================
  # Projector Router
  # ==========================================================================

  Scenario: Projector router dispatches by event type
    Given a projector router with handlers for "OrderCreated"
    When I receive an "OrderCreated" event
    Then the OrderCreated handler should be invoked

  Scenario: Projector router processes event batches
    Given a projector router
    When I receive 5 events in a batch
    Then all 5 events should be processed in order
    And the resulting projection should reflect all 5 events

  # ==========================================================================
  # Process Manager Router
  # ==========================================================================

  Scenario: PM router dispatches by event type across domains
    Given a PM router with handlers for "OrderCreated" and "InventoryReserved"
    When I receive an "OrderCreated" event from domain "orders"
    Then the OrderCreated handler should be invoked
    When I receive an "InventoryReserved" event from domain "inventory"
    Then the InventoryReserved handler should be invoked

  # ==========================================================================
  # Handler Registration
  # ==========================================================================

  Scenario: Register multiple handlers
    Given a router
    When I register handlers for "TypeA", "TypeB", and "TypeC"
    Then all three types should be routable
    And each should invoke its specific handler

  Scenario: Handler receives typed message
    Given a router with handler for protobuf message type
    When I receive an event with that type
    Then the handler should receive the message as its declared protobuf type

  # ==========================================================================
  # State Building
  # ==========================================================================

  Scenario: State is built from events
    Given an aggregate router
    And events: OrderCreated, ItemAdded, ItemAdded
    When I build state from these events
    Then the state should reflect all three events applied
    And the state should have 2 items

  Scenario: Empty aggregate has default state
    Given an aggregate router
    And no events for the aggregate
    When I build state
    Then the state should be the default/initial state

  # ==========================================================================
  # Error Handling in Routers
  # ==========================================================================

  Scenario: Handler failure yields no events
    Given a router
    When a handler returns an error
    Then the caller should be informed of the failure
    And no events should be emitted

  Scenario: Malformed payload is rejected
    Given a router
    When I receive an event with invalid payload
    Then the request should fail
    And the failure should identify the malformed payload

  # ==========================================================================
  # Guard/Validate/Compute Pattern
  # ==========================================================================

  Scenario: Guard checks preconditions
    Given an aggregate with guard checking aggregate exists
    When I send command to non-existent aggregate
    Then guard should reject
    And no event should be emitted

  Scenario: Validate checks command validity
    Given an aggregate handler with validation
    When I send command with invalid data
    Then validate should reject
    And rejection reason should describe the issue

  Scenario: Compute produces events
    Given an aggregate handler
    When guard and validate pass
    Then compute should produce events
    And events should reflect the state change
