Feature: Component declarations - fact handlers and fact lint
  angzarr-cli reads ComponentOptions from compiled descriptors, lints the
  declarations across the whole proto tree, and generates per-component
  handler interfaces and dispatch tables. These scenarios pin the `facts`
  and `emits_facts` declarations (options.proto).

  - facts (AGGREGATE only): fully-qualified event types the aggregate
    accepts as facts. One fact handler per entry; dispatch routes a fact by
    its fully-qualified type.
  - emits_facts (SAGA / PROCESS_MANAGER only): fact types the component
    injects into its output domains. Each must be declared in `facts` by an
    aggregate owning one of those domains.

  @C-0486
  Scenario: An aggregate's facts declaration generates one fact handler per entry
    Given an aggregate "OrderState" owning domain "order" declaring facts "shipping.ShipmentDispatched" and "payment.PaymentCaptured"
    When code is generated
    Then the OrderState handler interface has a ShipmentDispatched fact handler and a PaymentCaptured fact handler, in declaration order
    And the generated dispatch routes a "shipping.ShipmentDispatched" fact to the ShipmentDispatched fact handler

  @C-0487
  Scenario Outline: facts is a lint error outside aggregates
    Given a <kind> component declaring facts "shipping.ShipmentDispatched"
    When the protos are linted
    Then lint reports an error that facts is allowed only on aggregates

    Examples:
      | kind            |
      | PROCESS_MANAGER |
      | SAGA            |
      | PROJECTOR       |

  @C-0488
  Scenario: A saga emitting a fact type no target-domain aggregate declares is a lint error
    Given an aggregate "OrderState" owning domain "order" declaring facts "shipping.ShipmentDispatched"
    And a saga "ShippingToOrder" from "shipping" to "order" declaring emits_facts "shipping.ShipmentDelayed"
    When the protos are linted
    Then lint reports an error naming fact type "shipping.ShipmentDelayed" and output domain "order"

  @C-0489
  Scenario: A saga emitting a fact type its target-domain aggregate declares lints clean
    Given an aggregate "OrderState" owning domain "order" declaring facts "shipping.ShipmentDispatched"
    And a saga "ShippingToOrder" from "shipping" to "order" declaring emits_facts "shipping.ShipmentDispatched"
    When the protos are linted
    Then lint reports no error for "ShippingToOrder"
