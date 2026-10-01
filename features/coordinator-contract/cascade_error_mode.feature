Feature: Cascade error mode - failures of synchronous downstream reactions
  CommandRequest.cascade_error_mode decides what a CASCADE request does when
  a saga or process manager reacting to the command's events fails (handler
  error, or a rejection of a command it emitted). It applies only when
  sync_mode is CASCADE; every other sync mode runs reactions asynchronously
  and ignores it.

  - FAIL_FAST (zero value): stop at the first failure and fail the request.
  - CONTINUE: run every reaction; the request succeeds and its response
    lists each reaction that failed.
  - COMPENSATE: at the first failure, compensate the downstream commands
    already executed in this cascade, then fail the request.
  - DEAD_LETTER: dead-letter the failed reaction and continue with the rest;
    the request succeeds.

  The originating command's own events are persisted before any reaction
  runs. Without a cascade_id they are committed and stay visible whatever
  the mode; with a cascade_id (two-phase commit) they are pending, and a
  COMPENSATE failure revokes them with the rest of the cascade.

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
    And SendReceipt has not been handled by "shipping"
    And the OrderCreated event remains persisted

  @C-0440
  Scenario: COMPENSATE under two-phase commit revokes the cascade's pending events
    When a CreateOrder command is handled with sync_mode CASCADE, cascade_error_mode COMPENSATE and cascade_id "cascade-E"
    Then the request fails with reason "card declined"
    And a Revocation with cascade_id "cascade-E" hides the pending StockReserved event in "inventory"
    And a Revocation with cascade_id "cascade-E" hides the pending OrderCreated event in "order"

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
