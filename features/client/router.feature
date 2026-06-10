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

  @wip
  Scenario: Aggregate router validates sequence
    Given an aggregate at sequence 5
    When I receive a command at sequence 3
    Then the command should be rejected with a sequence mismatch
    And no handler should be invoked

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

  @wip
  Scenario: Saga router emits commands
    Given a saga router
    When a handler produces a command
    Then the router should return the command
    And the command should have correct saga_origin

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

  @wip
  Scenario: Projector router supports speculative execution
    Given a projector router
    When I speculatively process events
    Then no external side effects should occur
    And the projection result should be returned

  @wip
  Scenario: Projector does not reprocess already-delivered events
    Given a projector router
    And events up to sequence 15 have been processed
    When events from sequence 10 to 15 are delivered again
    Then the projection should not change

  # ==========================================================================
  # Process Manager Router
  # ==========================================================================

  Scenario: PM router dispatches by event type across domains
    Given a PM router with handlers for "OrderCreated" and "InventoryReserved"
    When I receive an "OrderCreated" event from domain "orders"
    Then the OrderCreated handler should be invoked
    When I receive an "InventoryReserved" event from domain "inventory"
    Then the InventoryReserved handler should be invoked

  @wip
  Scenario: PM router requires correlation ID
    Given a PM router
    When I receive an event without correlation ID
    Then the event should be skipped
    And no handler should be invoked

  @wip
  Scenario: PM router maintains state by correlation
    Given a PM router
    When I receive correlated events with ID "workflow-123"
    Then state should be maintained across events
    And events with different correlation IDs should have separate state

  @wip
  Scenario: PM router emits commands
    Given a PM router
    When a handler produces a command
    Then the router should return the command
    And the command should preserve correlation ID

  # R2-02-LIVE: after persisting the new PM events the coordinator
  # publishes EXACTLY those new events, never re-reading the full
  # event-store history. Pre-fix the persist path called
  # `event_store.get(...)` after the add and republished every prior
  # PM event on every command, fanning out O(history) on every update.
  @wip
  Scenario: PM persist publishes only the newly-emitted events
    Given a process manager with 3 prior events persisted
    When the PM handler emits 2 new events
    Then the bus receives exactly 2 events
    And the 3 prior events are NOT re-fired

  @wip
  Scenario: PM publish stamps the in-flight correlation ID on the cover
    Given a process manager invoked with correlation ID "in-flight-corr"
    And the PM handler returns events with a blank cover correlation ID
    When the coordinator publishes the events
    Then the published cover carries correlation ID "in-flight-corr"

  # ==========================================================================
  # Handler Registration
  # ==========================================================================

  @wip
  Scenario: Register handler by type URL token
    Given a router
    When I register handler for type "OrderCreated"
    Then events whose final dotted token is "OrderCreated" should match
    And events whose final dotted token is "ItemAdded" should NOT match

  # R2-01: short subscription names must not silently fan out to other
  # event types that happen to end with the same substring. Matching is
  # token-boundary (split on the last "." or "/"), not raw `ends_with`.
  @wip
  Scenario: Short event-type subscription does not match other types
    Given a subscription to event type "Created"
    When an event of type "OrderCreated" is published
    Then the subscriber does NOT receive it

  @wip
  Scenario: Short event-type subscription matches at the final dotted token only
    Given a subscription to event type "OrderCreated"
    When an event of type "type.googleapis.com/example.OrderCreated" is published
    Then the subscriber receives it
    When an event of type "type.googleapis.com/example.MyOrderCreated" is published
    Then the subscriber does NOT receive it

  @wip
  Scenario: Fully-qualified subscription type requires exact match
    Given a subscription to event type "type.googleapis.com/example.OrderCreated"
    When an event of type "type.googleapis.com/example.OrderCreated" is published
    Then the subscriber receives it
    When an event of type "type.googleapis.com/example.UserCreated" is published
    Then the subscriber does NOT receive it

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

  @wip
  Scenario: State building uses snapshot when available
    Given an aggregate router
    And a snapshot at sequence 5
    And events 6, 7, 8
    When I build state
    Then the resulting state should reflect the snapshot with events 6 through 8 applied

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

  @wip
  Scenario: Unreplayable history fails safely
    Given a router
    And an aggregate whose recorded history cannot be replayed
    When I receive a command for that aggregate
    Then the command should fail
    And no handler should be invoked

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
