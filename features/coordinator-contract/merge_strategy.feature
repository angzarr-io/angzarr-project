# DOC: This file is referenced in docs/docs/reference/patterns.mdx
#      Update documentation when making changes to merge strategy patterns.

Feature: Merge strategy - concurrency control for stale commands
  Every CommandPage carries a MergeStrategy. It decides what the aggregate
  coordinator does when the command's expected sequence differs from the
  aggregate's next_sequence (a "stale" command). Four strategies exist:

  - COMMUTATIVE (wire value 0, the default): field-overlap merge. The
    coordinator runs the command against current state, then compares the
    state fields its events change with the state fields changed by the
    events the command did not see. Disjoint changes are persisted; any
    overlap rejects with a retryable FAILED_PRECONDITION.
  - STRICT: optimistic concurrency. Any mismatch rejects with a retryable
    FAILED_PRECONDITION; the caller reloads and resubmits.
  - AGGREGATE_HANDLES: the coordinator does not validate the sequence; the
    command handler receives the full prior history and decides.
  - MANUAL: a mismatch is dead-lettered for human review and rejected with
    a non-retryable ABORTED.

  The concurrency window is the run of events the command did not see:
  sequences basis .. actual-1, where actual is the aggregate's
  next_sequence and basis is
  - the explicit PageHeader.sequence of a client command, or
  - AngzarrDeferredSequence.basis_seq of a saga/PM-emitted (deferred)
    command. basis_seq 0 means no basis was recorded: the window is the
    whole history.

  Field changes are computed with the command handler's Replay RPC: the
  coordinator replays state at basis, at actual, and at actual plus the
  command's events, and diffs them field by field.

  Background:
    Given an "order" aggregate whose state has fields status, shipping_address, notes and item_count
    And the command handler implements Replay
    And the aggregate has events:
      | sequence | type           | changes            |
      | 0        | OrderCreated   | status, item_count |
      | 1        | ItemAdded      | item_count         |
      | 2        | OrderNoteAdded | notes              |
    # next_sequence is 3

  # ===========================================================================
  # MERGE_COMMUTATIVE - field-overlap merge (default)
  # ===========================================================================

  @merge_commutative
  @C-0149
  Scenario: Commutative - command at the current sequence succeeds
    Given an AddItem command with merge_strategy COMMUTATIVE targeting sequence 3
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @merge_commutative
  @C-0150
  Scenario: Commutative - stale command whose fields do not overlap the window is merged
    Given a ChangeShippingAddress command with merge_strategy COMMUTATIVE targeting sequence 1
    When the coordinator processes the command
    Then the command succeeds
    And a ShippingAddressChanged event is persisted at sequence 3

  @merge_commutative
  @C-0151
  Scenario: Commutative - stale command whose fields overlap the window is rejected as retryable
    Given an AddItem command with merge_strategy COMMUTATIVE targeting sequence 1
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    And the error is marked as retryable
    And the overlapping fields reported are item_count
    And no events are persisted

  @merge_commutative
  @C-0152
  Scenario: Commutative - only events after the basis count toward overlap
    # The window is sequence 2 only (notes); item_count changed at sequence 1,
    # which the command already saw.
    Given an AddItem command with merge_strategy COMMUTATIVE targeting sequence 2
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @merge_commutative
  @C-0153
  Scenario: Commutative - a rejected command succeeds after reloading and resubmitting
    Given an AddItem command with merge_strategy COMMUTATIVE targeting sequence 1
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    When the client reloads the aggregate and resubmits the command targeting sequence 3
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @merge_commutative
  @C-0154
  Scenario: Commutative - without Replay the coordinator falls back to STRICT
    Given the command handler does not implement Replay
    And a ChangeShippingAddress command with merge_strategy COMMUTATIVE targeting sequence 1
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    And the error is marked as retryable
    And no events are persisted

  @merge_commutative
  @C-0155
  Scenario: Commutative - unset merge_strategy is COMMUTATIVE
    Given a ChangeShippingAddress command with no merge_strategy set targeting sequence 1
    When the coordinator processes the command
    Then the command succeeds
    And a ShippingAddressChanged event is persisted at sequence 3

  # ---------------------------------------------------------------------------
  # Deferred (saga/PM-emitted) commands: the window starts at basis_seq
  # ---------------------------------------------------------------------------

  @merge_commutative @deferred
  @C-0156
  Scenario: Commutative - deferred command merges when nothing after its basis overlaps
    Given a saga-emitted AddItem command with merge_strategy COMMUTATIVE and basis_seq 2
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @merge_commutative @deferred
  @C-0157
  Scenario: Commutative - deferred command is rejected when an event after its basis overlaps
    Given a saga-emitted AddItem command with merge_strategy COMMUTATIVE and basis_seq 1
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    And the error is marked as retryable
    And no events are persisted

  @merge_commutative @deferred
  @C-0158
  Scenario: Commutative - deferred command with basis_seq 0 is checked against the whole history
    Given a saga-emitted AddItem command with merge_strategy COMMUTATIVE and basis_seq 0
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    And the overlapping fields reported are item_count

  @merge_commutative @deferred
  @C-0159
  Scenario: Commutative - deferred command with basis_seq 0 merges when no historical event touched its fields
    Given a saga-emitted ChangeShippingAddress command with merge_strategy COMMUTATIVE and basis_seq 0
    When the coordinator processes the command
    Then the command succeeds
    And a ShippingAddressChanged event is persisted at sequence 3

  # ===========================================================================
  # MERGE_STRICT - optimistic concurrency
  # ===========================================================================

  @merge_strict
  @C-0160
  Scenario: Strict - command at the current sequence succeeds
    Given an AddItem command with merge_strategy STRICT targeting sequence 3
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @merge_strict
  @C-0161
  Scenario: Strict - stale command is rejected even when its fields do not overlap
    Given a ChangeShippingAddress command with merge_strategy STRICT targeting sequence 1
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    And the error is marked as retryable
    And the error message contains "Sequence mismatch"
    And no events are persisted

  @merge_strict
  @C-0162
  Scenario: Strict - command ahead of the aggregate is rejected
    Given an AddItem command with merge_strategy STRICT targeting sequence 5
    When the coordinator processes the command
    Then the command fails with FAILED_PRECONDITION status
    And no events are persisted

  @merge_strict @deferred
  @C-0163
  Scenario: Strict - deferred command is stamped at the destination head
    # A deferred command claims no destination sequence, so there is no
    # expected sequence to enforce; the framework assigns next_sequence.
    Given a saga-emitted ChangeShippingAddress command with merge_strategy STRICT and basis_seq 1
    When the coordinator processes the command
    Then the command succeeds
    And a ShippingAddressChanged event is persisted at sequence 3

  # ===========================================================================
  # MERGE_AGGREGATE_HANDLES - the command handler owns concurrency
  # ===========================================================================

  @merge_aggregate_handles
  @C-0164
  Scenario: AggregateHandles - stale command reaches the handler with the full prior history
    Given an AddItem command with merge_strategy AGGREGATE_HANDLES targeting sequence 0
    When the coordinator processes the command
    Then the command handler is invoked
    And the handler receives prior events at sequences 0, 1 and 2
    And an ItemAdded event is persisted at sequence 3

  @merge_aggregate_handles
  @C-0165
  Scenario: AggregateHandles - handler rejection is returned unchanged
    Given an AddItem command with merge_strategy AGGREGATE_HANDLES targeting sequence 1
    And the command handler rejects the command with reason "order is closed"
    When the coordinator processes the command
    Then the command fails with the handler's rejection reason "order is closed"
    And no events are persisted

  @merge_aggregate_handles
  @C-0166
  Scenario: AggregateHandles - concurrent increments both apply
    Given two AddItem commands with merge_strategy AGGREGATE_HANDLES both targeting sequence 1
    When the coordinator processes both commands
    Then both commands succeed
    And ItemAdded events are persisted at sequences 3 and 4

  # ===========================================================================
  # MERGE_MANUAL - dead-letter for human review
  # ===========================================================================

  @merge_manual
  @C-0167
  Scenario: Manual - command at the current sequence succeeds
    Given an AddItem command with merge_strategy MANUAL targeting sequence 3
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @merge_manual
  @C-0168
  Scenario: Manual - stale command is dead-lettered and rejected as non-retryable
    Given a ChangeShippingAddress command with merge_strategy MANUAL targeting sequence 1
    When the coordinator processes the command
    Then the command fails with ABORTED status
    And the error is not marked as retryable
    And no events are persisted
    And a dead letter is published to "angzarr.dlq.order" carrying the rejected command
    And the dead letter's sequence mismatch details are:
      | field             | value        |
      | expected_sequence | 1            |
      | actual_sequence   | 3            |
      | merge_strategy    | MERGE_MANUAL |

  @merge_manual @deferred
  @C-0169
  Scenario: Manual - deferred command whose fields do not overlap after its basis is merged
    Given a saga-emitted ChangeShippingAddress command with merge_strategy MANUAL and basis_seq 1
    When the coordinator processes the command
    Then the command succeeds
    And a ShippingAddressChanged event is persisted at sequence 3
    And no dead letter is published

  @merge_manual @deferred
  @C-0170
  Scenario: Manual - deferred command whose fields overlap after its basis is dead-lettered
    Given a saga-emitted AddItem command with merge_strategy MANUAL and basis_seq 1
    When the coordinator processes the command
    Then the command fails with ABORTED status
    And no events are persisted
    And a dead letter is published to "angzarr.dlq.order" carrying the rejected command

  @merge_manual @deferred
  @C-0171
  Scenario: Manual - deferred command is dead-lettered when overlap cannot be computed
    Given the command handler does not implement Replay
    And a saga-emitted ChangeShippingAddress command with merge_strategy MANUAL and basis_seq 1
    When the coordinator processes the command
    Then the command fails with ABORTED status
    And a dead letter is published to "angzarr.dlq.order" carrying the rejected command

  # ===========================================================================
  # Cross-strategy
  # ===========================================================================

  @merge_strategy
  @C-0172
  Scenario Outline: Strategy decides the outcome of a stale, overlapping command
    Given an AddItem command with merge_strategy <strategy> targeting sequence 1
    When the coordinator processes the command
    Then the outcome is <outcome>

    Examples:
      | strategy          | outcome                                     |
      | COMMUTATIVE       | rejected with retryable FAILED_PRECONDITION |
      | STRICT            | rejected with retryable FAILED_PRECONDITION |
      | AGGREGATE_HANDLES | delegated to the command handler            |
      | MANUAL            | dead-lettered and rejected with ABORTED     |

  @merge_strategy
  @C-0173
  Scenario Outline: Strategy decides the outcome of a stale, non-overlapping command
    Given a ChangeShippingAddress command with merge_strategy <strategy> targeting sequence 1
    When the coordinator processes the command
    Then the outcome is <outcome>

    Examples:
      | strategy          | outcome                                     |
      | COMMUTATIVE       | merged and persisted at sequence 3          |
      | STRICT            | rejected with retryable FAILED_PRECONDITION |
      | AGGREGATE_HANDLES | delegated to the command handler            |
      | MANUAL            | dead-lettered and rejected with ABORTED     |

  # ===========================================================================
  # Edge cases
  # ===========================================================================

  @merge_strategy @edge_case
  @C-0174
  Scenario Outline: A new aggregate accepts sequence 0 under every strategy
    Given a new "order" aggregate with no events
    And a CreateOrder command with merge_strategy <strategy> targeting sequence 0
    When the coordinator processes the command
    Then the command succeeds
    And an OrderCreated event is persisted at sequence 0

    Examples:
      | strategy          |
      | COMMUTATIVE       |
      | STRICT            |
      | AGGREGATE_HANDLES |
      | MANUAL            |

  @merge_strategy @edge_case
  @C-0175
  Scenario: A snapshot moves next_sequence forward
    Given an "order" aggregate with a snapshot at sequence 50 and events at sequences 51 and 52
    And an AddItem command with merge_strategy STRICT targeting sequence 53
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 53

  @merge_strategy @edge_case
  @C-0176
  Scenario: A CommandBook with no pages has the default strategy
    Given a CommandBook with no pages
    When its merge_strategy is resolved
    Then the result is COMMUTATIVE
