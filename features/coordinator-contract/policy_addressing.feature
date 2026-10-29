Feature: Who a policy's command addresses, and the correlation it carries
  A policy sends commands to foreign aggregates directly, and to process
  managers (decision 14.36). Every command or fact a policy sends, to any
  target, carries its trigger's correlation_id unchanged: correlation
  traces the causal chain. For an aggregate the policy names the root. For
  a process manager naming the root is optional: by default the command
  addresses the instance whose root is the trigger's correlation; a policy
  that implements the command's root callback (root_<Command>, opt-in by
  writing it) names another instance's root, and the command still carries
  the trigger's correlation. A policy naming no root leaves it unset, and
  the coordinator (or angzarr-embedded's kernel) fills in the default. The correlation ids below are UUIDs, as in
  every scenario (decision 14.18).

  Background:
    Given an "order" aggregate "order-1" on the main timeline
    And an "inventory" aggregate "inv-7" on the main timeline
    And a process manager "Fulfillment" owning domain "fulfillment" whose StartFulfillment command is a starting input

  @policy_addressing
  @C-0656
  Scenario: A policy's command to an aggregate lands on the root it names, with the trigger's correlation
    Given a policy "OrderToInventory" translating from "order" to "inventory" that sends ReserveStock to "inventory" "inv-7" on OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000040" is recorded for order "order-1"
    Then "inventory" "inv-7" handles ReserveStock
    And the ReserveStock command carries correlation_id "0192a6b0-0000-7000-8000-000000000040"
    And the events it records carry correlation_id "0192a6b0-0000-7000-8000-000000000040"

  @policy_addressing
  @C-0657
  Scenario: A policy's command to a process manager, naming no root, lands on the instance its trigger's correlation names
    Given a policy "OrderToFulfillment" translating from "order" to "fulfillment" that builds StartFulfillment from OrderPlaced
    And "OrderToFulfillment" implements no root_StartFulfillment callback
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000041" is recorded for order "order-1"
    Then the policy's StartFulfillment command leaves its cover's root unset on the wire
    And the coordinator fills in root "0192a6b0-0000-7000-8000-000000000041", the trigger's correlation, before delivery
    And nothing is dead-lettered and no alert is raised
    And "Fulfillment" handles StartFulfillment on stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000041"
    And the StartFulfillment command carries correlation_id "0192a6b0-0000-7000-8000-000000000041"

  @policy_addressing
  @C-0658
  Scenario: A policy's command to a process manager, naming a root, lands there and keeps its trigger's correlation
    Given a policy "OrderToFulfillment" translating from "order" to "fulfillment" that builds StartFulfillment from OrderPlaced
    And "OrderToFulfillment" implements root_StartFulfillment, naming root "0192a6b0-0000-7000-8000-0000000000aa" for every OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000042" is recorded for order "order-1"
    Then "Fulfillment" handles StartFulfillment on stream "fulfillment" root "0192a6b0-0000-7000-8000-0000000000aa"
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000042"
    And the StartFulfillment command carries correlation_id "0192a6b0-0000-7000-8000-000000000042"
    And the events "Fulfillment" records carry correlation_id "0192a6b0-0000-7000-8000-000000000042"
    And nothing is dead-lettered and no alert is raised

  @policy_addressing
  @C-0659
  Scenario: One instance named by a root takes the inputs of several correlations, each keeping its own
    Given a policy "OrderToFulfillment" translating from "order" to "fulfillment" that builds StartFulfillment from OrderPlaced
    And "OrderToFulfillment" implements root_StartFulfillment, naming root "0192a6b0-0000-7000-8000-0000000000aa" for every OrderPlaced
    And "Fulfillment" also takes a RecordStockReserved command, which is not a starting input
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000043" is recorded for order "order-1"
    And a client sends a RecordStockReserved command to "fulfillment" root "0192a6b0-0000-7000-8000-0000000000aa" with correlation_id "0192a6b0-0000-7000-8000-000000000044"
    Then stream "fulfillment" root "0192a6b0-0000-7000-8000-0000000000aa" holds the events of both inputs
    And the StartFulfillment events carry correlation_id "0192a6b0-0000-7000-8000-000000000043"
    And the RecordStockReserved events carry correlation_id "0192a6b0-0000-7000-8000-000000000044"

  @policy_addressing
  @C-0660
  Scenario: One event fans out to an aggregate and a process manager, both commands keeping the trigger's correlation
    Given a policy "OrderToInventory" translating from "order" to "inventory" that sends ReserveStock to "inventory" "inv-7" on OrderPlaced
    And a policy "OrderToFulfillment" translating from "order" to "fulfillment" that builds StartFulfillment from OrderPlaced
    And "OrderToFulfillment" implements no root_StartFulfillment callback
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000045" is recorded for order "order-1"
    Then "inventory" "inv-7" handles ReserveStock with correlation_id "0192a6b0-0000-7000-8000-000000000045"
    And "Fulfillment" handles StartFulfillment on stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000045" with correlation_id "0192a6b0-0000-7000-8000-000000000045"
    And each command's causation_id is the OrderPlaced event of "order" "order-1"

  @policy_addressing
  @C-0665
  Scenario: A policy's command to an aggregate naming no root is a policy bug
    Given a policy "OrderToInventory" translating from "order" to "inventory" that sends ReserveStock with no root on OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000046" is recorded for order "order-1"
    Then the ReserveStock command is not delivered
    And it is dead-lettered and an alert is raised
    And no root is filled in for it
