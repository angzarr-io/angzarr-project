# Allocated: C-0010 .. C-0015, C-0087
#
# Audit finding #18 (formerly #51): multi-handler CommandHandler dispatch
# is FORBIDDEN. Two CommandHandlers may not register for the same
# (domain, command_type_url) pair within one Router — the builder
# rejects duplicates at build time. Saga / PM / projector fan-out is
# unaffected (those kinds legitimately broadcast).
Feature: Multi-handler dispatch
  The Router enforces that exactly one CommandHandler owns a given
  (domain, command_type) pair, while sagas, process managers, and projectors
  may legitimately fan out — every matching handler runs once per dispatch.

  # Why this constraint exists:
  # - CommandHandlers mutate aggregate state; two handlers claiming the same
  #   command would produce ambiguous, non-deterministic outcomes
  # - Sagas / PMs / projectors are read-side or coordination concerns; multiple
  #   reactors to the same event is the normal, intended pattern
  #
  # What breaks if this is wrong:
  # - Silent duplicate CH registration: commands routed to an arbitrary handler,
  #   state diverges across deployments
  # - Saga/PM/projector under-fan-out: downstream effects (stock reservation,
  #   shipment creation, read-model updates) silently dropped
  # - Saga/PM over-fan-out: same effect emitted N times per matching handler
  #   method, producing duplicate commands

  # ==========================================================================
  # CommandHandler uniqueness — build-time enforcement
  # ==========================================================================
  # Duplicate (domain, command_type) CH registrations must fail loudly at
  # router build, not at dispatch. Same command_type under different domains
  # is fine; one CH handling many command types is fine.

  @C-0010
  Scenario: Router rejects duplicate CommandHandler registration
    Given two command handlers Alpha and Beta for domain "order"
    And both handle CreateOrder
    When the router is built with Alpha then Beta
    Then registration is rejected because two command handlers claim CreateOrder in "order"

  @C-0011
  Scenario: Router accepts CommandHandlers in different domains for same command type
    Given a command handler Alpha for domain "orderA" handling CreateOrder
    And a command handler Beta for domain "orderB" handling CreateOrder
    When the router is built with Alpha then Beta across domains
    Then the configuration is accepted

  @C-0012
  Scenario: Router accepts a single CommandHandler with multiple handled types
    Given a command handler Player for domain "player" handling RegisterPlayer and DepositFunds
    When the router is built with Player
    Then the configuration is accepted

  # ==========================================================================
  # Saga / PM / Projector fan-out — every matching handler runs
  # ==========================================================================
  # Unlike CHs, multiple sagas, PMs, or projectors may legitimately react to
  # the same event. Each matching handler is invoked, and commands emerge in
  # registration order so downstream effects are deterministic.

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

  # ==========================================================================
  # Fan-out arity — each saga handles the event once, not once per method
  # ==========================================================================
  # Audit #18 reframe: the original C-0087 asserted factory invocation counts
  # on multi-handler CH dispatch. CH multi-handler is now forbidden, so the
  # remaining "N matching handlers, each fires once" surface is saga (and
  # PM/projector, already covered above). A saga with multiple matching
  # handler methods must still be dispatched to once per event — not once
  # per matching method — otherwise downstream commands duplicate.

  @C-0087
  Scenario: Each saga handles the event once, not once per matching handler method
    Given two sagas SagaA and SagaB both listening to source "order" for OrderCreated
    And the saga router is built with SagaA then SagaB
    When an OrderCreated event is dispatched to the saga router
    Then each saga handles the event exactly once
