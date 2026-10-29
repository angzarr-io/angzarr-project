Feature: Who a policy's command addresses, and the correlation it carries
  A policy sends commands to foreign aggregates directly, and to process
  managers (decision 14.36, as amended). Every command or fact a policy
  sends, to any target, carries its trigger's correlation_id unchanged:
  correlation traces the causal chain, and a command carrying another is a
  policy bug (POLICY_COMMAND_OTHER_CORRELATION). A policy names its
  command's root for EVERY target, aggregate or process manager alike:
  nothing fills one in, the router never knows the target's kind, and a
  command with no root is a policy bug (POLICY_COMMAND_NO_ROOT). Setting a
  process manager's root to the trigger's correlation is a convention a
  policy may follow by writing it. The correlation ids below are UUIDs, as
  in every scenario (decision 14.18).

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

  # C-0665 (an aggregate command naming no root) is merged into C-0657 and
  # retired: the rule is the same for every target (decision 14.36, as
  # amended).

  @policy_addressing
  @C-0657
  Scenario Outline: A policy's command naming no root is a policy bug, whatever its target
    Given a policy "<policy>" translating from "order" to "<domain>" that sends <command> with no root on OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000041" is recorded for order "order-1"
    Then the <command> command is refused INTERNAL with reason POLICY_COMMAND_NO_ROOT, naming domain "<domain>" and command type <command>
    And it is dead-lettered and an alert is raised
    And no root is filled in for it, and nothing is appended to any "<domain>" stream

    Examples:
      | policy             | domain      | command          |
      | OrderToInventory   | inventory   | ReserveStock     |
      | OrderToFulfillment | fulfillment | StartFulfillment |

  @policy_addressing
  @C-0658
  Scenario: A policy's command to a process manager lands on the root the policy sets, keeping its trigger's correlation
    Given a policy "OrderToFulfillment" translating from "order" to "fulfillment" that sends StartFulfillment to "fulfillment" "0192a6b0-0000-7000-8000-0000000000aa" on OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000042" is recorded for order "order-1"
    Then "Fulfillment" handles StartFulfillment on stream "fulfillment" root "0192a6b0-0000-7000-8000-0000000000aa"
    And nothing is appended to stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000042"
    And the StartFulfillment command carries correlation_id "0192a6b0-0000-7000-8000-000000000042"
    And the events "Fulfillment" records carry correlation_id "0192a6b0-0000-7000-8000-000000000042"
    And nothing is dead-lettered and no alert is raised

  @policy_addressing
  @C-0659
  Scenario: One instance named by its root takes the inputs of several correlations, each keeping its own
    Given a policy "OrderToFulfillment" translating from "order" to "fulfillment" that sends StartFulfillment to "fulfillment" "0192a6b0-0000-7000-8000-0000000000aa" on OrderPlaced
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
    And a policy "OrderToFulfillment" translating from "order" to "fulfillment" that sends StartFulfillment to "fulfillment" root the trigger's correlation on OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000045" is recorded for order "order-1"
    Then "inventory" "inv-7" handles ReserveStock with correlation_id "0192a6b0-0000-7000-8000-000000000045"
    And "Fulfillment" handles StartFulfillment on stream "fulfillment" root "0192a6b0-0000-7000-8000-000000000045" with correlation_id "0192a6b0-0000-7000-8000-000000000045"
    And each command's causation_id is the OrderPlaced event of "order" "order-1"

  @policy_addressing
  @C-0666
  Scenario Outline: A policy's command carrying another correlation is a policy bug, whatever its target
    Given a policy "<policy>" translating from "order" to "<domain>" that sends <command> to "<domain>" "0192a6b0-0000-7000-8000-0000000000bb" with correlation_id "0192a6b0-0000-7000-8000-000000000099" on OrderPlaced
    When an OrderPlaced event with correlation "0192a6b0-0000-7000-8000-000000000047" is recorded for order "order-1"
    Then the <command> command is refused INTERNAL with reason POLICY_COMMAND_OTHER_CORRELATION
    And it is dead-lettered and an alert is raised
    And nothing is appended to stream "<domain>" root "0192a6b0-0000-7000-8000-0000000000bb"

    Examples:
      | policy             | domain      | command          |
      | OrderToInventory   | inventory   | ReserveStock     |
      | OrderToFulfillment | fulfillment | StartFulfillment |
