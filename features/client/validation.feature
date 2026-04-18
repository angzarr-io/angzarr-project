# Allocated: C-0070 .. C-0077
Feature: Decorator validation
  As a framework user
  I want misconfigured class and method decorators to fail fast
  So that typos and omissions surface at declaration or build time, not during dispatch

  Missing required fields may surface at declaration time or at build time
  depending on the language's type system. Either is acceptable — the scenario
  asserts only that the error happens before dispatch.

  @C-0070
  Scenario: @command_handler without state is rejected
    When I declare a @command_handler for domain "order" without state
    Then the declaration raises a configuration error

  @C-0071
  Scenario: @saga without target is rejected
    When I declare a @saga named "x" from "order" without target
    Then the declaration raises a configuration error

  @C-0072
  Scenario: @process_manager without pm_domain is rejected
    When I declare a @process_manager for name "x" without pm_domain
    Then the declaration raises a configuration error

  @C-0073
  Scenario: @process_manager without sources is rejected
    When I declare a @process_manager for name "x" without sources
    Then the declaration raises a configuration error

  @C-0074
  Scenario: @process_manager without targets is rejected
    When I declare a @process_manager for name "x" without targets
    Then the declaration raises a configuration error

  @C-0075
  Scenario: @projector without domains is rejected
    When I declare a @projector named "x" without domains
    Then the declaration raises a configuration error

  @C-0076
  Scenario: Stacking two class decorators on one class fails
    Given a class Order
    And Order has the @command_handler decorator applied
    When I also apply the @saga decorator to Order
    Then the declaration raises a configuration error

  @C-0077
  Scenario: Stacking conflicting method decorators on one method fails
    Given a method "handle_create" with the @handles decorator applied
    When I also apply the @applies decorator to "handle_create"
    Then the declaration raises a configuration error
