Feature: Process manager delivery - each process manager behind its own coordinator
  A process manager is one component, served by its own business process
  behind its own coordinator. When several process managers react to the
  same domain, each one's coordinator delivers the trigger to it with its
  own process state, and keeps its answer to its own stream. A process
  manager takes in triggers and commands addressed to its own domain,
  records each as its own events, and sends no commands (decision 14.31).

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

  # ===========================================================================
  # Facts in, facts out (decision 14.31)
  # ===========================================================================
  # A process manager takes triggers, and commands addressed to its own
  # domain, and records each as its own events; it sends no commands. Its
  # instance is its correlation (decision 14.30). The correlation ids below
  # are UUIDs, as in every scenario (decision 14.18).

  @process_manager @pm_start
  @C-0592
  Scenario: A starting trigger for an unknown correlation starts an instance
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlaced trigger from "order" is a starting trigger
    And "Fulfillment" has no instance for correlation "0192a6b0-0000-7000-8000-000000000010"
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000010" is recorded for order "order-1"
    Then "Fulfillment"'s coordinator delivers the OrderPlaced trigger to "Fulfillment" with an empty process state
    And the process events are appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000010"

  @process_manager @pm_start
  @C-0593
  Scenario: A non-starting trigger for an unknown correlation is skipped
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlaced trigger from "order" is a starting trigger
    And "Fulfillment" also reacts to StockReserved from "inventory", which is not a starting trigger
    And "Fulfillment" has no instance for correlation "0192a6b0-0000-7000-8000-000000000011"
    When a StockReserved event with correlation "0192a6b0-0000-7000-8000-000000000011" is recorded
    Then "Fulfillment" is not called
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000011"
    And "Fulfillment"'s coordinator has advanced its position past the StockReserved event
    And nothing is dead-lettered and no alert is raised
    And the StockReserved event's source is not refused

  @process_manager @pm_start
  @C-0594
  Scenario: A non-starting trigger for an existing instance is delivered
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlaced trigger from "order" is a starting trigger
    And "Fulfillment" also reacts to StockReserved from "inventory", which is not a starting trigger
    And "Fulfillment" has an instance for correlation "0192a6b0-0000-7000-8000-000000000012" with process state "awaiting stock"
    When a StockReserved event with correlation "0192a6b0-0000-7000-8000-000000000012" is recorded
    Then "Fulfillment"'s coordinator delivers the StockReserved trigger to "Fulfillment" with its process state "awaiting stock"

  @process_manager @pm_start
  @C-0595
  Scenario: A command addressed to a process manager with no instance starts one
    Given a process manager "Fulfillment" owning domain "fulfillment" that handles the CancelFulfillment command
    And "Fulfillment" has no instance for correlation "0192a6b0-0000-7000-8000-000000000013"
    When a client sends CancelFulfillment to "fulfillment" root "0192a6b0-0000-7000-8000-000000000013"
    Then "Fulfillment" handles CancelFulfillment with an empty process state
    And the client is answered APPLIED with the process events

  @process_manager @pm_command
  @C-0596
  Scenario: A command addressed to a process manager is recorded, with its command id as the cause
    Given a process manager "Fulfillment" owning domain "fulfillment" that handles the CancelFulfillment command
    And "Fulfillment" has an instance for correlation "0192a6b0-0000-7000-8000-000000000014" with process state "awaiting stock"
    When a client sends CancelFulfillment with command_id "0192a6b0-0000-7000-8000-0000000000c1" and no correlation_id to "fulfillment" root "0192a6b0-0000-7000-8000-000000000014"
    Then each process event records causation command_id "0192a6b0-0000-7000-8000-0000000000c1"
    And each process event records correlation_id "0192a6b0-0000-7000-8000-000000000014"
    And no process event records a triggering_event
    And the client is answered APPLIED

  @process_manager @pm_command
  @C-0597
  Scenario: A redelivered command addressed to a process manager is answered from its stored events
    Given a process manager "Fulfillment" owning domain "fulfillment" that handles the CancelFulfillment command
    And CancelFulfillment with command_id "0192a6b0-0000-7000-8000-0000000000c2" has been recorded by "Fulfillment" for correlation "0192a6b0-0000-7000-8000-000000000015"
    When the same CancelFulfillment is sent again
    Then "Fulfillment" is not called
    And the sender is answered DUPLICATE with the stored process events

  @process_manager @pm_command
  @C-0598
  Scenario Outline: A malformed command addressed to a process manager is refused before the handler runs
    Given a process manager "Fulfillment" owning domain "fulfillment" that handles the CancelFulfillment command
    When a client sends CancelFulfillment to "fulfillment" root "0192a6b0-0000-7000-8000-000000000016" with <malformation>
    Then the client is answered INVALID_ARGUMENT
    And "Fulfillment" is not called
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000016"

    Examples:
      | malformation                                                       |
      | Handling.expected_sequence 3                                       |
      | Handling.conflict_resolution STRICT                                |
      | correlation_id "0192a6b0-0000-7000-8000-000000000099"              |

  @process_manager @pm_failure
  @C-0599
  Scenario: A failing handler for a command addressed to a process manager parks it
    Given a process manager "Fulfillment" owning domain "fulfillment" that handles the CancelFulfillment command
    And "Fulfillment"'s CancelFulfillment handler fails with INTERNAL
    When a client sends CancelFulfillment to "fulfillment" root "0192a6b0-0000-7000-8000-000000000017"
    Then the client is answered OK with delivery PARKED and no events
    And the command is dead-lettered and an alert is raised
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000017"

  @process_manager @pm_failure
  @C-0600
  Scenario: A failing handler for a trigger is dead-lettered and alerted
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlaced trigger from "order" is a starting trigger
    And "Fulfillment"'s OrderPlaced handler fails with INTERNAL
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000018" is recorded for order "order-1"
    Then the trigger is dead-lettered and an alert is raised
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000018"

  @process_manager @pm_dedup
  @C-0601
  Scenario: A redelivered trigger is deduplicated before the handler runs
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlaced trigger from "order" is a starting trigger
    And "Fulfillment" has recorded process events for the OrderPlaced event at sequence 0 of order "order-1"
    When that OrderPlaced event is delivered to "Fulfillment"'s coordinator again
    Then "Fulfillment" is not called
    And nothing is appended to "Fulfillment"'s stream
    And the trigger-caused process events record that event's EventRef as their triggering_event and no command_id

  @process_manager @pm_trigger_page
  @C-0602
  Scenario: The trigger is the last page of the trigger book
    # Drafter's proposal in decision 14.31, not yet ruled.
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlaced trigger from "order" is a starting trigger
    When "Fulfillment"'s coordinator is handed a trigger book for order "order-1" with pages at sequences 0, 1 and 2, the last an OrderPlaced event
    Then the process events record the EventRef of order "order-1" sequence 2 as their triggering_event

  @process_manager @pm_output
  @C-0603
  Scenario: A process manager's decision reaches another domain through a saga
    Given a process manager "Fulfillment" owning domain "fulfillment" that records a ShipmentRequested event on OrderPlaced
    And a saga "FulfillmentToShipping" translating from "fulfillment" to "shipping" that builds a CreateShipment command from ShipmentRequested
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000019" is recorded for order "order-1"
    Then "Fulfillment" sends no command
    And "FulfillmentToShipping" delivers CreateShipment to "shipping" with correlation "0192a6b0-0000-7000-8000-000000000019"
