Feature: The generated component descriptor
  angzarr-cli generates a component's whole ComponentDescriptor at build
  time from its protos: its name, kind, input domains, state descriptor,
  starting types and, for a policy, its output domain, with the build's
  baked-in version as its rules version. The business process answers
  ComponentService.Describe with it unchanged; the router neither builds
  nor checks it, and the coordinator validates it (decision 14.42;
  coordinator-contract component_discovery.feature, C-0687). C-0535 and
  C-0565 moved here from handler-contract.

  @descriptor
  @C-0535
  Scenario: The generated descriptor carries the build version and the state type
    Given an "order" aggregate component whose state message is "orders.v1.OrderState"
    And the business binary is built as version "1.4.2+build.7"
    When the component's descriptor is generated
    Then the descriptor carries rules version "1.4.2+build.7"
    And the descriptor carries the state type "/orders.v1.OrderState"

  @descriptor
  @C-0565
  Scenario: The business process describes its one component with the generated descriptor
    Given an "order" business binary built as version "1.4.2+build.7" from its generated descriptor
    When the coordinator asks the "order" business binary to describe its component
    Then the answer describes one component:
      | name  | kind      | rules version | state type            |
      | order | AGGREGATE | 1.4.2+build.7 | /orders.v1.OrderState |
    And the answer is the generated descriptor, unchanged
    And business code is not invoked

  @descriptor
  @C-0715
  Scenario: A policy's descriptor names its one input and its one output domain
    Given a POLICY component "OrderToInventory" with input domain "order" and output domain "inventory"
    When the component's descriptor is generated
    Then the descriptor lists input domain "order" only
    And the descriptor carries output domain "inventory"
    And the descriptor carries no state

  @descriptor
  @C-0716
  Scenario Outline: Only a policy's descriptor carries an output domain
    Given a <kind> component "<name>"
    When the component's descriptor is generated
    Then the descriptor carries no output domain

    Examples:
      | kind            | name         |
      | AGGREGATE       | order        |
      | PROCESS_MANAGER | Fulfillment  |
      | PROJECTOR       | OrderSummary |
