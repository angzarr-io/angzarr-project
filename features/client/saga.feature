# Allocated: C-0050 .. C-0053
Feature: Saga dispatch
  As a saga author
  I want source-domain events translated into target-domain commands
  So that cross-domain coordination happens without shared state

  Background:
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    And the saga handles OrderCreated by emitting a ReserveStock command
    And the router is built with the OrderFulfillment saga

  @C-0050
  Scenario: Saga produces a command for the target domain
    When an OrderCreated event is dispatched to the saga router
    Then the response contains exactly one command
    And the command targets the "inventory" domain

  @C-0051
  Scenario: Saga with no matching handler yields no commands
    When a StockReserved event is dispatched to the saga router
    Then the response contains no commands

  @C-0052
  Scenario: Saga receives destinations with stamped sequences
    Given destination sequences inventory=7 and fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the saga observed destination inventory = 7
    And the saga observed destination fulfillment = 3

  @C-0053
  Scenario: Saga emitting to two target domains uses each domain's sequence independently
    Given a saga "OrderSplit" translating from "order" to "inventory" and "fulfillment"
    And the saga handles OrderCreated by emitting a ReserveStock for "inventory" and a CreateShipment for "fulfillment"
    And destination sequences inventory=7 and fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the ReserveStock command carries destination sequence 7
    And the CreateShipment command carries destination sequence 3

# Audit #86 was reverted: edition propagation is a coordinator
# concern (one canonical implementation, applied uniformly across all
# clients) rather than per-client framework code. The 5 saga scenarios
# (C-0138..C-0142) and 3 PM scenarios (C-0143..C-0145) moved to
# `coordinator-contract/edition_propagation.feature` along with the
# rest of the coordinator-side specs (merge_strategy, fact_flow,
# state_building).
