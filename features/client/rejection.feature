# Allocated: C-0040 .. C-0042
Feature: Rejection compensation
  When a downstream command is rejected, the originating component must be
  able to undo or compensate for the failure. Compensation handlers subscribe
  to specific rejections and emit events that reverse or mitigate the
  attempted side effect.

  # Why this exists:
  # - A rejected downstream command leaves the originator in an inconsistent
  #   state (funds debited but stock not reserved, for example)
  # - Compensation closes the loop without coupling the originator to the
  #   rejecting component
  # - Multiple originators may need to react to the same rejection
  #   independently (e.g. release funds AND notify the customer)
  #
  # What breaks if this is wrong:
  # - Funds, inventory, or reservations leak when downstream commands fail
  # - Compensation fires for the wrong rejection and undoes valid state
  # - Only one compensator runs when several distinct undoings are required
  #
  # Patterns exercised here:
  # - Targeted compensation: a rejection of a specific command from a specific
  #   domain triggers exactly the compensators registered for that pairing.
  # - Fan-out: multiple compensators for the same rejection all run, each
  #   producing its own compensating event.
  # - Selective routing: a rejection that no compensator subscribes to is a
  #   no-op - silence, not error.

  Background:
    Given Payment is a component in domain "payment"
    And Payment compensates a rejected ReserveStock from inventory by releasing funds
    And Payment is the active component

  @C-0040
  Scenario: A matching rejection fires the compensation
    When a rejection of ReserveStock arrives from inventory
    Then a FundsReleased event is emitted

  @C-0041
  Scenario: A rejection Payment does not compensate is ignored
    When a rejection of ProcessPayment arrives from inventory
    Then no events are emitted

  @C-0042
  Scenario: Multiple compensators for the same rejection all run
    Given a second compensation handler for the same rejection also releases funds
    And Payment then Payment2 are configured
    When a rejection of ReserveStock arrives from inventory
    Then two FundsReleased events are emitted in registration order
