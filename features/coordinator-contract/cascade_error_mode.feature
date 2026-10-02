Feature: Cascade error mode - failures of synchronous downstream reactions
  CommandRequest.cascade_error_mode decides what a CASCADE request does when
  a saga or process manager reacting to the command's events fails (handler
  error, or a rejection of a command it emitted). It applies only when
  sync_mode is CASCADE; every other sync mode runs reactions asynchronously
  and ignores it.

  CASCADE gives no ordering guarantee among the reactions to one event,
  in-process or in-cluster: they may run in any order or concurrently. These
  scenarios assert only outcomes that hold for every order.

  - FAIL_FAST (also what an unset mode means): fail the request with the
    failure's reason once a reaction fails. Reactions that have not started
    may be skipped; reactions that ran keep their effects.
  - CONTINUE: run every reaction; the request succeeds and its response
    lists each reaction that failed.
  - COMPENSATE: fail the request once a reaction fails, and record one
    Compensate notification per reaction command that executed successfully
    in this request, addressed to that command's target aggregate, before
    the response is returned. The notifications are delivered through the
    compensation outbox (see compensation_delivery.feature): each target's
    compensation handler emits compensating events, and nothing else is
    written to its stream.
  - DEAD_LETTER: dead-letter the failed reaction and run every other
    reaction; the request succeeds.

  In every mode, a rejected reaction command's RejectionNotification is
  delivered to its source aggregate: a rejection always reaches its source.

  The originating command's own events are persisted before any reaction
  runs. Events are immutable facts: no mode removes or hides them, or the
  events of reactions that succeeded.

  Background:
    Given an "order" aggregate that accepts CreateOrder
    And three sagas reacting to OrderCreated:
      | saga           | emits          | target    |
      | ReserveSaga    | ReserveStock   | inventory |
      | ChargeSaga     | CapturePayment | payment   |
      | NotifySaga     | SendReceipt    | shipping  |
    And the payment aggregate rejects CapturePayment with code "CARD_DECLINED" and message "card declined"
    And the inventory aggregate undoes ReserveStock and the shipping aggregate undoes SendReceipt

  @C-0436
  Scenario: FAIL_FAST fails the request with the failing reaction's reason
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode FAIL_FAST
    Then the request fails with reason "card declined"
    And every reaction command that its target executed successfully has its events persisted
    And no Compensate notification is recorded
    And the OrderCreated event remains persisted

  @C-0437
  Scenario: An unset cascade_error_mode behaves as FAIL_FAST
    When a CreateOrder command is handled with sync_mode CASCADE and no cascade_error_mode set
    Then the request fails with reason "card declined"
    And every reaction command that its target executed successfully has its events persisted
    And no Compensate notification is recorded

  @C-0438
  Scenario: CONTINUE runs every reaction and succeeds
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode CONTINUE
    Then the request succeeds
    And ReserveStock has been handled by "inventory"
    And SendReceipt has been handled by "shipping"
    And the response reports exactly one failed reaction
    And the failed reaction is ChargeSaga's CapturePayment to "payment" with reason "card declined"
    And no dead letter is published

  @C-0439
  Scenario: COMPENSATE notifies every successfully executed reaction's target and fails the request
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode COMPENSATE
    Then the request fails with reason "card declined"
    And every reaction command that its target executed successfully has exactly one Compensate notification recorded in the compensation outbox before the response is returned
    And each Compensate notification is addressed to that command's target aggregate, carries the command's type and the sequences of the events the command produced, and its page header carries the command's provenance
    And each Compensate notification is delivered to its target's HandleCompensation and handled by the target's undo handler for that command type
    And each target's stream gains only its compensation handler's events
    And the compensated events remain visible
    And no Compensate notification is recorded for a reaction command that its target did not execute successfully
    And no Compensate notification is sent to the "payment" aggregate
    And a RejectionNotification for the rejected CapturePayment command with code "CARD_DECLINED" and rejection_reason "card declined" is delivered to the "order" aggregate
    And the OrderCreated event remains persisted

  @C-0480
  Scenario: COMPENSATE dead-letters a Compensate its target cannot undo
    Given the shipping aggregate declares no undo for SendReceipt
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode COMPENSATE
    Then the request fails with reason "card declined"
    And every reaction command that its target executed successfully has exactly one Compensate notification recorded, whether or not its target can undo it
    And every Compensate notification for a SendReceipt command that shipping executed successfully is dead-lettered to "angzarr.dlq.shipping" with compensation_delivery_failed details
    And no Compensate notification is dropped

  @C-0441
  Scenario: DEAD_LETTER dead-letters the failure and runs every other reaction
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode DEAD_LETTER
    Then the request succeeds
    And ReserveStock has been handled by "inventory"
    And SendReceipt has been handled by "shipping"
    And a dead letter is published to "angzarr.dlq.payment" carrying the rejected CapturePayment command
    And the dead letter's rejection_reason is "card declined"
    And the dead letter's source_component is "ChargeSaga" with source_component_type "saga"
    And the response reports no failed reactions

  @C-0442
  Scenario Outline: cascade_error_mode is ignored outside CASCADE
    When a CreateOrder command is handled with sync_mode <sync_mode> and cascade_error_mode FAIL_FAST
    Then the request succeeds
    And the OrderCreated event is persisted

    Examples:
      | sync_mode |
      | ASYNC     |
      | DECISION  |
      | SIMPLE    |
      | ISOLATED  |

  @C-0471
  Scenario Outline: A rejected reaction command's notification reaches its source under every cascade_error_mode
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode <mode>
    Then a RejectionNotification for the rejected CapturePayment command with code "CARD_DECLINED" and rejection_reason "card declined" is recorded in the compensation outbox
    And the RejectionNotification is delivered to the "order" aggregate's HandleCompensation

    Examples:
      | mode        |
      | FAIL_FAST   |
      | CONTINUE    |
      | COMPENSATE  |
      | DEAD_LETTER |
