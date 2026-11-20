Feature: Order policy dispatch
  The OrderPolicy (fixture/FIXTURE.md) proves the translation-side dispatch
  mechanisms every router implements identically: React is handed one
  trigger event (decision 46, Q3), and a declared source event answers an
  Output holding only the destination root and the payload in its arm, a
  command or a fact (decisions 14.78 and 14.91), passed through unstamped
  and unchecked (the coordinator addresses, checks and stamps it, decision
  14.42); its handler sees the triggering event's sequence, and an
  undeclared event emits nothing. Ported from angzarr-router's own
  conformance features.

  @policy
  @C-0709
  Scenario: A declared event emits a command, as a root and a payload
    Given an order policy delivering to "inventory"
    When React is handed a trigger book holding only an Increased event at sequence 7
    Then the policy emits one output, a Reserve in the command arm with the root business code named
    And the output carries no domain, no edition, no command id, no correlation and no causation

  @policy
  @C-0710
  Scenario: An undeclared event emits nothing
    Given an order policy delivering to "inventory"
    When a Reserve event is dispatched
    Then the policy emits no commands

  @policy
  @C-0711
  Scenario: A policy handler sees the triggering event's sequence
    Given an order policy delivering to "inventory"
    When an Increased event at sequence 7 is dispatched
    Then the policy handler saw source sequence 7
