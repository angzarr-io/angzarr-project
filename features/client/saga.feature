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
  Scenario: Saga observes the destination heads supplied with the request
    Given destination sequences inventory=7 and fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the saga observed destination inventory = 7
    And the saga observed destination fulfillment = 3

  @C-0053
  Scenario: Saga emitting to two target domains records each domain's head as its basis
    Given a saga "OrderSplit" translating from "order" to "inventory" and "fulfillment"
    And the saga handles OrderCreated by emitting a ReserveStock for "inventory" and a CreateShipment for "fulfillment"
    And destination sequences inventory=7 and fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the ReserveStock command carries an angzarr_deferred header with basis_seq 7
    And the CreateShipment command carries an angzarr_deferred header with basis_seq 3

  # ---------------------------------------------------------------------------
  # Emitted commands are deferred: provenance, not an explicit sequence
  # ---------------------------------------------------------------------------
  # Saga commands carry PageHeader.angzarr_deferred. The router records the
  # triggering event (source cover + source_seq), the command's position in
  # the output (command_index) and the observed destination head (basis_seq);
  # the framework assigns the concrete destination sequence on delivery.

  @C-0177
  Scenario: Saga command records the triggering event as its source
    Given destination sequences inventory=7
    And the OrderCreated event is at sequence 4 of order root "order-1"
    When the OrderCreated event is dispatched to the saga router
    Then the ReserveStock command carries an angzarr_deferred header
    And the deferred source cover is domain "order" root "order-1"
    And the deferred source_seq is 4
    And the deferred command_index is 0
    And the deferred basis_seq is 7

  @C-0178
  Scenario: Saga command never carries an explicit sequence
    Given destination sequences inventory=7
    When an OrderCreated event is dispatched to the saga router
    Then no page of the ReserveStock command has an explicit sequence

  @C-0179
  Scenario: Saga commands are indexed in emission order
    Given a saga "OrderSplit" translating from "order" to "inventory" and "fulfillment"
    And the saga handles OrderCreated by emitting a ReserveStock for "inventory" and a CreateShipment for "fulfillment"
    And destination sequences inventory=7 and fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the ReserveStock command's deferred command_index is 0
    And the CreateShipment command's deferred command_index is 1

  @C-0180
  Scenario: Saga command for a domain without a supplied head has basis_seq 0
    Given destination sequences fulfillment=3
    When an OrderCreated event is dispatched to the saga router
    Then the ReserveStock command carries an angzarr_deferred header with basis_seq 0
