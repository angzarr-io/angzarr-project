# Allocated: C-0050 .. C-0053, C-0138 .. C-0142
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

  # Audit #86: edition propagation. When a saga reacts to an event, every
  # outgoing CommandBook / EventBook inherits the source cover's edition
  # so the timeline stays consistent across the cross-domain boundary.
  # Semantics are **always-override**: the framework guarantees propagation
  # even if the handler set a different edition on the outgoing cover.

  @C-0138
  Scenario: Saga propagates source edition to outgoing commands
    Given the source event has edition "speculative"
    When an OrderCreated event is dispatched to the saga router
    Then the emitted command's cover has edition "speculative"

  @C-0139
  Scenario: Saga propagates source edition to outgoing events
    Given a saga "OrderAudit" translating from "order" to "audit"
    And the saga handles OrderCreated by emitting an OrderObserved event
    And the router is built with the OrderAudit saga
    And the source event has edition "speculative"
    When an OrderCreated event is dispatched to the saga router
    Then the emitted event's cover has edition "speculative"

  @C-0140
  Scenario: Saga always overrides handler-set edition with source edition
    Given the source event has edition "alpha"
    And the saga handler sets outgoing edition "beta"
    When an OrderCreated event is dispatched to the saga router
    Then the emitted command's cover has edition "alpha"

  @C-0141
  Scenario: Saga propagates main-timeline (empty) edition unchanged
    Given the source event has no edition set
    When an OrderCreated event is dispatched to the saga router
    Then the emitted command's cover has no edition set

  @C-0142
  Scenario: Saga propagation preserves source edition divergences
    Given the source event has edition "speculative" with divergence at "order"=5
    When an OrderCreated event is dispatched to the saga router
    Then the emitted command's cover has edition "speculative" with divergence at "order"=5
