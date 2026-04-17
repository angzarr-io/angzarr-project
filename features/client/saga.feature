Feature: Saga dispatch
  As a saga author
  I want source-domain events translated into target-domain commands
  So that cross-domain coordination happens without shared state

  Background:
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    And the saga handles OrderCreated by emitting a ReserveStock command
    And the router is built with the OrderFulfillment saga

  Scenario: Saga produces a command for the target domain
    When an OrderCreated event is dispatched to the saga router
    Then the response contains exactly one command
    And the command targets the "inventory" domain

  Scenario: Saga with no matching handler yields no commands
    When a StockReserved event is dispatched to the saga router
    Then the response contains no commands

  Scenario: Saga receives destinations with stamped sequences
    Given destination sequences inventory=7 and fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the saga observed destination inventory = 7
    And the saga observed destination fulfillment = 3
