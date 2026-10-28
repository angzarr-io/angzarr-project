Feature: Saga refusals - a refused command becomes one fact for the saga's own source domain
  A saga's target, an aggregate or a process manager alike, refuses a
  saga's command the way it refuses any command, and records nothing. The
  saga then delivers one unrefusable refusal fact to its own source domain
  (decision 2.2, as amended by 14.31). By default its generated code passes
  the standard CommandRefused { command, response, trigger } through, and
  the source's generated on_refused_<Command> handles it; a command may opt
  in to translation, where the saga's callback turns Refusal { event,
  command, response } into a domestic fact. The mode is chosen when the code
  is generated. The refusal fact's id is the refused command's id. Both
  calls go through the outbox.

  Background:
    Given a "player" aggregate that refuses HoldFunds with FAILED_PRECONDITION reason INSUFFICIENT_AVAILABLE_FUNDS when funds are short
    And a process manager "BuyIn" owning domain "buy-in"
    And a saga "BuyInToPlayer" translating from "buy-in" to "player" that builds HoldFunds from BuyInStarted

  @saga_refusal
  @C-0613
  Scenario: A refused command is passed through as CommandRefused and handled by the source's generated handler
    Given "BuyInToPlayer" sends HoldFunds in pass-through mode
    And "BuyIn" declares HoldFunds among its refusals
    And player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1" under correlation "0192a6b0-0000-7000-8000-000000000020"
    Then player "p-1" refuses HoldFunds and records nothing
    And a CommandRefused fact carrying the HoldFunds sent, the refusal response and the BuyInStarted event's EventRef is delivered to "buy-in" root "0192a6b0-0000-7000-8000-000000000020"
    And "BuyIn"'s on_refused_HoldFunds handler records its own events for it

  @saga_refusal
  @C-0614
  Scenario: A refused command is translated into a domestic fact by the saga's callback
    Given "BuyInToPlayer" sends HoldFunds in translate mode, with refusal fact "buy-in" HoldFundsDeclined
    And player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1" under correlation "0192a6b0-0000-7000-8000-000000000021"
    Then "BuyInToPlayer"'s callback is called with one Refusal holding the BuyInStarted event, the HoldFunds sent and the refusal response
    And a HoldFundsDeclined fact is delivered to "buy-in" root "0192a6b0-0000-7000-8000-000000000021"
    And "BuyIn" handles it as an ordinary fact, with no reference to the player's protos

  @saga_refusal
  @C-0615
  Scenario Outline: The refusal fact's id is the refused command's id, in either mode
    Given "BuyInToPlayer" sends HoldFunds in <mode> mode
    And player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1" under correlation "0192a6b0-0000-7000-8000-000000000022"
    Then the refusal fact's command_id is the refused HoldFunds' command_id
    And its fact_origin external_id is that command_id's canonical text
    And its causation_id names the BuyInStarted event
    And its correlation_id is "0192a6b0-0000-7000-8000-000000000022"
    And player "p-1"'s stream holds no event with that command_id

    Examples:
      | mode         |
      | pass-through |
      | translate    |

  @saga_refusal
  @C-0616
  Scenario: The refusal fact replaces the command's outbox entry in one transaction
    Given "BuyInToPlayer" sends HoldFunds in pass-through mode
    And "BuyIn" declares HoldFunds among its refusals
    And player "p-1" has too little available to hold 500
    And the saga's coordinator crashes after OnRefused answers and before its transaction commits
    When the coordinator restarts
    Then HoldFunds is delivered again and refused again
    And "BuyIn" records the refusal once

  @saga_refusal
  @C-0617
  Scenario Outline: Only a business rejection yields a refusal fact
    Given player "p-1" answers HoldFunds with <status>
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then "BuyInToPlayer"'s OnRefused is not called
    And <outcome>

    Examples:
      | status            | outcome                                                     |
      | UNAVAILABLE       | HoldFunds is retried                                        |
      | INVALID_ARGUMENT  | HoldFunds is dead-lettered and an alert is raised           |
      | INTERNAL          | HoldFunds is dead-lettered and an alert is raised           |

  @saga_refusal
  @C-0618
  Scenario: A pass-through refusal with no handler at the source is dead-lettered for a human
    Given "BuyInToPlayer" sends HoldFunds in pass-through mode
    And "BuyIn" does not declare HoldFunds among its refusals
    And player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then the CommandRefused fact is refused NO_FACT_HANDLER, dead-lettered and alerted
    And nothing is recorded in "buy-in" or "player"

  @saga_refusal
  @C-0619
  Scenario: A failing translating callback is dead-lettered and alerted
    Given "BuyInToPlayer" sends HoldFunds in translate mode, with refusal fact "buy-in" HoldFundsDeclined
    And "BuyInToPlayer"'s callback fails with INTERNAL
    And player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then the refusal is dead-lettered and an alert is raised
    And nothing is recorded in "buy-in"

  @saga_refusal
  @C-0621
  Scenario: A refusal fact for any domain but the saga's source is refused
    Given "BuyInToPlayer" sends HoldFunds in translate mode, with refusal fact "buy-in" HoldFundsDeclined
    And "BuyInToPlayer"'s callback returns a fact addressed to domain "table"
    And player "p-1" has too little available to hold 500
    When "BuyIn" records BuyInStarted for 500 from player "p-1"
    Then the fact is refused as malformed, dead-lettered and alerted
    And nothing is recorded in "table"

  @saga_refusal
  @C-0622
  Scenario: The mechanism is the same when the saga's target is a process manager
    Given a process manager "Fulfillment" owning domain "fulfillment" that refuses RecordStockReserved once completed
    And a saga "InventoryToFulfillment" translating from "inventory" to "fulfillment" that sends RecordStockReserved in pass-through mode
    And the "inventory" aggregate declares RecordStockReserved among its refusals
    When "Fulfillment" refuses the RecordStockReserved built from StockReserved of item "sku-1"
    Then "Fulfillment" records nothing
    And a CommandRefused fact is delivered to "inventory" item "sku-1"
