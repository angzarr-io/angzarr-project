# Allocated: C-0001 .. C-0006, C-0085, C-0146 .. C-0148
Feature: Command handler dispatch
  As an aggregate author
  I want commands routed to @handles methods with state rebuilt from prior events
  So that business logic runs with the correct state and emits events

  Background:
    Given a command handler "Order" for domain "order" with order state
    And OrderCreated marks the order as created
    And CreateOrder emits OrderCreated
    And Order is the active aggregate handler

  @C-0001
  Scenario: Unknown aggregate receives a creation command
    When CreateOrder(order_id="o-1") is dispatched
    Then the response emits an OrderCreated event
    And the emitted event sequence is 0

  @C-0002
  Scenario: State is rebuilt from prior events before dispatch
    Given a prior history with an OrderCreated event at sequence 0
    When a command is dispatched against the aggregate
    Then the order is treated as already created

  @C-0003
  Scenario: Unknown command type returns INVALID_ARGUMENT
    When CompleteOrder(order_id="o-1") is dispatched
    Then the unknown command is rejected as invalid input

  @C-0004
  Scenario: Handler returning None yields empty BusinessResponse
    Given a command handler whose handler returns None for CreateOrder
    When CreateOrder(order_id="o-1") is dispatched
    Then when the handler emits nothing, no events are produced

  @C-0005
  Scenario: Aggregate-supplied initial state constructs an already-created order
    Given a command handler "Order" for domain "order" with order state
    And the aggregate supplies its own initial state with created = true
    And Order handles CreateOrder by emitting OrderCreated only when the order is already created
    When CreateOrder(order_id="o-1") is dispatched
    Then the response emits an OrderCreated event

  @C-0006
  Scenario: Default state constructor is used when the aggregate does not supply its own
    Given a command handler "Order" for domain "order" with order state
    And the aggregate does not supply its own initial state
    And Order handles CreateOrder by reading whether the order is created
    When CreateOrder(order_id="o-1") is dispatched
    Then the handler observes that the order is not created

  @C-0085
  Scenario: With zero prior events, state remains at its constructed default
    Given a command handler "Order" for domain "order" with order state
    And OrderCreated marks the order as created
    And Order handles CreateOrder by reading whether the order is created
    And no prior events in the incoming ContextualCommand
    When CreateOrder(order_id="o-1") is dispatched
    Then the handler observes that the order is not created

  # ==========================================================================
  # Cover.ext propagation (client-side, fill-only)
  # ==========================================================================
  # types.proto Cover doc: "the framework stamps this slot onto EVERY event
  # a child aggregate emits". Implementation lives in each client's
  # dispatch path (not the coordinator) so the policy is colocated with
  # event creation. Fill-only — never overrides a handler-set ext.

  @C-0146
  Scenario: Command cover.ext is stamped onto the emitted EventBook's cover
    Given the incoming command has cover.ext set to a packed parent Cover
    When CreateOrder(order_id="o-1") is dispatched
    Then the response's EventBook cover.ext is the same packed parent Cover

  @C-0147
  Scenario: Handler-set ext on the emitted EventBook is not overridden
    Given a command handler whose emit step sets EventBook cover.ext explicitly
    And the incoming command also has a different cover.ext set
    When CreateOrder(order_id="o-1") is dispatched
    Then the response's EventBook cover.ext is the handler-set value

  @C-0148
  Scenario: No command ext leaves the emitted EventBook cover.ext unset
    Given the incoming command's cover has no ext field set
    When CreateOrder(order_id="o-1") is dispatched
    Then the response's EventBook cover has no ext field set
