Feature: Saga refusals - a refused command becomes a fact for the saga's own source domain
  A saga's target, an aggregate or a process manager alike, refuses a
  saga's command the way it refuses any command, and records nothing. The
  saga's coordinator then calls the saga's on-refused callback with one
  struct, Refusal { event, command, response }: the triggering event, the
  command as sent and the refusal response. The callback crafts a rejection
  fact for the saga's own source domain, which records it and decides what
  it means (decision 2.2, as amended by 14.31). Both calls go through the
  outbox, retried and deduplicated by command id and fact id.

  Background:
    Given a "player" aggregate that refuses HoldFunds with FAILED_PRECONDITION reason INSUFFICIENT_AVAILABLE_FUNDS when funds are short
    And a process manager "BuyIn" owning domain "buy-in"
    And a saga "BuyInToPlayer" translating from "buy-in" to "player" that builds HoldFunds from BuyInStarted
    And "BuyInToPlayer" declares an on-refused callback for HoldFunds returning the "buy-in" fact HoldFundsRefused

  @saga_refusal
  @C-0613
  Scenario: A refused command is turned into a fact for the saga's own source, through its callback
    Given player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1" under correlation "0192a6b0-0000-7000-8000-000000000020"
    Then player "p-1" refuses HoldFunds and records nothing
    And "BuyInToPlayer"'s callback is called with the BuyInStarted event, the HoldFunds sent and the refusal response with reason INSUFFICIENT_AVAILABLE_FUNDS
    And a HoldFundsRefused fact is delivered to "buy-in" root "0192a6b0-0000-7000-8000-000000000020"
    And the fact's causation_id names the BuyInStarted event
    And the fact's correlation_id is "0192a6b0-0000-7000-8000-000000000020"
    And the fact's fact_origin external_id is "angzarr-refusal:" followed by the HoldFunds command's reaction name
    And "BuyIn" records the fact as its own events

  @saga_refusal
  @C-0614
  Scenario: The rejection fact replaces the command's outbox entry in one transaction
    Given player "p-1" has too little available to hold 500
    And the saga's coordinator crashes after the callback returns and before its transaction commits
    When the coordinator restarts
    Then HoldFunds is delivered again and refused again
    And the callback runs again and returns the same fact id
    And "BuyIn" records the HoldFundsRefused fact once

  @saga_refusal
  @C-0615
  Scenario Outline: Only a business rejection reaches the callback
    Given player "p-1" answers HoldFunds with <status>
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then "BuyInToPlayer"'s callback is not called
    And <outcome>

    Examples:
      | status            | outcome                                                     |
      | UNAVAILABLE       | HoldFunds is retried                                        |
      | INVALID_ARGUMENT  | HoldFunds is dead-lettered and an alert is raised           |
      | INTERNAL          | HoldFunds is dead-lettered and an alert is raised           |

  @saga_refusal @proposed
  @C-0616
  Scenario: A refused command with no callback is dead-lettered for a human (PROPOSED)
    Given a saga "BuyInToTable" translating from "buy-in" to "table" with no on-refused callback for ConfirmSeat
    And the table refuses ConfirmSeat with FAILED_PRECONDITION
    When "BuyIn" records BuyInFundsHeld
    Then ConfirmSeat is dead-lettered with its refusal and an alert is raised
    And nothing is recorded in "buy-in" or "table"

  @saga_refusal @proposed
  @C-0617
  Scenario: A failing callback is dead-lettered and alerted (PROPOSED)
    Given player "p-1" has too little available to hold 500
    And "BuyInToPlayer"'s callback fails with INTERNAL
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then the refusal is dead-lettered and an alert is raised
    And nothing is recorded in "buy-in"

  @saga_refusal
  @C-0618
  Scenario: A rejection fact for any domain but the saga's source is refused
    Given player "p-1" has too little available to hold 500
    And "BuyInToPlayer"'s callback returns a fact addressed to domain "table"
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then the fact is refused as malformed, dead-lettered and alerted
    And nothing is recorded in "table"

  @saga_refusal
  @C-0619
  Scenario: The refusal mechanism is the same when the saga's target is a process manager
    Given a process manager "Fulfillment" owning domain "fulfillment" that refuses RecordStockReserved once completed
    And a saga "InventoryToFulfillment" translating from "inventory" to "fulfillment" that builds RecordStockReserved from StockReserved
    And "InventoryToFulfillment" declares an on-refused callback for RecordStockReserved returning the "inventory" fact ReservationUnwanted
    When "Fulfillment" refuses the RecordStockReserved built from StockReserved of item "sku-1"
    Then "Fulfillment" records nothing
    And a ReservationUnwanted fact is delivered to "inventory" item "sku-1"
