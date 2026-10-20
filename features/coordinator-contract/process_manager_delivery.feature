Feature: Process manager delivery - each process manager behind its own coordinator
  A process manager is one component, served by its own business process
  behind its own coordinator. When several process managers react to the
  same domain, each one's coordinator delivers the trigger to it with its
  own process state, and keeps its answer to its own stream.

  @process_manager
  @C-0578
  Scenario: Two process managers reacting to one domain each get their own delivery and state
    Given process managers "Fulfillment" and "Billing", each behind its own coordinator, both reacting to "order"
    And "Fulfillment" has process state "awaiting stock" and "Billing" has process state "awaiting payment"
    When an OrderPlaced event is recorded for order "order-1"
    Then "Fulfillment"'s coordinator delivers the OrderPlaced trigger to "Fulfillment" with its process state "awaiting stock"
    And "Billing"'s coordinator delivers the OrderPlaced trigger to "Billing" with its process state "awaiting payment"
    And each answer's process events are appended to that process manager's own stream
    And each answer's process state is stored for that process manager alone
