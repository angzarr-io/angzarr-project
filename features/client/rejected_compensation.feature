# Allocated: C-0080 .. C-0084
Feature: Rejection compensation details
  As a framework user
  I want compensation handlers to receive accurate state and routing
  So that compensating actions can make informed decisions, not just fire blindly

  Builds on the basic rejection routing in rejection.feature. These scenarios
  cover state rebuild, routing across multiple compensation handlers on one
  class, sequence stamping, and the empty-handler case.

  @wip
  @C-0080
  Scenario: State is rebuilt before the compensation handler runs
    Given a command handler "Payment" for domain "payment" with stateful rejection
    And deposits update Payment's bankroll
    And Payment compensates a rejected ReserveStock from inventory by emitting FundsReleased with the current bankroll
    And Payment is configured
    And a prior history with a FundsDeposited event of bankroll 100
    When a rejection of ReserveStock arrives from inventory
    Then the response contains one FundsReleased event
    And the FundsReleased event carries amount 100

  @wip
  @C-0081
  Scenario: Compensation handlers route by (source_domain, command) pair
    Given a command handler "Payment" for domain "payment" with two compensation handlers
    And Payment compensates a rejected ReserveStock from inventory by emitting FundsReleased
    And Payment compensates a rejected ProcessPayment from payment by emitting WorkflowFailed
    And Payment is configured
    When a rejection of ProcessPayment arrives from payment
    Then the response contains one WorkflowFailed event
    And no FundsReleased event is emitted

  @wip
  @C-0082
  Scenario: Multiple compensation handlers on one class do not cross-fire
    Given a command handler "Payment" for domain "payment" with two compensation handlers
    And Payment compensates a rejected ReserveStock from inventory by emitting FundsReleased
    And Payment compensates a rejected ProcessPayment from payment by emitting WorkflowFailed
    And Payment is configured
    When a rejection of CreateShipment arrives from fulfillment
    Then the response contains no events

  @wip
  @C-0083
  Scenario: Compensation events are appended in sequence after prior history
    Given a command handler "Payment" for domain "payment" with stateful rejection
    And Payment compensates a rejected ReserveStock from inventory by emitting two FundsReleased events
    And Payment is configured
    And a prior history ending at sequence 6
    When a rejection of ReserveStock arrives from inventory
    Then compensation events are appended after sequence 6, taking sequences 7 and 8

  @wip
  @C-0084
  Scenario: No matching compensation handler yields empty compensation
    Given a command handler "Payment" for domain "payment" with no rejection handlers
    And Payment is configured
    When a rejection of ReserveStock arrives from inventory
    Then the response contains no events
