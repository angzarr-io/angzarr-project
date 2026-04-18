# Allocated: C-0080 .. C-0084
Feature: Rejection compensation details
  As a framework user
  I want @rejected compensation handlers to receive accurate state and routing
  So that compensating actions can make informed decisions, not just fire blindly

  Builds on the basic rejection routing in rejection.feature. These scenarios
  cover state rebuild, routing across multiple @rejected methods on one class,
  sequence stamping, and the empty-handler case.

  @C-0080
  Scenario: State is rebuilt before the @rejected handler runs
    Given a command handler "Payment" for domain "payment" with stateful rejection
    And Payment @applies FundsDeposited by setting state.bankroll
    And Payment has a @rejected("inventory", "ReserveStock") handler that emits FundsReleased carrying state.bankroll
    And the router is built with the Payment handler
    And a prior EventBook with a FundsDeposited event of bankroll 100
    When a Notification wrapping a rejected ReserveStock in domain "inventory" is dispatched
    Then the response contains one FundsReleased event
    And the FundsReleased event carries amount 100

  @C-0081
  Scenario: @rejected methods route by (source_domain, command) pair
    Given a command handler "Payment" for domain "payment" with two @rejected handlers
    And Payment has a @rejected("inventory", "ReserveStock") handler emitting FundsReleased
    And Payment has a @rejected("payment", "ProcessPayment") handler emitting WorkflowFailed
    And the router is built with the Payment handler
    When a Notification wrapping a rejected ProcessPayment in domain "payment" is dispatched
    Then the response contains one WorkflowFailed event
    And no FundsReleased event is emitted

  @C-0082
  Scenario: Multiple @rejected methods on one class do not cross-fire
    Given a command handler "Payment" for domain "payment" with two @rejected handlers
    And Payment has a @rejected("inventory", "ReserveStock") handler emitting FundsReleased
    And Payment has a @rejected("payment", "ProcessPayment") handler emitting WorkflowFailed
    And the router is built with the Payment handler
    When a Notification wrapping a rejected CreateShipment in domain "fulfillment" is dispatched
    Then the response contains no events

  @C-0083
  Scenario: Compensation events receive framework-stamped sequences
    Given a command handler "Payment" for domain "payment" with stateful rejection
    And Payment has a @rejected("inventory", "ReserveStock") handler emitting two FundsReleased events
    And the router is built with the Payment handler
    And a prior EventBook whose next_sequence is 7
    When a Notification wrapping a rejected ReserveStock in domain "inventory" is dispatched
    Then the emitted pages carry sequences [7, 8]

  @C-0084
  Scenario: No matching @rejected handler yields empty compensation
    Given a command handler "Payment" for domain "payment" with no rejection handlers
    And the router is built with the Payment handler
    When a Notification wrapping a rejected ReserveStock in domain "inventory" is dispatched
    Then the response contains no events
