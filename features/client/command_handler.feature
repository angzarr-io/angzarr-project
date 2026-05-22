# Allocated: C-0001 .. C-0006, C-0085, C-0146 .. C-0148
Feature: Command handler dispatch
  As an aggregate author
  I want commands routed to @handles methods with state rebuilt from prior events
  So that business logic runs with the correct state and emits events

  Background:
    Given a command handler "Order" for domain "order" with state OrderState
    And the handler applies OrderCreated by setting state.created = true
    And the handler handles CreateOrder by emitting OrderCreated
    And the router is built with the Order handler

  @C-0001
  Scenario: Unknown aggregate receives a creation command
    When CreateOrder(order_id="o-1") is dispatched
    Then the response emits an OrderCreated event
    And the emitted event sequence is 0

  @C-0002
  Scenario: State is rebuilt from prior events before dispatch
    Given a prior EventBook with an OrderCreated event at seq 0
    When a command is dispatched against the aggregate
    Then the handler sees state.created = true

  @C-0003
  Scenario: Unknown command type returns INVALID_ARGUMENT
    When CompleteOrder(order_id="o-1") is dispatched
    Then dispatch fails with INVALID_ARGUMENT

  @C-0004
  Scenario: Handler returning None yields empty BusinessResponse
    Given a command handler whose handler returns None for CreateOrder
    When CreateOrder(order_id="o-1") is dispatched
    Then the response has no event pages

  @C-0005
  Scenario: @state_factory override constructs state when present
    Given a command handler "Order" for domain "order" with state OrderState
    And Order has a @state_factory method returning OrderState(created=True)
    And Order handles CreateOrder by emitting OrderCreated only when state.created is True
    When CreateOrder(order_id="o-1") is dispatched
    Then the response emits an OrderCreated event

  @C-0006
  Scenario: Default state() constructor is used when no @state_factory is present
    Given a command handler "Order" for domain "order" with state OrderState
    And Order has no @state_factory method
    And Order handles CreateOrder by reading state.created
    When CreateOrder(order_id="o-1") is dispatched
    Then the handler observed state.created = false

  @C-0085
  Scenario: With zero prior events, state remains at its constructed default
    Given a command handler "Order" for domain "order" with state OrderState
    And Order applies OrderCreated by setting state.created = true
    And Order handles CreateOrder by reading state.created
    And no prior events in the incoming ContextualCommand
    When CreateOrder(order_id="o-1") is dispatched
    Then the handler observed state.created = false

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
