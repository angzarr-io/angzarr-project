# Allocated: C-0121 .. C-0122
#
# Cross-language contract for the class-level kind declarations. Every
# language binds @command_handler / @saga / @process_manager / @projector /
# @upcaster to the same HandlerConfig shape once applied.
Feature: Kind-declaration parity

  @C-0121
  Scenario: Applying @command_handler records the domain
    Given a class "Order" decorated as a command handler for domain "order" with state OrderState
    Then the class exposes a handler config of kind "command_handler"
    And the handler config's domain is "order"

  @C-0122
  Scenario: Applying @saga records name, source, and target
    Given a class "OrderFulfillment" decorated as a saga named "OrderFulfillment" from "order" to "inventory"
    Then the class exposes a handler config of kind "saga"
    And the handler config's saga name is "OrderFulfillment"
    And the handler config's saga source is "order"
    And the handler config's saga target is "inventory"

  @C-0126
  Scenario: Applying @upcaster records name and domain
    Given a class "PlayerUpcaster" decorated as an upcaster named "player-v1-to-v2" in domain "player"
    Then the class exposes a handler config of kind "upcaster"
    And the handler config's upcaster name is "player-v1-to-v2"
    And the handler config's upcaster domain is "player"
