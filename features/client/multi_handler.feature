Feature: Multi-handler merge
  As a unified-Router user
  I want multiple handlers for the same (domain, type_url) to all run
  So that cross-cutting concerns compose without replacing domain logic

  Background:
    Given two command handlers Alpha and Beta for domain "order"
    And Alpha handles CreateOrder by emitting OrderCreated
    And Beta handles CreateOrder by emitting OrderCompleted
    And the router is built with Alpha then Beta

  Scenario: Both handlers invoked in registration order
    When CreateOrder(order_id="o-1") is dispatched
    Then Alpha was called before Beta
    And the response contains two events in [OrderCreated, OrderCompleted] order

  Scenario: Sequence numbers increment across handlers
    Given the prior EventBook's next_sequence is 5
    And Alpha emits two events per call
    And Beta emits one event per call
    When CreateOrder is dispatched
    Then Alpha observed seq = 5
    And Beta observed seq = 7
    And the emitted pages carry sequences [5, 6, 7]

  Scenario: Each instance rebuilds its own state
    Given Alpha applies OrderCreated by incrementing counter_a
    And Beta applies OrderCompleted by incrementing counter_b
    And a prior EventBook with [OrderCreated, OrderCreated, OrderCompleted]
    When a command is dispatched
    Then Alpha observed counter_a = 2
    And Beta observed counter_b = 1
