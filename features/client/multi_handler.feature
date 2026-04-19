# Allocated: C-0010 .. C-0015, C-0087
Feature: Multi-handler merge
  As a unified-Router user
  I want multiple handlers for the same (domain, type_url) to all run
  So that cross-cutting concerns compose without replacing domain logic

  Background:
    Given two command handlers Alpha and Beta for domain "order"
    And Alpha handles CreateOrder by emitting OrderCreated
    And Beta handles CreateOrder by emitting OrderCompleted
    And the router is built with Alpha then Beta

  @C-0010
  Scenario: Both handlers invoked in registration order
    When CreateOrder(order_id="o-1") is dispatched
    Then Alpha was called before Beta
    And the response contains two events in [OrderCreated, OrderCompleted] order

  @C-0011
  Scenario: Sequence numbers increment across handlers
    Given the prior EventBook's next_sequence is 5
    And Alpha emits two events per call
    And Beta emits one event per call
    When CreateOrder is dispatched
    Then Alpha observed seq = 5
    And Beta observed seq = 7
    And the emitted pages carry sequences [5, 6, 7]

  @C-0012
  Scenario: Each instance rebuilds its own state
    Given Alpha applies OrderCreated by incrementing counter_a
    And Beta applies OrderCompleted by incrementing counter_b
    And a prior EventBook with [OrderCreated, OrderCreated, OrderCompleted]
    When a command is dispatched
    Then Alpha observed counter_a = 2
    And Beta observed counter_b = 1

  @C-0013
  Scenario: Saga multi-handler merge — all matching sagas invoked
    Given two sagas SagaA and SagaB both listening to source "order" for OrderCreated
    And SagaA emits a ReserveStock command for "inventory"
    And SagaB emits a CreateShipment command for "fulfillment"
    And the saga router is built with SagaA then SagaB
    When an OrderCreated event is dispatched to the saga router
    Then the response contains two commands in registration order
    And the first command targets the "inventory" domain
    And the second command targets the "fulfillment" domain

  @C-0014
  Scenario: Process manager multi-handler merge — all matching PMs invoked
    Given two process managers PMA and PMB both sourcing from "order" and handling OrderCreated
    And PMA emits a ReserveStock command
    And PMB emits a CreateShipment command
    And the PM router is built with PMA then PMB
    When an OrderCreated trigger is dispatched to the PM router
    Then the response contains two commands in registration order

  @C-0015
  Scenario: Projector multi-handler fan-out — each projector runs its side effects
    Given two projectors ProjA and ProjB both consuming domain "order"
    And ProjA appends to a log on OrderCreated
    And ProjB appends to a different log on OrderCreated
    And the projector router is built with ProjA then ProjB
    When an EventBook with one OrderCreated event is dispatched
    Then ProjA's log has 1 entry
    And ProjB's log has 1 entry

  @C-0087
  Scenario: Each matched factory invoked exactly once per dispatch
    Given two command handlers Alpha and Beta for domain "order" both handling CreateOrder
    And each factory counts invocations
    And the router is built with Alpha then Beta
    When CreateOrder(order_id="o-1") is dispatched
    Then Alpha's factory was invoked exactly 1 time
    And Beta's factory was invoked exactly 1 time
