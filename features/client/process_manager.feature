# Allocated: C-0020 .. C-0022, C-0143 .. C-0145
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

  # Audit #86: edition propagation. Same contract as saga (C-0138..C-0142):
  # every outgoing CommandBook / EventBook inherits the trigger cover's
  # edition. Always-override semantics — framework guarantees propagation
  # even if the handler set a different edition on the outgoing cover.

  @C-0143
  Scenario: PM propagates trigger edition to outgoing commands
    Given the trigger event has edition "speculative"
    When an OrderCreated trigger is dispatched to the PM router
    Then the emitted command's cover has edition "speculative"

  @C-0144
  Scenario: PM propagates trigger edition to outgoing process_events
    Given the PM also emits an OrderTracked process_event on OrderCreated
    And the trigger event has edition "speculative"
    When an OrderCreated trigger is dispatched to the PM router
    Then the emitted process_event's cover has edition "speculative"

  @C-0145
  Scenario: PM always overrides handler-set edition with trigger edition
    Given the trigger event has edition "alpha"
    And the PM handler sets outgoing edition "beta"
    When an OrderCreated trigger is dispatched to the PM router
    Then the emitted command's cover has edition "alpha"
