Feature: Conflict resolution - how the coordinator treats a stale command
  A command may say which stream head it was decided against (its expected
  sequence). When the stream has moved on since, the command is stale, and
  its conflict resolution decides what happens. Three resolutions exist:

  - STRICT: a stale command is rejected as ABORTED before business code
    runs; the caller re-reads and re-issues.
  - AGGREGATE_HANDLES: business code receives the events the command did
    not see (the window) with a nonce, and applies its own conflict rule.
  - COMMUTATIVE: delivered exactly like AGGREGATE_HANDLES; the client
    library compares conflict units itself (handler-contract,
    handling.feature).

  Which resolutions a stream supports comes from its registered state. Every
  state supports STRICT and AGGREGATE_HANDLES; COMMUTATIVE only where the
  state declares conflict units. With no resolution given, the default is
  COMMUTATIVE where supported and STRICT otherwise.

  A command without an expected sequence is decided against the head, so it
  is never stale. Reaction commands (from policies; a process manager sends
  none, decision 14.31) never carry an expected sequence or a resolution.

  Background:
    Given an "order" aggregate whose registered state supports COMMUTATIVE
    And the aggregate has events:
      | sequence | type           |
      | 0        | OrderCreated   |
      | 1        | ItemAdded      |
      | 2        | OrderNoteAdded |
    # next_sequence is 3

  # ===========================================================================
  # The default resolution
  # ===========================================================================

  @conflict_resolution
  @C-0155
  Scenario Outline: A command that names no resolution gets the state's default
    Given an "order" aggregate whose registered state <supports>
    And an AddItem command with no conflict resolution targeting sequence 1
    When the coordinator processes the command
    Then the command is handled under <resolution>

    Examples:
      | supports                       | resolution  |
      | supports COMMUTATIVE           | COMMUTATIVE |
      | does not support COMMUTATIVE   | STRICT      |

  @conflict_resolution
  @C-0531
  Scenario: A command naming a resolution its stream does not support is refused
    Given an "order" aggregate whose registered state does not support COMMUTATIVE
    And an AddItem command with conflict resolution COMMUTATIVE targeting sequence 3
    When the coordinator processes the command
    Then the command fails with INVALID_ARGUMENT status
    And business code is not invoked
    And no events are persisted

  # ===========================================================================
  # STRICT - optimistic concurrency
  # ===========================================================================

  @strict
  @C-0160
  Scenario: Strict - a command at the head succeeds without a nonce
    Given an AddItem command with conflict resolution STRICT targeting sequence 3
    When the coordinator processes the command
    Then the command succeeds
    And business code received no conflict nonce
    And an ItemAdded event is persisted at sequence 3

  @strict
  @C-0161
  Scenario: Strict - a stale command is rejected before business code
    Given a ChangeShippingAddress command with conflict resolution STRICT targeting sequence 1
    When the coordinator processes the command
    Then the command fails with ABORTED status
    And business code is not invoked
    And no events are persisted

  @strict
  @C-0162
  Scenario: Strict - a command ahead of the stream is rejected
    Given an AddItem command with conflict resolution STRICT targeting sequence 5
    When the coordinator processes the command
    Then the command fails with ABORTED status
    And no events are persisted

  # ===========================================================================
  # AGGREGATE_HANDLES - business code owns the conflict rule
  # ===========================================================================

  @aggregate_handles
  @C-0164
  Scenario: AggregateHandles - a stale command reaches business code with the window and a nonce
    Given an AddItem command with conflict resolution AGGREGATE_HANDLES targeting sequence 1
    When the coordinator processes the command
    Then business code is invoked
    And business code receives the events at sequences 1 and 2 as the window
    And business code receives a conflict nonce

  @aggregate_handles
  @C-0532
  Scenario: AggregateHandles - a snapshot inside the window is not used
    Given the "order" aggregate has a snapshot at sequence 2
    And an AddItem command with conflict resolution AGGREGATE_HANDLES targeting sequence 1
    When the coordinator processes the command
    Then business code receives no snapshot
    And business code receives the events at sequences 1 and 2 as the window

  @aggregate_handles
  @C-0165
  Scenario: AggregateHandles - a business rejection is returned unchanged
    Given an AddItem command with conflict resolution AGGREGATE_HANDLES targeting sequence 1
    And business code rejects the command with reason "order is closed"
    When the coordinator processes the command
    Then the command fails with the business rejection reason "order is closed"
    And no events are persisted

  @aggregate_handles
  @C-0166
  Scenario: AggregateHandles - two stale commands that business code accepts both apply
    Given business code accepts every window it examines
    And two AddItem commands with conflict resolution AGGREGATE_HANDLES both targeting sequence 1
    When the coordinator processes both commands
    Then both commands succeed
    And ItemAdded events are persisted at sequences 3 and 4

  @aggregate_handles
  @C-0551
  Scenario: Each delivery carries a fresh nonce
    Given an AddItem command with conflict resolution AGGREGATE_HANDLES targeting sequence 1
    And business code rejects the first delivery with reason "try again"
    When the caller sends the same command twice
    Then business code is invoked twice
    And the two deliveries carry different conflict nonces

  # ===========================================================================
  # COMMUTATIVE - delivered like AGGREGATE_HANDLES
  # ===========================================================================

  @commutative
  @C-0149
  Scenario: Commutative - a command at the head is delivered with an empty window and a nonce
    Given an AddItem command with conflict resolution COMMUTATIVE targeting sequence 3
    When the coordinator processes the command
    Then business code receives an empty window
    And business code receives a conflict nonce
    And an ItemAdded event is persisted at sequence 3

  @conflict_resolution
  @C-0172
  Scenario Outline: The resolution decides how a stale command is delivered
    Given an AddItem command with conflict resolution <resolution> targeting sequence 1
    When the coordinator processes the command
    Then the outcome is <outcome>

    Examples:
      | resolution        | outcome                                                   |
      | STRICT            | rejected with ABORTED before business code                |
      | AGGREGATE_HANDLES | delivered to business code with the window and a nonce    |
      | COMMUTATIVE       | delivered to business code with the window and a nonce    |

  # ===========================================================================
  # Reaction commands: never stale
  # ===========================================================================

  @reaction
  @C-0458
  Scenario: A reaction command is decided against the head
    Given a policy-emitted AddItem command with no expected sequence and no conflict resolution
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 3

  @reaction
  @C-0552
  Scenario: A reaction command that names an expected sequence is a reactor bug
    Given a policy-emitted AddItem command targeting sequence 1
    When the coordinator processes the command
    Then the command is not delivered to business code
    And the command is dead-lettered and an alert is raised
    And no events are persisted

  @reaction
  @C-0459
  Scenario: A reaction command is guarded only by the destination's own decision
    Given a policy-emitted AddItem command with no expected sequence and no conflict resolution
    And business code rejects the command with reason "order is closed"
    When the coordinator processes the command
    Then the command fails with the business rejection reason "order is closed"
    And no events are persisted

  @reaction
  @C-0460
  Scenario: A redelivered reaction command is applied once
    Given a policy-emitted AddItem command
    When the coordinator processes the command
    And the coordinator processes the same command again
    Then exactly one ItemAdded event is persisted
    And the second delivery returns the events of the first

  # ===========================================================================
  # Edge cases
  # ===========================================================================

  @conflict_resolution @edge_case
  @C-0174
  Scenario Outline: A new stream accepts sequence 0 under every resolution
    Given a new "order" aggregate with no events
    And a CreateOrder command with conflict resolution <resolution> targeting sequence 0
    When the coordinator processes the command
    Then the command succeeds
    And an OrderCreated event is persisted at sequence 0

    Examples:
      | resolution        |
      | COMMUTATIVE       |
      | STRICT            |
      | AGGREGATE_HANDLES |

  @conflict_resolution @edge_case
  @C-0175
  Scenario: A snapshot moves the head forward
    Given an "order" aggregate with a snapshot at sequence 50 and events at sequences 51 and 52
    And an AddItem command with conflict resolution STRICT targeting sequence 53
    When the coordinator processes the command
    Then the command succeeds
    And an ItemAdded event is persisted at sequence 53
