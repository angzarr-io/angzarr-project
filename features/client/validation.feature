# Allocated: C-0070 .. C-0077
Feature: Handler declaration validation
  As a framework user
  I want misconfigured handlers to fail fast at declaration or build time
  So that typos and omissions surface before dispatch

  Missing required fields may surface at declaration time or at build time
  depending on the language's type system. Either is acceptable — the scenario
  asserts only that the error happens before dispatch.

  @C-0070
  Scenario: An aggregate handler without state is rejected
    When I declare an aggregate handler for domain "order" without state
    Then the declaration raises a configuration error

  @C-0071
  Scenario: A saga without target is rejected
    When I declare a saga named "x" from "order" without target
    Then the declaration raises a configuration error

  @C-0072
  Scenario: A process manager without pm_domain is rejected
    When I declare a process manager for name "x" without pm_domain
    Then the declaration raises a configuration error

  @C-0073
  Scenario: A process manager without sources is rejected
    When I declare a process manager for name "x" without sources
    Then the declaration raises a configuration error

  @C-0074
  Scenario: A process manager without targets is rejected
    When I declare a process manager for name "x" without targets
    Then the declaration raises a configuration error

  @C-0075
  Scenario: A projector without domains is rejected
    When I declare a projector named "x" without domains
    Then the declaration raises a configuration error

  @C-0076
  Scenario: A class cannot be both an aggregate handler and a saga
    Given a class Order
    And Order is declared as an aggregate handler
    When I also declare Order as a saga
    Then the declaration raises a configuration error

  @C-0077
  Scenario: A method cannot both handle a command and apply an event
    Given a method "handle_create" declared as a command handler
    When I also declare "handle_create" as an event applier
    Then the declaration raises a configuration error
