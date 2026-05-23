# Allocated: C-0123 .. C-0125, C-0136 .. C-0137
#
# Cross-language contract for upcaster declarations. The C-0123..C-0125
# scenarios pin the declaration surface (an upcaster's name and domain, its
# source-and-target event types, and its state factory). The C-0136..C-0137
# scenarios pin the dispatch chain.
Feature: Event upcasting

  @C-0123
  Scenario: an upcaster declares its name and domain
    Given an upcaster named "player-v1-to-v2" in domain "player"
    Then the declaration is accepted

  @C-0124
  Scenario: an upcasting rule declares its source and target event types
    Given an upcasting rule from "PlayerRegisteredV1" to "PlayerRegisteredV2"
    Then the declaration is accepted

  @C-0125
  Scenario: an upcaster declares a state factory
    Given an upcaster with a state factory
    Then the declaration is accepted

  # Dispatch chain semantics — audit finding #43.
  # The runtime applies every matching upcaster in registration order:
  # the output of one upcaster is the input of the next. This lets schema
  # evolution compose across versions (V1 → V2 → V3) without forcing each
  # upcaster to know about every newer version.

  @C-0136
  Scenario: chained upcasters transform an event across two versions
    Given an upcaster registered for V1 → V2
    And an upcaster registered for V2 → V3
    And an incoming event of type V1
    When the V1 event is upcasted
    Then the emitted event has type V3

  @C-0137
  Scenario: chain stops when no further upcaster matches the current event type
    Given an upcaster registered for V1 → V2
    And an upcaster registered for V3 → V4
    And an incoming event of type V1
    When the V1 event is upcasted
    Then the emitted event has type V2
