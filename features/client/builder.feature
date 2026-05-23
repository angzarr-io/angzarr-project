# Allocated: C-0060 .. C-0065, C-0088
Feature: Building a handler routing configuration
  As a framework user
  I want the handler registry to catch misconfiguration before dispatch
  So that misconfiguration surfaces with a clear error, not a cryptic runtime failure

  @C-0060
  Scenario: Empty configuration fails to build
    Given an empty handler configuration
    When I build the router
    Then the configuration is rejected because no handlers are registered

  @C-0061
  Scenario: An unmarked component cannot be registered as a handler
    Given a component that has not been marked as a handler kind
    When I attempt to register it
    Then the configuration is rejected because the component is not a recognised handler

  @C-0062
  Scenario: Command handlers for distinct domains build a command-handling router
    Given a command handler "Order" for domain "order" with order state
    And another command handler "Payment" for domain "payment" with payment state
    When I build the router
    Then the result routes commands to their handlers

  @C-0063
  Scenario: Mixed handler kinds are rejected
    Given a command handler "Order" for domain "order" with order state
    And a saga "OrderFulfillment" translating from "order" to "inventory"
    When I build the router
    Then the configuration is rejected for mixing handler kinds

  @C-0064
  Scenario: Two command handlers for the same domain and command pair are rejected at build time
    # Audit finding #18 (formerly #51): multi-handler command dispatch is
    # forbidden. Two command handlers may not register for the same
    # domain/command pair within one configuration. Build fails with a
    # duplicate-handler error. Saga / PM / projector / upcaster fan-out
    # is unaffected (those kinds legitimately broadcast — see
    # multi_handler.feature C-0013..C-0015).
    Given two command handlers Alpha and Beta for domain "order" both handling the same command
    When I build the router
    Then the configuration is rejected because two command handlers share the same domain and command

  @C-0065
  Scenario: Each registered handler is introspected at most once at build time
    # Audit #18: the build step inspects each command handler once to
    # collect its configuration (handled commands + domain) for the
    # duplicate-detection pass. After build, the handler is exercised
    # once per dispatch, not at registration.
    Given a command handler "Order" for domain "order" with order state
    And the handler reports how many times it has been introspected
    When I register the handler and build the router
    Then the handler has been introspected exactly once

  @C-0088
  Scenario: A single saga handler builds a saga-routing router
    Given a saga "OrderFulfillment" translating from "order" to "inventory"
    When I build the router
    Then the result routes saga notifications to their handlers
