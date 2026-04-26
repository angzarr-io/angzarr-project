# Allocated: C-0123 .. C-0125
#
# Cross-language contract for upcaster kind declarations and method
# markers. Full Router-builder / Handler-trait integration for upcasters
# is tracked separately; these scenarios pin the symbol surface and
# attribute shape only.
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
