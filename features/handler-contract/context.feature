Feature: Facts and handler context
  Beyond commands, an aggregate handles facts: external realities delivered
  in the Fact arm of the command page, each recorded by the fact handler
  registered for its type, optionally followed by events that flag it,
  never refused. A fact whose type has no fact handler (a command type
  included: the arm must match the handler's kind) is refused with
  ANGZARR_REASON_NO_FACT_HANDLER and nothing is recorded. Appliers see each event's
  sequence; handlers read the cover they are handling; a projector fold
  knows where each event sits. A policy handler and a projector fold read
  the event's whole metadata, as delivered: its cover and sequence, and
  every field of its EventMeta (its command id, correlation, fact origin,
  rules version and recording instant), none withheld (decision 14.61).
  The ledger aggregate, order policy and tracking projector are built over
  the fixture's CounterState (fixture/FIXTURE.md). Roots, command ids and
  correlations are UUID v5 (NAMESPACE_OID) of the quoted label. Ported from
  angzarr-router's own conformance features (decision 14.42).

  @context
  @C-0703
  Scenario: A fact handler records the fact and flags it against the folded state
    Given a ledger aggregate
    When an Increased fact is handled over 3 prior Increased events
    Then the Increased fact is recorded, flagged by the count 4

  @context
  @C-0704
  Scenario: A fact of an undeclared type is refused
    Given a ledger aggregate
    When a Reserve fact is handled over no prior events
    Then the fact is refused with ANGZARR_REASON_NO_FACT_HANDLER as INTERNAL

  @context
  @C-0705
  Scenario: A command delivered as a fact is refused
    Given a ledger aggregate
    When an IncreaseBy fact is handled over no prior events
    Then the fact is refused with ANGZARR_REASON_NO_FACT_HANDLER as INTERNAL

  @context
  @C-0706
  Scenario: An applier reads each event's sequence
    Given a ledger aggregate
    When an IncreaseBy command for ledger root "ledger-1" is dispatched over Increased events at sequences 2 and 3
    Then the ledger applied Increased events at sequences 2 and 3, then its emitted event at 4

  @context
  @C-0707
  Scenario: A command handler reads its own cover
    Given a ledger aggregate
    When an IncreaseBy command for ledger root "ledger-1" is dispatched
    Then the ledger handler saw root "ledger-1"

  @context
  @C-0708
  Scenario: A projector fold reads each event's root and sequence
    Given a tracking projector
    When Increased events of counter root "counter-1" at sequences 4 and 5 are projected
    Then the projector saw root "counter-1" at sequences 4 and 5

  @context
  @C-0757
  Scenario: A policy handler reads its trigger's whole metadata
    Given an order policy delivering to "inventory"
    When an Increased event of counter root "counter-1" at sequence 7 is dispatched, recorded by command "cmd-1" in correlation "corr-1" from fact "pi_1234" under rules version "1.4.2+build.7" at second 1700000000
    Then the policy handler saw root "counter-1" at sequence 7, recorded by command "cmd-1" in correlation "corr-1" from fact "pi_1234" under rules version "1.4.2+build.7" at second 1700000000

  @context
  @C-0758
  Scenario: A projector fold reads each event's whole metadata
    Given a tracking projector
    When an Increased event of counter root "counter-1" at sequence 4 is projected, recorded by command "cmd-1" in correlation "corr-1" from fact "pi_1234" under rules version "1.4.2+build.7" at second 1700000000
    Then the projector saw root "counter-1" at sequence 4, recorded by command "cmd-1" in correlation "corr-1" from fact "pi_1234" under rules version "1.4.2+build.7" at second 1700000000
