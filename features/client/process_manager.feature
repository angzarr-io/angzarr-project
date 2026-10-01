Feature: Process-manager dispatch
  As a process-manager author
  I want to correlate events across domains with my own state
  So that multi-step workflows are orchestrated correctly

  Background:
    Given a process manager "Fulfillment" for the fulfillment domain
    And the PM sources from "order" and "inventory"
    And the PM targets "shipping"
    And the PM tracks the number of orders seen
    And OrderCompleted advances the orders-seen count
    And the PM handles OrderCreated by emitting a ReserveStock command
    And Fulfillment is the active process manager

  @C-0020
  Scenario: PM receives a trigger and emits a command
    When an OrderCreated trigger is dispatched to the PM router
    Then the response contains exactly one command

  @C-0021
  Scenario: PM state is rebuilt from its own process events
    Given process state events: OrderCompleted, OrderCompleted
    When an OrderCreated trigger is dispatched to the PM router
    Then the PM has seen 2 completed orders

  @C-0022
  Scenario: PM skips events from domains outside its sources
    When a StockReserved trigger with a domain outside sources is dispatched
    Then the response contains no commands

  @C-0181
  Scenario: PM command is deferred with the trigger as its source
    Given the OrderCreated trigger is at sequence 2 of order root "order-1"
    When the OrderCreated trigger is dispatched to the PM router
    Then the ReserveStock command carries an angzarr_deferred header
    And the deferred source cover is domain "order" root "order-1"
    And the deferred source_seq is 2
    And the deferred command_index is 0
    And no page of the ReserveStock command has an explicit sequence
