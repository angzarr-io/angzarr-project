Feature: Compensation delivery - Notifications through the coordinator outbox
  A compensation Notification is a durable obligation of the coordinator
  that raises it:
  - a saga/PM command is rejected: a RejectionNotification addressed to the
    command's angzarr_deferred.source (the aggregate whose event triggered
    the saga);
  - a CASCADE request with cascade_error_mode COMPENSATE fails after a
    reaction command executed: a Compensate notification addressed to that
    command's target (see cascade_error_mode.feature).

  The coordinator records the obligation in its compensation outbox before
  acknowledging the trigger, then delivers it at least once to the target
  domain's HandleCompensation as a delivery-envelope CommandBook: one page
  whose command is the Notification and whose angzarr_deferred header
  carries the provenance tuple (source, source_seq, source_component,
  command_index) of the command being compensated. Failed deliveries are
  retried with backoff and dead-lettered once the coordinator's configured
  outbox retry budget is spent. A Compensate is routed to the target's undo
  handler for its command_type (ComponentOptions.undoes); one with no undo
  handler is answered UNIMPLEMENTED and dead-lettered at once, never
  dropped. The target deduplicates by (kind, source,
  source_seq, source_component, command_index), kind being command,
  rejection-notification or compensate-notification, so a notification is
  never dropped as a duplicate of the command it concerns. A rejection
  reaches its source in every sync mode. The
  Notification is never written to the target's stream; only the events its
  compensation handler emits are.

  Background:
    Given a saga "OrderFulfillment" reacting to OrderCreated on "order" by emitting ReserveStock to "inventory"
    And the order aggregate compensates a rejected ReserveStock by emitting OrderCancelled
    And the inventory aggregate undoes ReserveStock by emitting StockReleased
    And every recorded Compensate notification undoes a ReserveStock command unless a scenario says otherwise

  # ---------------------------------------------------------------------------
  # Recording the obligation
  # ---------------------------------------------------------------------------

  @C-0462
  Scenario: A rejected saga command's notification is recorded before the triggering event is acknowledged
    Given the inventory aggregate rejects ReserveStock with code "OUT_OF_STOCK" and message "out of stock"
    When the OrderCreated event for "order-1" at sequence 0 is delivered to the saga
    Then a RejectionNotification addressed to the "order" aggregate "order-1" is recorded in the compensation outbox
    And the outbox record is written before the OrderCreated delivery is acknowledged
    And the recorded notification carries the rejected ReserveStock command, code "OUT_OF_STOCK" and rejection_reason "out of stock"

  @C-0472
  Scenario Outline: A rejected saga command's notification reaches its source in every sync mode
    Given the inventory aggregate rejects ReserveStock with code "OUT_OF_STOCK" and message "out of stock"
    When a CreateOrder command for "order-1" is handled with sync_mode <sync_mode>
    Then a RejectionNotification for the rejected ReserveStock command with code "OUT_OF_STOCK" and rejection_reason "out of stock" is delivered to the "order" aggregate "order-1"

    Examples:
      | sync_mode |
      | ASYNC     |
      | DECISION  |
      | SIMPLE    |
      | CASCADE   |

  @C-0505
  Scenario: The rejection code and message are carried in separate fields
    Given the inventory aggregate rejects ReserveStock with code "OUT_OF_STOCK" and message "only 2 left of sku-1"
    When the OrderCreated event for "order-1" at sequence 0 is delivered to the saga
    Then the recorded RejectionNotification's code is "OUT_OF_STOCK"
    And its rejection_reason is "only 2 left of sku-1"
    And its rejection_reason does not contain "OUT_OF_STOCK"

  @C-0506
  Scenario: A rejection without ErrorInfo carries an empty code
    Given the inventory aggregate rejects ReserveStock with message "out of stock" and no ErrorInfo
    When the OrderCreated event for "order-1" at sequence 0 is delivered to the saga
    Then the recorded RejectionNotification's code is empty
    And its rejection_reason is "out of stock"

  @C-0463
  Scenario: A notification that cannot be recorded leaves the trigger unacknowledged
    Given the inventory aggregate rejects ReserveStock with code "OUT_OF_STOCK" and message "out of stock"
    And the compensation outbox cannot be written
    When the OrderCreated event for "order-1" at sequence 0 is delivered to the saga
    Then the OrderCreated delivery is not acknowledged
    And no notification is delivered to the "order" aggregate

  # ---------------------------------------------------------------------------
  # Delivery
  # ---------------------------------------------------------------------------

  @C-0464
  Scenario Outline: A recorded notification is delivered to the target's compensation handler
    Given a recorded <payload> notification addressed to the "<domain>" aggregate "<root>" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    When the compensation outbox is processed
    Then HandleCompensation on "<domain>" receives a CommandBook addressed to "<root>"
    And the CommandBook's single page carries the Notification with a <payload> payload
    And the page header is angzarr_deferred with source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And the <domain> compensation handler is invoked once
    And the outbox record is closed

    Examples:
      | payload               | domain    | root    |
      | RejectionNotification | order     | order-1 |
      | Compensate            | inventory | sku-1   |

  @C-0465
  Scenario Outline: A recorded notification is delivered after a coordinator restart
    Given a recorded <payload> notification addressed to the "<domain>" aggregate "<root>" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And the coordinator restarts before delivering it
    When the compensation outbox is processed
    Then the <domain> compensation handler is invoked once
    And the outbox record is closed

    Examples:
      | payload               | domain    | root    |
      | RejectionNotification | order     | order-1 |
      | Compensate            | inventory | sku-1   |

  @C-0466
  Scenario: A failed delivery is retried with backoff until it succeeds
    Given a recorded RejectionNotification notification addressed to the "order" aggregate "order-1" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And HandleCompensation on "order" fails with UNAVAILABLE for the first 2 attempts
    When the compensation outbox is processed
    Then delivery is attempted 3 times
    And each retry waits longer than the retry before it
    And the order compensation handler is invoked once
    And no dead letter is published

  # ---------------------------------------------------------------------------
  # Deduplication at the target
  # ---------------------------------------------------------------------------

  @C-0467
  Scenario Outline: A redelivered notification is applied once
    Given a recorded <payload> notification addressed to the "<domain>" aggregate "<root>" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And the notification has been delivered and the <domain> compensation handler emitted <event>
    When the same notification is delivered again
    Then the <domain> compensation handler is not invoked again
    And exactly one <event> event is persisted to "<domain>" aggregate "<root>"
    And the second delivery returns the events of the first

    Examples:
      | payload               | domain    | root    | event          |
      | RejectionNotification | order     | order-1 | OrderCancelled |
      | Compensate            | inventory | sku-1   | StockReleased  |

  @C-0468
  Scenario: Notifications that differ only in command_index are each applied
    Given a recorded RejectionNotification notification addressed to the "order" aggregate "order-1" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And a recorded RejectionNotification notification addressed to the "order" aggregate "order-1" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 1
    When the compensation outbox is processed
    Then the order compensation handler is invoked twice
    And exactly two OrderCancelled events are persisted to "order" aggregate "order-1"

  @C-0473
  Scenario: A Compensate sharing an applied command's provenance is delivered, and its redelivery is deduplicated
    Given the "inventory" aggregate "sku-1" has applied a deferred ReserveStock command with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And a recorded Compensate notification addressed to the "inventory" aggregate "sku-1" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    When the compensation outbox is processed
    And the same Compensate notification is delivered again
    Then the inventory compensation handler is invoked once
    And exactly one StockReleased event is persisted to "inventory" aggregate "sku-1"
    And the second delivery returns the events of the first

  # ---------------------------------------------------------------------------
  # Undo routing
  # ---------------------------------------------------------------------------

  @C-0478
  Scenario: A Compensate is routed to the undo handler for its command type
    Given the inventory aggregate also undoes AdjustStock by emitting StockAdjustmentReverted
    And a recorded Compensate notification addressed to the "inventory" aggregate "sku-1" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And the Compensate notification's command_type is "inventory.AdjustStock"
    When the compensation outbox is processed
    Then the inventory AdjustStock undo handler is invoked once
    And the inventory ReserveStock undo handler is not invoked
    And exactly one StockAdjustmentReverted event is persisted to "inventory" aggregate "sku-1"

  @C-0479
  Scenario: A Compensate for a command with no undo handler is dead-lettered, not dropped
    Given a recorded Compensate notification addressed to the "inventory" aggregate "sku-1" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And the Compensate notification's command_type is "inventory.CountStock"
    And the inventory aggregate declares no undo for CountStock
    When the compensation outbox is processed
    Then HandleCompensation on "inventory" answers UNIMPLEMENTED
    And delivery is attempted once
    And a dead letter is published to "angzarr.dlq.inventory"
    And the dead letter carries the notification's delivery envelope as rejected_command
    And the dead letter's compensation_delivery_failed details have attempts 1
    And the outbox record is closed
    And no event is persisted to "inventory" aggregate "sku-1"

  # ---------------------------------------------------------------------------
  # Exhaustion
  # ---------------------------------------------------------------------------

  @C-0469
  Scenario Outline: A notification whose delivery keeps failing is dead-lettered
    Given a recorded <payload> notification addressed to the "<domain>" aggregate "<root>" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    And the coordinator's configured outbox retry budget is 3 attempts
    And HandleCompensation on "<domain>" always fails with "<domain> service down"
    When the compensation outbox is processed
    Then delivery is attempted 3 times
    And a dead letter is published to "angzarr.dlq.<domain>"
    And the dead letter carries the notification's delivery envelope as rejected_command
    And the dead letter's compensation_delivery_failed details have attempts 3 and last_error "<domain> service down"
    And the outbox record is closed
    And no event is persisted to "<domain>" aggregate "<root>"

    Examples:
      | payload               | domain    | root    |
      | RejectionNotification | order     | order-1 |
      | Compensate            | inventory | sku-1   |

  # ---------------------------------------------------------------------------
  # The stream holds only business events
  # ---------------------------------------------------------------------------

  @C-0470
  Scenario Outline: The notification is never written to the target's stream
    Given the "<domain>" aggregate "<root>" has 2 events
    And a recorded <payload> notification addressed to the "<domain>" aggregate "<root>" with provenance source "order"/"order-1", source_seq 0, source_component "OrderFulfillment" and command_index 0
    When the compensation outbox is processed
    Then the "<domain>" aggregate "<root>" has 3 events
    And the event at sequence 2 is the <event> event emitted by its compensation handler
    And no event in the stream is a Notification, RejectionNotification or Compensate

    Examples:
      | payload               | domain    | root    | event          |
      | RejectionNotification | order     | order-1 | OrderCancelled |
      | Compensate            | inventory | sku-1   | StockReleased  |
