Feature: Order policy dispatch
  The OrderPolicy (fixture/FIXTURE.md) proves the translation-side dispatch
  mechanisms every router implements identically: a declared source event
  emits a command (passed through unstamped and unchecked: the coordinator
  checks, stamps its identity and provenance, decision 14.42) and its
  handler sees the triggering event's sequence, and an undeclared event
  emits nothing. Ported from angzarr-router's own conformance features.

  @policy
  @C-0709
  Scenario: A declared event emits a command
    Given an order policy delivering to "inventory"
    When an Increased event at sequence 7 is dispatched
    Then the policy emits one command to "inventory", in the reaction to sequence 7
    And the command carries no router-stamped provenance

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
