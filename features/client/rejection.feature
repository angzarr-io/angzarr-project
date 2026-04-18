# Allocated: C-0040 .. C-0042
Feature: Rejection compensation
  As an originating component author
  I want rejection notifications routed to @rejected handlers for compensation
  So that a rejected downstream command can be undone or side-effected

  Background:
    Given a command handler "Payment" for domain "payment" with state PaymentState
    And Payment has a @rejected("inventory", "ReserveStock") handler emitting FundsReleased
    And the router is built with the Payment handler

  @C-0040
  Scenario: Matching rejection fires the compensation handler
    When a Notification wrapping a rejected ReserveStock in domain "inventory" is dispatched
    Then the response contains one FundsReleased event

  @C-0041
  Scenario: Non-matching rejection produces no compensation
    When a Notification wrapping a rejected ProcessPayment in domain "inventory" is dispatched
    Then the response contains no events

  @C-0042
  Scenario: Multiple rejection handlers for the same key all fire
    Given a second Payment handler Payment2 with the same @rejected key emitting FundsReleased
    And the router is built with Payment then Payment2
    When a Notification wrapping a rejected ReserveStock in domain "inventory" is dispatched
    Then the response contains two FundsReleased events in registration order
