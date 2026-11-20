Feature: The generated component descriptor
  angzarr-cli generates a component's whole ComponentDescriptor at build
  time from its protos: its name and, in the arm of its kind (the
  descriptor's kind oneof, decision 14.78), what that kind has: an
  aggregate's domain and state, a process manager's domain, state and
  starting types, a policy's derived input domain and its output domain, a
  projector's derived input domains; with the build's baked-in version as
  its rules version. Types are named by their fully-qualified NAME, never a
  type URL (StateDescriptor.type_name; decision 14.101). The business
  process answers ComponentService.Describe with it unchanged; the router
  neither builds nor checks it, and the coordinator validates it (decision
  14.42; coordinator-contract component_discovery.feature, C-0687). C-0535
  and C-0565 moved here from handler-contract.

  @descriptor
  @C-0535
  Scenario: The generated descriptor carries the build version and the state type's name
    Given an aggregate component "order" owning domain "order" whose state message is "orders.v1.OrderState"
    And the business binary is built as version "1.4.2+build.7"
    When the component's descriptor is generated
    Then the descriptor carries rules version "1.4.2+build.7"
    And its aggregate arm carries domain "order" and state type_name "orders.v1.OrderState"

  @descriptor
  @C-0565
  Scenario: The business process describes its one component with the generated descriptor
    Given an "order" business binary built as version "1.4.2+build.7" from its generated descriptor
    When the coordinator asks the "order" business binary to describe its component
    Then the answer describes one component:
      | name  | kind      | domain | rules version | state type_name      |
      | order | aggregate | order  | 1.4.2+build.7 | orders.v1.OrderState |
    And the answer is the generated descriptor, unchanged
    And business code is not invoked

  @descriptor
  @C-0715
  Scenario: A policy's descriptor names its one derived input domain and its one output domain
    # The input domain is derived from the events the policy names
    # (decision 14.78); the output domain is PolicyDecl.output_domain.
    Given an aggregate "OrderState" owning domain "order" that folds "order.OrderPlaced"
    And a policy "order-to-inventory" with output_domain "inventory" whose (event) entries name "order.OrderPlaced"
    When the component's descriptor is generated
    Then the descriptor's policy arm carries input_domain "order" and output_domain "inventory"
    And the descriptor has no aggregate, process_manager or projector arm

  @descriptor
  @C-0716
  Scenario Outline: Each kind's descriptor carries only what its arm has
    # The kind is a oneof (decision 14.78): nothing can be set on a kind
    # that may not have it.
    Given <kind> component "<name>"
    When the component's descriptor is generated
    Then the descriptor's <arm> arm is set, carrying <carries>
    And no other kind arm is set

    Examples:
      | kind              | name                 | arm             | carries                                   |
      | an aggregate      | order                | aggregate       | domain and state                          |
      | a process manager | fulfillment          | process_manager | domain, state and starting_types          |
      | a projector       | projector-order-view | projector       | input_domains only                        |

  @descriptor
  @C-0866
  Scenario: A process manager's descriptor names its own domain and its state type's name
    # A required domain, copied from the declaration: after the one
    # component name the name no longer implies it (decisions 14.87, 14.101).
    Given a process manager "fulfillment" owning domain "fulfillment" whose state message is "fulfillment.v1.FulfillmentState"
    And "fulfillment" declares starting_types "fulfillment.v1.StartFulfillment"
    When the component's descriptor is generated
    Then its process_manager arm carries domain "fulfillment"
    And its state type_name is "fulfillment.v1.FulfillmentState"
    And its starting_types are "fulfillment.v1.StartFulfillment", a name with no type URL prefix

  @descriptor
  @C-0867
  Scenario: A projector's descriptor lists each domain whose events it names
    # Derived from the events it names (decision 14.78); no wildcard domain
    # (decision 14.53).
    Given aggregates "OrderState" owning domain "order" and "PaymentState" owning domain "payment"
    And a projector "projector-billing" whose (event) entries name "order.OrderPlaced" and "payment.PaymentCaptured"
    When the component's descriptor is generated
    Then its projector arm lists input_domains "order" and "payment"
