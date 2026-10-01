Feature: Cascade error mode - failures of synchronous downstream reactions
  CommandRequest.cascade_error_mode decides what a CASCADE request does when
  a saga or process manager reacting to the command's events fails (handler
  error, or a rejection of a command it emitted). It applies only when
  sync_mode is CASCADE; every other sync mode runs reactions asynchronously
  and ignores it.

  - FAIL_FAST (also what an unset mode means): stop at the first failure and fail the request.
  - CONTINUE: run every reaction; the request succeeds and its response
    lists each reaction that failed.
  - COMPENSATE: at the first failure, append a Compensate marker to each
    aggregate whose downstream command already executed in this request
    (its compensation handler emits compensating events), then fail the
    request.
  - DEAD_LETTER: dead-letter the failed reaction and continue with the rest;
    the request succeeds.

  The originating command's own events are persisted before any reaction
  runs. Events are immutable facts: no mode removes or hides them, or the
  events of reactions that already succeeded.

  Background:
    Given an "order" aggregate that accepts CreateOrder
    And three sagas reacting to OrderCreated, run in registration order:
      | saga           | emits          | target    |
      | ReserveSaga    | ReserveStock   | inventory |
      | ChargeSaga     | CapturePayment | payment   |
      | NotifySaga     | SendReceipt    | shipping  |
    And the payment aggregate rejects CapturePayment with reason "card declined"

  @C-0436
  Scenario: FAIL_FAST stops at the first failure and fails the request
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode FAIL_FAST
    Then the request fails with reason "card declined"
    And ReserveStock has been handled by "inventory"
    And SendReceipt has not been handled by "shipping"
    And the OrderCreated event remains persisted

  @C-0437
  Scenario: An unset cascade_error_mode behaves as FAIL_FAST
    When a CreateOrder command is handled with sync_mode CASCADE and no cascade_error_mode set
    Then the request fails with reason "card declined"
    And SendReceipt has not been handled by "shipping"

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
  Scenario: COMPENSATE compensates executed commands and fails the request
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode COMPENSATE
    Then the request fails with reason "card declined"
    And a Compensate marker is written to the "inventory" aggregate for the StockReserved event
    And the inventory compensation handler is invoked for the StockReserved event
    And the StockReserved event remains visible
    And no Compensate marker is written to the "payment" or "shipping" aggregates
    And SendReceipt has not been handled by "shipping"
    And the OrderCreated event remains persisted

  @C-0441
  Scenario: DEAD_LETTER dead-letters the failure and continues
    When a CreateOrder command is handled with sync_mode CASCADE and cascade_error_mode DEAD_LETTER
    Then the request succeeds
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
