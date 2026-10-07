# Coordinator-contract feature: edition propagation across cross-domain
# emissions. When a saga or process-manager handler receives an event in
# edition X, the coordinator stamps edition X onto every outgoing
# CommandBook / EventBook (commands, events, facts, process_events) before
# persistence or dispatch. The full Edition (name + divergences) propagates
# verbatim, and always overrides whatever edition the handler set.
#
# Main timeline: canonical name "angzarr" (DEFAULT_EDITION); "" and an
# unset Edition denote the same timeline.
#
# Coverage in core: Rust unit tests in
# src/orchestration/saga/local/tests.rs (C-0138..C-0142) and
# src/orchestration/process_manager/local/tests.rs (C-0143..C-0145).
Feature: Edition propagation across cross-domain emissions
  As a saga / process-manager author
  I want the framework to guarantee that emitted commands and events
  inherit the source / trigger cover's edition
  So that timeline consistency holds across cross-domain boundaries
  without requiring me to manually stamp every outgoing cover

  # ---------------------------------------------------------------
  # Saga: source event → outgoing commands / events
  # ---------------------------------------------------------------

  @C-0138
  Scenario: Saga propagates source edition to outgoing commands
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    And the saga handles OrderCreated by emitting a ReserveStock command
    And the source event has edition "speculative"
    When an OrderCreated event is dispatched to the saga
    Then the emitted command's cover has edition "speculative"

  @C-0139
  Scenario: Saga propagates source edition to outgoing events
    Given a saga "OrderAudit" translating from "order" to "audit"
    And the saga handles OrderCreated by emitting an OrderObserved event
    And the source event has edition "speculative"
    When an OrderCreated event is dispatched to the saga
    Then the emitted event's cover has edition "speculative"

  @C-0140
  Scenario: Coordinator always overrides handler-set edition with source edition
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    And the source event has edition "alpha"
    And the saga handler sets outgoing edition "beta"
    When an OrderCreated event is dispatched to the saga
    Then the persisted command's cover has edition "alpha"

  @C-0141
  Scenario: Saga propagates main-timeline (empty) edition unchanged
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    And the source event has no edition set
    When an OrderCreated event is dispatched to the saga
    Then the emitted command's cover has no edition set

  @C-0142
  Scenario: Saga propagation preserves source edition divergences
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    And the source event has edition "speculative" with divergence at "order"=5
    When an OrderCreated event is dispatched to the saga
    Then the emitted command's cover has edition "speculative" with divergence at "order"=5

  # ---------------------------------------------------------------
  # Process Manager: trigger event → outgoing commands / process_events
  # ---------------------------------------------------------------

  @C-0143
  Scenario: PM propagates trigger edition to outgoing commands
    Given a process manager "Fulfillment" with sources "order" and targets "shipping"
    And the trigger event has edition "speculative"
    When an OrderCreated trigger is dispatched to the PM
    Then the emitted command's cover has edition "speculative"

  @C-0144
  Scenario: PM propagates trigger edition to every emitted process_events book
    Given a process manager "Fulfillment" with sources "order" and targets "shipping"
    And the PM also emits an OrderTracked process_event on OrderCreated
    And the trigger event has edition "speculative"
    When an OrderCreated trigger is dispatched to the PM
    Then every emitted process_events book's cover has edition "speculative"

  @C-0145
  Scenario: Coordinator always overrides handler-set edition with trigger edition
    Given a process manager "Fulfillment" with sources "order" and targets "shipping"
    And the trigger event has edition "alpha"
    And the PM handler sets outgoing edition "beta"
    When an OrderCreated trigger is dispatched to the PM
    Then the persisted command's cover has edition "alpha"

  # ---------------------------------------------------------------
  # Main timeline: "" , unset and "angzarr" are one timeline
  # ---------------------------------------------------------------

  @C-0409
  Scenario Outline: Events written under one main-timeline spelling are read under every other
    Given an "order" aggregate "order-1" with 2 events written with edition <written>
    When the coordinator loads "order-1" with edition <read>
    Then the loaded history has 2 events
    And next_sequence is 2

    Examples:
      | written   | read      |
      | ""        | "angzarr" |
      | "angzarr" | ""        |
      | unset     | "angzarr" |
      | "angzarr" | unset     |

  @C-0410
  Scenario Outline: The main timeline cannot be deleted under either spelling
    Given an "order" aggregate "order-1" with 2 events on the main timeline
    When DeleteEditionEvents is requested for edition <edition> in domain "order"
    Then the request is refused because the main timeline is protected
    And the aggregate still has 2 events

    Examples:
      | edition   |
      | ""        |
      | "angzarr" |
