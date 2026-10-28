Feature: Process manager delivery - facts only, each process manager behind its own coordinator
  A process manager is one component, served by its own business process
  behind its own coordinator. Its only input is facts addressed to it,
  whose cover root names the instance (its correlation). It subscribes to
  no domain: the events of other domains reach it as facts that sagas
  build. It takes no commands, records each fact as its own events, never
  refuses one, and sends no commands (decision 14.31). The correlation ids
  below are UUIDs, as in every scenario (decision 14.18).

  @process_manager
  @C-0578
  Scenario: Two process managers told of one event each get their own delivery and state
    Given process managers "Fulfillment" and "Billing", each behind its own coordinator
    And a saga from "order" to "Fulfillment"'s domain and a saga from "order" to "Billing"'s domain, each turning OrderPlaced into a fact
    And "Fulfillment" has process state "awaiting stock" and "Billing" has process state "awaiting payment" for the order's correlation
    When an OrderPlaced event is recorded for order "order-1"
    Then "Fulfillment"'s coordinator delivers its fact to "Fulfillment" with its process state "awaiting stock"
    And "Billing"'s coordinator delivers its fact to "Billing" with its process state "awaiting payment"
    And each answer's process events are appended to that process manager's own stream
    And each answer's process state is stored for that process manager alone

  # ===========================================================================
  # Starting an instance (ruling B1, adapted to facts)
  # ===========================================================================

  @process_manager @pm_start
  @C-0592
  Scenario: A starting fact for an unknown correlation starts an instance
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And "Fulfillment" has no instance for correlation "0192a6b0-0000-7000-8000-000000000010"
    When an OrderPlacedReported fact is sent to "fulfillment" root "0192a6b0-0000-7000-8000-000000000010"
    Then "Fulfillment"'s coordinator delivers the fact to "Fulfillment" with an empty process state
    And the process events are appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000010"

  @process_manager @pm_start
  @C-0593
  Scenario: A non-starting fact for an unknown correlation is skipped silently
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And "Fulfillment" also takes a StockReservedReported fact, which is not a starting fact
    And "Fulfillment" has no instance for correlation "0192a6b0-0000-7000-8000-000000000011"
    When a StockReservedReported fact is sent to "fulfillment" root "0192a6b0-0000-7000-8000-000000000011"
    Then "Fulfillment" is not called
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000011"
    And nothing is dead-lettered and no alert is raised
    And the sender is answered APPLIED with no events

  @process_manager @pm_start
  @C-0594
  Scenario: A non-starting fact for an existing instance is delivered
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And "Fulfillment" also takes a StockReservedReported fact, which is not a starting fact
    And "Fulfillment" has an instance for correlation "0192a6b0-0000-7000-8000-000000000012" with process state "awaiting stock"
    When a StockReservedReported fact is sent to "fulfillment" root "0192a6b0-0000-7000-8000-000000000012"
    Then "Fulfillment"'s coordinator delivers the fact to "Fulfillment" with its process state "awaiting stock"

  # ===========================================================================
  # Facts only
  # ===========================================================================

  @process_manager @pm_input
  @C-0595
  Scenario: A command addressed to a process manager is refused
    Given a process manager "Fulfillment" owning domain "fulfillment"
    When a client sends a CancelFulfillment Command to "fulfillment" root "0192a6b0-0000-7000-8000-000000000013"
    Then the client is answered INVALID_ARGUMENT
    And "Fulfillment" is not called
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000013"

  @process_manager @pm_input
  @C-0596
  Scenario: A fact is recorded with its id as the cause of the process events
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    When an OrderPlacedReported fact with external_id "order-1-placed" and no correlation_id is sent to "fulfillment" root "0192a6b0-0000-7000-8000-000000000014"
    Then each process event records as its causation the command_id derived from "order-1-placed"
    And each process event records the fact's origin
    And each process event records correlation_id "0192a6b0-0000-7000-8000-000000000014"
    And the sender is answered APPLIED

  @process_manager @pm_dedup
  @C-0597
  Scenario: A redelivered fact is answered from its stored events, before the handler runs
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And an OrderPlacedReported fact with external_id "order-1-placed" has been recorded by "Fulfillment" for correlation "0192a6b0-0000-7000-8000-000000000015"
    When the same fact is sent again
    Then "Fulfillment" is not called
    And the sender is answered DUPLICATE with the stored process events

  @process_manager @pm_input
  @C-0598
  Scenario Outline: A malformed fact addressed to a process manager is refused before the handler runs
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    When a client sends an OrderPlacedReported fact to "fulfillment" root "0192a6b0-0000-7000-8000-000000000016" with <malformation>
    Then the client is answered INVALID_ARGUMENT
    And "Fulfillment" is not called
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000016"

    Examples:
      | malformation                                                       |
      | Handling.expected_sequence 3                                       |
      | Handling.conflict_resolution STRICT                                |
      | correlation_id "0192a6b0-0000-7000-8000-000000000099"              |
      | no fact_origin                                                     |

  @process_manager @pm_failure
  @C-0599
  Scenario: A failing handler dead-letters the fact and raises an alert
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And "Fulfillment"'s OrderPlacedReported handler fails with INTERNAL
    When a client sends an OrderPlacedReported fact to "fulfillment" root "0192a6b0-0000-7000-8000-000000000017"
    Then the fact is dead-lettered and an alert is raised
    And the client is answered OK with delivery PARKED and no events
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000017"

  # ===========================================================================
  # Sagas in and out
  # ===========================================================================

  @process_manager @pm_saga_in
  @C-0600
  Scenario: Another domain's event reaches a process manager only through a saga
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And no saga translates from "order" to "fulfillment"
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000018" is recorded for order "order-1"
    Then "Fulfillment" is not called
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000018"

  @process_manager @pm_saga_in
  @C-0601
  Scenario: A saga's fact reaches the instance its trigger's correlation names
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And a saga "OrderToFulfillment" translating from "order" to "fulfillment" that builds an OrderPlacedReported fact from OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000019" is recorded for order "order-1"
    Then "Fulfillment" records the fact on stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000019"
    And the process events record the fact's reaction origin, which names the OrderPlaced event

  @process_manager @pm_dedup
  @C-0602
  Scenario: A saga re-run sends the same fact id, which the process manager answers DUPLICATE
    Given a process manager "Fulfillment" owning domain "fulfillment" whose OrderPlacedReported fact is a starting fact
    And a saga "OrderToFulfillment" translating from "order" to "fulfillment" that builds an OrderPlacedReported fact from OrderPlaced
    And "Fulfillment" has recorded the saga's fact for the OrderPlaced event at sequence 0 of order "order-1"
    When the saga is run again over that OrderPlaced event
    Then the saga's fact carries the same command_id as before
    And "Fulfillment" is not called
    And nothing is appended to "Fulfillment"'s stream

  @process_manager @pm_output
  @C-0603
  Scenario: A process manager's decision reaches another domain through a saga
    Given a process manager "Fulfillment" owning domain "fulfillment" that records a ShipmentRequested event on an OrderPlacedReported fact
    And a saga "FulfillmentToShipping" translating from "fulfillment" to "shipping" that builds a CreateShipment command from ShipmentRequested
    When an OrderPlacedReported fact with correlation "0192a6b0-0000-7000-8000-00000000001a" is sent to "fulfillment" root "0192a6b0-0000-7000-8000-00000000001a"
    Then "Fulfillment" sends no command
    And "FulfillmentToShipping" delivers CreateShipment to "shipping" with correlation "0192a6b0-0000-7000-8000-00000000001a"
