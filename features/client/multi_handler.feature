# Allocated: C-0010 .. C-0015, C-0087
#
# Audit finding #18 (formerly #51): multi-handler CommandHandler dispatch
# is FORBIDDEN. Two CommandHandlers may not register for the same
# (domain, command_type_url) pair within one Router — the builder
# rejects duplicates at build time. Saga / PM / projector fan-out is
# unaffected (those kinds legitimately broadcast).
Feature: Multi-handler dispatch
  As a unified-Router user
  I want sagas, PMs, and projectors that share an event source to ALL run
  And I want CommandHandler duplicates to fail loudly at build time
  So that fan-out cross-cutting concerns work without ambiguous CH semantics

  @C-0010
  Scenario: Router rejects duplicate CommandHandler registration
    Given two command handlers Alpha and Beta for domain "order"
    And both handle CreateOrder
    When the router is built with Alpha then Beta
    Then build fails with DuplicateCommandHandler for domain "order" and CreateOrder

  @C-0011
  Scenario: Router accepts CommandHandlers in different domains for same command type
    Given a command handler Alpha for domain "orderA" handling CreateOrder
    And a command handler Beta for domain "orderB" handling CreateOrder
    When the router is built with Alpha then Beta across domains
    Then build succeeds with a CommandHandlerRouter

  @C-0012
  Scenario: Router accepts a single CommandHandler with multiple handled types
    Given a command handler Player for domain "player" handling RegisterPlayer and DepositFunds
    When the router is built with Player
    Then build succeeds with a CommandHandlerRouter

  @C-0013
  Scenario: Saga multi-handler merge — all matching sagas invoked
    Given two sagas SagaA and SagaB both listening to source "order" for OrderCreated
    And SagaA emits a ReserveStock command for "inventory"
    And SagaB emits a CreateShipment command for "fulfillment"
    And the saga router is built with SagaA then SagaB
    When an OrderCreated event is dispatched to the saga router
    Then the response contains two commands in registration order
    And the first command targets the "inventory" domain
    And the second command targets the "fulfillment" domain

  @C-0014
  Scenario: Process manager multi-handler merge — all matching PMs invoked
    Given two process managers PMA and PMB both sourcing from "order" and handling OrderCreated
    And PMA emits a ReserveStock command
    And PMB emits a CreateShipment command
    And the PM router is built with PMA then PMB
    When an OrderCreated trigger is dispatched to the PM router
    Then the response contains two commands in registration order

  @C-0015
  Scenario: Projector multi-handler fan-out — each projector runs its side effects
    Given two projectors ProjA and ProjB both consuming domain "order"
    And ProjA appends to a log on OrderCreated
    And ProjB appends to a different log on OrderCreated
    And the projector router is built with ProjA then ProjB
    When an EventBook with one OrderCreated event is dispatched
    Then ProjA's log has 1 entry
    And ProjB's log has 1 entry

  @C-0087
  Scenario: Each matched factory invoked exactly once per dispatch (saga fan-out)
    # Audit #18 reframe: the original C-0087 asserted factory invocation
    # counts on multi-handler CH dispatch. CH multi-handler is now
    # forbidden, so the only remaining "multi-handler dispatch with N
    # factories invoked exactly once" surface is saga (and PM/projector,
    # already covered above).
    Given two sagas SagaA and SagaB both listening to source "order" for OrderCreated
    And each saga factory counts invocations
    And the saga router is built with SagaA then SagaB
    When an OrderCreated event is dispatched to the saga router
    Then SagaA's factory was invoked exactly 1 time
    And SagaB's factory was invoked exactly 1 time
