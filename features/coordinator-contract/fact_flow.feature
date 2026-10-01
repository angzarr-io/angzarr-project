Feature: Fact injection from sagas and process managers

  Sagas and process managers can emit facts (events) that are injected
  directly into target aggregates without going through command handling.
  Facts ARE sequenced and persisted to the event store - they differ from
  commands only in that they bypass validation and cannot be rejected.

  The receiving aggregate declares which event types it accepts as facts
  (ComponentOptions.facts); each is handled by its fact handler, which
  records the fact and may add events that flag it but cannot refuse it.
  A fact of an undeclared type is a wiring error: refused with
  INVALID_ARGUMENT / NO_FACT_HANDLER and nothing is persisted.

  Facts vs Commands vs Notifications:
  - Commands: Sequenced, validated, can be rejected
  - Facts: Sequenced, recorded by a declared fact handler, cannot be rejected
  - Notifications: NOT sequenced, used for coordination (e.g., compensation)

  Facts represent external realities:
  - Events that have already occurred elsewhere
  - State that the aggregate has no authority to reject
  - Cross-domain propagation where validation doesn't apply

  Sequences are 0-based: an aggregate with N events has next_sequence N.

  Background:
    Given the order aggregate declares facts ShipmentDispatched and PaymentCaptured
    And the inventory aggregate declares fact StockHoldRequested

  # ---------------------------------------------------------------------------
  # Cross-domain reality: the receiving aggregate records, never rejects
  # ---------------------------------------------------------------------------

  @C-0184
  Scenario: Saga injects a ShipmentDispatched fact into the order aggregate
    Given an order "order-1" awaiting shipment
    And a saga "ShippingToOrder" translating from "shipping" to "order"
    When the shipping aggregate emits ShipmentDispatched for order "order-1"
    Then a ShipmentDispatched fact is injected into the "order" aggregate "order-1"
    And the fact is appended at the order's next sequence
    And the order records the shipment as dispatched

  @C-0185
  Scenario: Fact receives the next sequence number
    Given an "order" aggregate with 3 existing events
    When a ShipmentDispatched fact is injected
    Then the fact is persisted with sequence number 3
    And subsequent events continue from sequence 4

  @C-0186
  Scenario: Fact is recorded even when a command with the same intent would be refused
    Given an order "order-2" that has been cancelled
    When a PaymentCaptured fact is injected into the "order" aggregate "order-2"
    Then the fact is persisted at the order's next sequence
    And no rejection is produced

  @C-0187
  Scenario: Process manager injects a fact alongside its commands
    Given a process manager "Fulfillment" with sources "order" and targets "inventory"
    And the PM handles OrderCreated by emitting a ReserveStock command and a StockHoldRequested fact
    When an OrderCreated trigger is dispatched to the PM
    Then the ReserveStock command is delivered to "inventory"
    And a StockHoldRequested fact is persisted in the "inventory" aggregate

  # ---------------------------------------------------------------------------
  # Fact metadata requirements
  # ---------------------------------------------------------------------------

  @C-0188
  Scenario: Fact carries required metadata
    Given a saga that emits a fact
    When the fact is constructed
    Then the fact Cover has domain set to the target aggregate
    And the fact Cover has root set to the target aggregate root
    And the fact Cover has correlation_id for traceability
    And every fact page header has external_deferred.external_id set for idempotency

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  @C-0189
  Scenario: Fact injection failure fails the saga
    Given a saga that emits a fact to domain "nonexistent"
    When the saga processes an event
    Then the saga fails because the target domain does not exist
    And no commands from that saga are executed

  @C-0492
  Scenario: A fact of a type the aggregate does not declare is refused and nothing is persisted
    Given an "order" aggregate with 3 existing events
    When an OrderRefunded fact with external_id "refund-R1" is injected into the "order" aggregate
    Then the injection fails with INVALID_ARGUMENT and angzarr error code NO_FACT_HANDLER
    And the "order" aggregate still has 3 events
    And external_id "refund-R1" is not recorded as processed

  @C-0493
  Scenario: A saga's refused fact fails the saga without retries
    Given a saga "ShippingToOrder" translating from "shipping" to "order" that emits an OrderRefunded fact
    When the shipping aggregate emits ShipmentReturned for order "order-1"
    Then the saga handler is attempted once
    And a dead letter is published to "angzarr.dlq.shipping"
    And the dead letter's event_processing_failed details have is_transient false and retry_count 0
    And no event is persisted to "order" aggregate "order-1"

  @C-0190
  Scenario: Duplicate fact with same external_id is idempotent
    Given a fact with external_id "shipment-S1-dispatched"
    When the same fact is injected twice
    Then only one event is stored in the aggregate
    And the second injection reports already_processed
