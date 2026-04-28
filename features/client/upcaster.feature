# Allocated: C-0123 .. C-0125, C-0136 .. C-0137
#
# Cross-language contract for upcaster kind declarations and method
# markers. Full Router-builder / Handler-trait integration for upcasters
# is tracked separately; the C-0123..C-0125 scenarios pin the symbol surface
# and attribute shape, the C-0136..C-0137 scenarios pin dispatch chaining.
Feature: Upcaster macros

  @C-0123
  Scenario: upcaster decorator is applicable with name and domain
    Given a class "PlayerUpcaster" decorated as an upcaster named "player-v1-to-v2" in domain "player"
    Then the class declaration compiles without error

  @C-0124
  Scenario: upcasts method marker is applicable with from and to types
    Given a method declared as upcasting from "PlayerRegisteredV1" to "PlayerRegisteredV2"
    Then the method declaration compiles without error

  @C-0125
  Scenario: state_factory method marker is applicable
    Given a method declared as a state factory
    Then the method declaration compiles without error

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
    When I dispatch the upcast request
    Then the emitted event has type V3

  @C-0137
  Scenario: chain stops when no further upcaster matches the current event type
    Given an upcaster registered for V1 → V2
    And an upcaster registered for V3 → V4
    And an incoming event of type V1
    When I dispatch the upcast request
    Then the emitted event has type V2
