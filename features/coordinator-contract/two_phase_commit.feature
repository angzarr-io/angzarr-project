Feature: Two-phase commit - pending events, confirmation and revocation
  A CommandRequest with cascade_id set runs under two-phase commit. Events
  it produces are persisted with EventPage.no_commit = true and the
  request's cascade_id. They are durable but pending: business logic does
  not see them until a Confirmation lists their sequences, and a
  Revocation hides them for good.

  Framework events (Confirmation, Revocation, Compensate) are persisted in
  the same stream as ordinary events. Every read that serves business logic
  or an external consumer resolves them:
  - a committed event (no_commit = false) is visible
  - a pending event that a Confirmation lists is visible
  - a pending event that a Revocation lists reads as NoOp (reason "revoked"),
    even if a Confirmation also lists it
  - any other pending event reads as NoOp (reason "uncommitted") — except to
    a handler running in the same cascade, which sees it
  - the framework events themselves read as NoOp (reason "framework_event")

  CascadeCommit / CascadeRollback name a cascade_id; the framework fans out
  a Confirmation / Revocation to every aggregate holding pending events of
  that cascade.

  Background:
    Given an "order" aggregate "order-1" with committed events at sequences 0 and 1

  # ---------------------------------------------------------------------------
  # Writing pending events
  # ---------------------------------------------------------------------------

  @C-0411
  Scenario: A command with a cascade_id persists pending events
    When an AddItem command for "order-1" is handled with cascade_id "cascade-A"
    Then an ItemAdded event is persisted at sequence 2
    And the persisted page has no_commit true and cascade_id "cascade-A"

  @C-0412
  Scenario: A command without a cascade_id persists committed events
    When an AddItem command for "order-1" is handled with no cascade_id
    Then the persisted page at sequence 2 has no_commit false and no cascade_id

  # ---------------------------------------------------------------------------
  # Visibility of pending events
  # ---------------------------------------------------------------------------

  @C-0413
  Scenario: A pending event is hidden from business logic outside its cascade
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-A"
    When "order-1" is read for business logic with no cascade
    Then sequences 0 and 1 are visible events
    And sequence 2 reads as NoOp with reason "uncommitted" and cascade_id "cascade-A"

  @C-0414
  Scenario: A pending event is visible to a handler in the same cascade
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-A"
    When an AddItem command for "order-1" is handled with cascade_id "cascade-A"
    Then the command handler's prior events include the ItemAdded event at sequence 2

  @C-0415
  Scenario: A query never returns a pending event as a business event
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-A"
    When "order-1" is queried through EventQueryService
    Then sequence 2 reads as NoOp with reason "uncommitted"

  # ---------------------------------------------------------------------------
  # Confirmation and revocation
  # ---------------------------------------------------------------------------

  @C-0416
  Scenario: Confirmation makes the listed pending events visible
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-A"
    When a Confirmation for "order-1" lists sequence 2 with cascade_id "cascade-A"
    Then "order-1" read for business logic shows an ItemAdded event at sequence 2
    And the Confirmation is persisted at sequence 3
    And sequence 3 reads as NoOp with reason "framework_event"

  @C-0417
  Scenario: Revocation hides the listed pending events
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-A"
    When a Revocation for "order-1" lists sequence 2 with cascade_id "cascade-A" and reason "saga_failed"
    Then sequence 2 reads as NoOp with reason "revoked"
    And the aggregate's next_sequence is 4

  @C-0418
  Scenario: Revocation wins over Confirmation for the same sequence
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-A"
    And a Confirmation for "order-1" lists sequence 2 with cascade_id "cascade-A"
    When a Revocation for "order-1" lists sequence 2 with cascade_id "cascade-A" and reason "timeout"
    Then sequence 2 reads as NoOp with reason "revoked"

  @C-0419
  Scenario: Compensate leaves the original events visible
    When a Compensate for "order-1" lists sequence 1 with reason "payment refunded"
    Then "order-1" read for business logic shows the event at sequence 1
    And the Compensate marker reads as NoOp with reason "framework_event"
    And the order's compensation handler is invoked for sequence 1

  # ---------------------------------------------------------------------------
  # Cascade-wide commit and rollback
  # ---------------------------------------------------------------------------

  @C-0420
  Scenario: CascadeCommit confirms every participant of the cascade
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-B"
    And an "inventory" aggregate "sku-1" has a pending StockReserved event at sequence 5 in cascade "cascade-B"
    When a CascadeCommit for "cascade-B" is emitted
    Then "order-1" receives a Confirmation listing sequence 2 with cascade_id "cascade-B"
    And "sku-1" receives a Confirmation listing sequence 5 with cascade_id "cascade-B"
    And both pending events are visible to business logic

  @C-0421
  Scenario: CascadeRollback revokes every participant of the cascade
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-B"
    And an "inventory" aggregate "sku-1" has a pending StockReserved event at sequence 5 in cascade "cascade-B"
    When a CascadeRollback for "cascade-B" with reason "payment declined" is emitted
    Then "order-1" receives a Revocation listing sequence 2 with cascade_id "cascade-B" and reason "payment declined"
    And "sku-1" receives a Revocation listing sequence 5 with cascade_id "cascade-B" and reason "payment declined"
    And both pending events read as NoOp with reason "revoked"

  @C-0422
  Scenario: CascadeCommit leaves other cascades pending
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-B"
    And "order-1" has a pending OrderNoteAdded event at sequence 3 in cascade "cascade-C"
    When a CascadeCommit for "cascade-B" is emitted
    Then sequence 2 is visible to business logic
    And sequence 3 reads as NoOp with reason "uncommitted" and cascade_id "cascade-C"

  # ---------------------------------------------------------------------------
  # Conflicts with another cascade's pending events
  # ---------------------------------------------------------------------------

  @C-0423
  Scenario: A command whose fields overlap another cascade's pending events is rejected
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-B" changing item_count
    When an AddItem command for "order-1" is handled with cascade_id "cascade-D"
    Then the command fails with ABORTED status
    And the error details are a CascadeConflictDetail with cascade_ids "cascade-B" and overlapping_fields "item_count"
    And no events are persisted

  @C-0424
  Scenario: A command whose fields do not overlap another cascade's pending events proceeds
    Given "order-1" has a pending ItemAdded event at sequence 2 in cascade "cascade-B" changing item_count
    When a ChangeShippingAddress command for "order-1" is handled with cascade_id "cascade-D"
    Then a ShippingAddressChanged event is persisted at sequence 3 with no_commit true and cascade_id "cascade-D"
