Feature: Process manager delivery - one process manager per delivery
  When several process managers react to the same domain, each is its own
  component with its own stream and state. The coordinator delivers a
  trigger to each of them separately, naming the one it is for, with that
  one's process state, and keeps each answer to that one's own stream. It
  never asks one business call to answer for several process managers, and
  never merges their answers.

  Background:
    Given process managers "Fulfillment" and "Billing" are registered, both reacting to "order"

  @process_manager
  @C-0578
  Scenario: Each process manager reacting to a trigger gets its own delivery and its own state
    Given "Fulfillment" has process state "awaiting stock" and "Billing" has process state "awaiting payment"
    When an OrderPlaced event is recorded for order "order-1"
    Then "Fulfillment" receives the OrderPlaced trigger with its process state "awaiting stock"
    And "Billing" receives the OrderPlaced trigger with its process state "awaiting payment"
    And each answer's process events are appended to that process manager's own stream
    And each answer's process state is stored for that process manager alone
