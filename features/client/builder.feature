# Allocated: C-0060 .. C-0065, C-0088
Feature: Router builder
  As a framework user
  I want the Router builder to catch configuration errors before dispatch
  So that misconfiguration surfaces with a clear error, not a cryptic runtime failure

  @C-0060
  Scenario: Empty builder fails to build
    Given an empty Router named "empty"
    When I build the router
    Then the builder raises a BuildError mentioning "no handlers"

  @C-0061
  Scenario: Registering an undecorated class is rejected
    Given a class "NotDecorated" with no kind decorator
    When I register it with a factory
    Then the builder raises a BuildError mentioning "NotDecorated"

  @C-0062
  Scenario: Homogeneous factories build a runtime router of the matching kind
    Given a command handler "Order" for domain "order" with state OrderState
    And another command handler "Payment" for domain "payment" with state PaymentState
    When I build the router
    Then the result is a CommandHandlerRouter

  @C-0063
  Scenario: Mixed handler kinds are rejected
    Given a command handler "Order" for domain "order" with state OrderState
    And a saga "OrderFulfillment" translating from "order" to "inventory"
    When I build the router
    Then the builder raises a BuildError mentioning "cannot mix"

  @C-0064
  Scenario: Duplicate (domain, type_url) across CommandHandlers is rejected at build time
    # Audit finding #18 (formerly #51): multi-handler CH dispatch is
    # forbidden. Two CommandHandlers may not register for the same
    # (domain, command_type_url) pair within one Router. Build fails
    # with DuplicateCommandHandler. Saga / PM / projector / upcaster
    # fan-out is unaffected (those kinds legitimately broadcast — see
    # multi_handler.feature C-0013..C-0015).
    Given two command handlers Alpha and Beta for domain "order" both handling CreateOrder
    When I build the router
    Then the builder raises a BuildError mentioning "duplicate command handler"

  @C-0065
  Scenario: Factories are invoked at most once per registered handler at build time
    # Audit #18: the builder calls each CommandHandler factory once at
    # build time to introspect its config (handled type URLs + domain)
    # for the duplicate-detection pass. After build, each factory is
    # called once per dispatch, not at registration.
    Given a command handler "Order" for domain "order" with state OrderState
    And a factory that counts invocations
    When I register the handler and build the router
    Then the factory invocation count is 1

  @C-0088
  Scenario: Single saga handler builds into the SagaRouter variant
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    When I build the router
    Then the result is a SagaRouter
