# Allocated: C-0020 .. C-0022
Feature: Process-manager dispatch
  As a process-manager author
  I want to correlate events across domains with my own state
  So that multi-step workflows are orchestrated correctly

  Background:
    Given a process manager "Fulfillment" with pm_domain "fulfillment"
    And the PM sources from "order" and "inventory"
    And the PM targets "shipping"
    And the PM has state WorkflowState with orders_seen int
    And the PM applies OrderCompleted by incrementing state.orders_seen
    And the PM handles OrderCreated by emitting a ReserveStock command
    And the router is built with the Fulfillment PM

  @C-0020
  Scenario: PM receives a trigger and emits a command
    When an OrderCreated trigger is dispatched to the PM router
    Then the response contains exactly one command

  @C-0021
  Scenario: PM state is rebuilt from its own process events
    Given process state events: OrderCompleted, OrderCompleted
    When an OrderCreated trigger is dispatched to the PM router
    Then the PM observed state.orders_seen = 2

  @C-0022
  Scenario: PM skips events from domains outside its sources
    When a StockReserved trigger with a domain outside sources is dispatched
    Then the response contains no commands

# Audit #86 was reverted: edition propagation moved to
# `coordinator-contract/edition_propagation.feature`. See the
# rationale in the saga.feature trailer comment.
