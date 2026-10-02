Feature: Dead letter queue routing
  Messages the framework cannot process and must not drop are published as
  AngzarrDeadLetter to the per-domain topic "angzarr.dlq.{domain}", where
  domain is the domain of the dead letter's cover. A dead letter carries
  either the rejected command (rejected_command) or the events that failed
  (rejected_events), a human-readable rejection_reason, exactly one
  rejection_details variant, occurred_at, and the producing component's
  name and type ("aggregate" | "saga" | "projector" | "process_manager").
  The cover's correlation_id is the failed message's correlation_id.

  Sources of dead letters:
  - MERGE_MANUAL sequence conflicts (sequence_mismatch details)
  - saga / PM / projector handler failures once retries are exhausted
    (event_processing_failed details)
  - claim-check payloads that cannot be retrieved
    (payload_retrieval_failed details)
  - CASCADE requests with cascade_error_mode DEAD_LETTER
  - compensation handlers answering RevocationResponse with
    send_to_dead_letter_queue
  - compensation notifications whose delivery exhausts its retries
    (compensation_delivery_failed details; see compensation_delivery.feature)

  @C-0443
  Scenario: A MANUAL sequence conflict is dead-lettered with mismatch details
    Given an "order" aggregate "order-1" at next_sequence 3
    When a ChangeShippingAddress command with merge_strategy MANUAL targeting sequence 1 and correlation_id "corr-7" is handled
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the rejected command
    And the dead letter's cover is domain "order" root "order-1" with correlation_id "corr-7"
    And the dead letter's sequence_mismatch details are expected 1, actual 3, merge_strategy MERGE_MANUAL
    And the dead letter's source_component_type is "aggregate"
    And the dead letter has occurred_at set

  @C-0444
  Scenario: A saga that keeps failing is dead-lettered with the events it could not process
    Given a saga "OrderFulfillment" subscribed to "order" whose handler fails with "inventory service down"
    And the saga's retry budget is 3 attempts
    When an OrderCreated event for "order-1" is delivered to the saga
    Then the saga handler is attempted 3 times
    And a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the OrderCreated event as rejected_events
    And the dead letter's event_processing_failed details have error "inventory service down" and retry_count 3
    And the dead letter's source_component is "OrderFulfillment" with source_component_type "saga"

  @C-0445
  Scenario: A projector that keeps failing is dead-lettered
    Given a projector "OrderSummary" subscribed to "order" whose handler fails with "view store unavailable"
    When an OrderCreated event for "order-1" is delivered to the projector and its retries are exhausted
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the OrderCreated event as rejected_events
    And the dead letter's source_component is "OrderSummary" with source_component_type "projector"

  @C-0446
  Scenario: A non-transient handler failure is dead-lettered without retries
    Given a saga "OrderFulfillment" subscribed to "order" whose handler fails permanently with "unknown event version"
    When an OrderCreated event for "order-1" is delivered to the saga
    Then the saga handler is attempted once
    And the dead letter's event_processing_failed details have is_transient false and retry_count 0

  @C-0447
  Scenario: An unretrievable claim-check payload is dead-lettered
    Given an OrderCreated event for "order-1" whose payload is a PayloadReference to "s3://payloads/abc.bin"
    And the payload store cannot return "s3://payloads/abc.bin"
    When the event is delivered to the saga "OrderFulfillment"
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter's payload_retrieval_failed details have storage_type S3 and uri "s3://payloads/abc.bin"

  @C-0448
  Scenario: A compensation handler can send the rejected command to the dead letter queue
    Given a saga "OrderFulfillment" whose ReserveStock command for "inventory" is rejected with reason "out of stock"
    And the order aggregate's compensation handler answers with a RevocationResponse requesting send_to_dead_letter_queue
    When the rejection is delivered to the "order" aggregate
    Then a dead letter is published to "angzarr.dlq.inventory"
    And the dead letter carries the rejected ReserveStock command
    And the dead letter's rejection_reason is "out of stock"

  @C-0449
  Scenario: A dead letter is not published when processing succeeds
    Given a saga "OrderFulfillment" subscribed to "order" whose handler succeeds
    When an OrderCreated event for "order-1" is delivered to the saga
    Then no dead letter is published
