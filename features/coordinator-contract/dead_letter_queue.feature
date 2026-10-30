Feature: Dead letter queue routing
  Messages the framework cannot process and must not drop are published as
  AngzarrDeadLetter to the per-domain topic "angzarr.dlq.{domain}", where
  domain is the domain of the dead letter's cover. A dead letter carries
  either the rejected command (rejected_command) or the events that failed
  (rejected_events), a reason (a Diagnostic: a code and its args, never
  rendered text; decision 14.37), exactly one rejection_details variant, chosen by
  its reason (the mapping on AngzarrDeadLetter.rejection_details in types.proto;
  decision 14.48), occurred_at, and the producing component's
  name and type ("aggregate" | "policy" | "projector" | "process_manager").
  The cover's correlation_id is the failed message's correlation_id.

  Sources of dead letters:
  - queued commands whose own expected sequence is stale (sequence_mismatch
    details)
  - policy / PM / projector handler failures once retries are exhausted
    (event_processing_failed details)
  - claim-check payloads that cannot be retrieved
    (payload_retrieval_failed details)
  - CASCADE requests with cascade_error_mode DEAD_LETTER
  - compensation handlers answering RevocationResponse with
    send_to_dead_letter_queue
  - compensation notifications whose delivery exhausts its retries
    (compensation_delivery_failed details; see compensation_delivery.feature)

  @C-0443
  Scenario: A queued command with a stale expected sequence is dead-lettered with mismatch details
    Given an "order" aggregate "order-1" at next_sequence 3
    When a ChangeShippingAddress command with conflict resolution STRICT targeting sequence 1 and correlation_id "0192f3a4-5b6c-7d8e-9f01-23456789ab07" is sent asynchronously
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the rejected command
    And the dead letter's command is addressed to domain "order" root "order-1" with correlation_id "0192f3a4-5b6c-7d8e-9f01-23456789ab07"
    And the dead letter's sequence_mismatch details are expected 1, actual 3
    And the dead letter's source_component_type is "aggregate"
    And the dead letter has occurred_at set

  @C-0444
  Scenario: A policy that keeps failing is dead-lettered with the events it could not process
    Given a policy "OrderFulfillment" subscribed to "order" whose handler fails with code INVENTORY_UNAVAILABLE
    And the policy's retry budget is 3 attempts
    When an OrderCreated event for "order-1" is delivered to the policy
    Then the policy handler is attempted 3 times
    And a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the OrderCreated event as rejected_events
    And the dead letter's event_processing_failed details have failure code INVENTORY_UNAVAILABLE and retry_count 3
    And the dead letter's source_component is "OrderFulfillment" with source_component_type "policy"

  @C-0445
  Scenario: A projector that keeps failing is dead-lettered
    Given a projector "OrderSummary" subscribed to "order" whose handler fails with code VIEW_STORE_UNAVAILABLE
    When an OrderCreated event for "order-1" is delivered to the projector and its retries are exhausted
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the OrderCreated event as rejected_events
    And the dead letter's source_component is "OrderSummary" with source_component_type "projector"

  @C-0446
  Scenario: A non-transient handler failure is dead-lettered without retries
    Given a policy "OrderFulfillment" subscribed to "order" whose handler fails permanently with code UNKNOWN_EVENT_VERSION
    When an OrderCreated event for "order-1" is delivered to the policy
    Then the policy handler is attempted once
    And the dead letter's event_processing_failed details have is_transient false and retry_count 0

  @C-0447
  Scenario: An unretrievable claim-check payload is dead-lettered
    Given an OrderCreated event for "order-1" whose payload is a PayloadReference to "s3://payloads/abc.bin"
    And the payload store cannot return "s3://payloads/abc.bin"
    When the event is delivered to the policy "OrderFulfillment"
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter's payload_retrieval_failed details have storage_type S3 and uri "s3://payloads/abc.bin"

  @C-0448
  Scenario: A compensation handler can send the rejected command to the dead letter queue
    Given a policy "OrderFulfillment" whose ReserveStock command for "inventory" is rejected with code OUT_OF_STOCK
    And the order aggregate's compensation handler answers with a RevocationResponse requesting send_to_dead_letter_queue
    When the rejection is delivered to the "order" aggregate
    Then a dead letter is published to "angzarr.dlq.inventory"
    And the dead letter carries the rejected ReserveStock command
    And the dead letter's reason has code OUT_OF_STOCK

  @C-0449
  Scenario: A dead letter is not published when processing succeeds
    Given a policy "OrderFulfillment" subscribed to "order" whose handler succeeds
    When an OrderCreated event for "order-1" is delivered to the policy
    Then no dead letter is published

  @C-0673
  Scenario: A dead letter carries a key and its args, never rendered text
    # Decision 14.37: text is rendered only where it is displayed, from a
    # catalog keyed by the code.
    Given a policy "OrderFulfillment" subscribed to "order" whose handler fails with code INVENTORY_UNAVAILABLE and arg sku "sku-1", and logs "inventory service down" for itself
    And the policy's retry budget is 1 attempt
    When an OrderCreated event for "order-1" is delivered to the policy
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter's reason has code INVENTORY_UNAVAILABLE and arg sku "sku-1"
    And the dead letter's event_processing_failed details have failure code INVENTORY_UNAVAILABLE and arg sku "sku-1"
    And no field of the dead letter carries the text "inventory service down"

  @C-0730
  Scenario Outline: An asynchronous command ahead of the stream carries sequence mismatch details
    # Decision 14.48: the AHEAD key's head arg is the details' actual_sequence.
    Given an "order" aggregate "order-1" at next_sequence 3
    When a ChangeShippingAddress command with conflict resolution <resolution> targeting sequence 7 is sent asynchronously
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the rejected command
    And the dead letter's reason has code COORDINATOR_REASON_EXPECTED_SEQUENCE_AHEAD, arg expected "7" and arg head "3"
    And the dead letter's sequence_mismatch details are expected 7, actual 3
    And the dead letter carries no other rejection_details variant

    Examples:
      | resolution        |
      | STRICT            |
      | AGGREGATE_HANDLES |

  @C-0731
  Scenario: An asynchronous STRICT command behind the stream carries its stale key and sequence mismatch details
    Given an "order" aggregate "order-1" at next_sequence 3
    When a ChangeShippingAddress command with conflict resolution STRICT targeting sequence 1 is sent asynchronously
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the rejected command
    And the dead letter's reason has code COORDINATOR_REASON_EXPECTED_SEQUENCE_STALE, arg expected "1" and arg actual "3"
    And the dead letter's sequence_mismatch details are expected 1, actual 3
    And the dead letter carries no other rejection_details variant

  @C-0732
  Scenario Outline: A command dead-lettered at a retry cap carries event processing failed details
    # Decision 14.48: one variant for the key, whether or not the command
    # carries an expected sequence; retry_count is the attempts arg.
    Given an "order" aggregate "order-1" at next_sequence 3
    And the <cap> is reached after 3 runs
    And an AddItem command <handling> is sent asynchronously
    And the business process answers every run with an ItemAdded event<report>
    And another write to the "order" stream lands after each run's load and before the command is written
    When the coordinator processes the command
    Then a dead letter is published to "angzarr.dlq.order"
    And the dead letter carries the rejected command
    And the dead letter's reason has code COORDINATOR_REASON_RETRY_CAP_EXHAUSTED, arg attempts "3" and arg cap "3"
    And the dead letter's event_processing_failed details have failure code COORDINATOR_REASON_RETRY_CAP_EXHAUSTED, retry_count 3 and is_transient true
    And the dead letter carries no other rejection_details variant

    Examples:
      | cap             | handling                                                        | report                                                                  |
      | race re-run cap | with no expected sequence and no conflict resolution            |                                                                         |
      | retry cap       | with conflict resolution AGGREGATE_HANDLES targeting sequence 1 | , reporting the conflict nonce it was delivered as its resolved nonce   |
