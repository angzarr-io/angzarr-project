# Allocated: C-0138 .. C-0145
#
# Coordinator-contract feature: edition propagation across cross-domain
# emissions. Audit #86 originally landed this as per-client framework
# code (auto-stamping outgoing covers in `dispatch_saga` /
# `dispatch_process_manager`). User direction 2026-04-29: edition
# propagation belongs at the coordinator — one canonical
# implementation, universally applied across all clients regardless of
# language, rather than N copies of the same policy in N client
# libraries.
#
# The CONTRACT below holds at the coordinator level: when a saga or
# process-manager handler receives an event in edition X, the
# coordinator stamps edition X onto every outgoing CommandBook /
# EventBook (commands, events, facts, process_events) before
# persistence / dispatch downstream. The full Edition struct
# (name + divergences) propagates verbatim.
#
# **Always-override semantics:** the coordinator guarantees timeline
# consistency on cross-domain emissions; saga/PM handlers cannot
# escape into a different timeline by setting their own outgoing
# edition. Cross-timeline emission would need a separate
# fork-to-timeline mechanism out of scope here.
#
# **TESTED.** As of 2026-04-29 the coordinator implements the
# always-override contract via `Cover::propagate_edition_from`
# (`core/main/src/proto_ext/cover.rs`). Coverage of every outgoing
# book type (saga commands + events; PM commands + facts +
# process_events list) lives in the four orchestration sites:
# `core/main/src/orchestration/saga/{local,grpc}/mod.rs` and
# `core/main/src/orchestration/process_manager/{local,grpc}/mod.rs`.
#
# The 8 scenarios below are covered by Rust unit tests:
# - C-0138..C-0142 → `core/main/src/orchestration/saga/local/tests.rs`
#   (5 tests, one per scenario; drive `LocalSagaContext::handle` with
#   a stub `SagaHandler`).
# - C-0143..C-0145 + main-timeline + divergences + no-trigger-cover
#   → `core/main/src/orchestration/process_manager/local/tests.rs`
#   (7 tests; drive the shared
#   `propagate_trigger_edition` helper that both `LocalPMContext` and
#   `GrpcPMContext` delegate to). The helper-level test is sufficient
#   because the local + gRPC paths cannot drift — they both call the
#   same code.
#
# Step definitions for an end-to-end coordinator-tier cucumber runner
# are still queued (no such runner exists today; the unit tests are
# the authoritative coverage). When the runner is built, this file
# becomes its source of truth.
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
