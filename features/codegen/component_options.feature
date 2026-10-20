Feature: Component declarations - lint warnings and errors
  angzarr-cli reads ComponentOptions from compiled descriptors, lints the
  declarations across the whole proto tree, and generates per-component
  handler interfaces and dispatch tables. These scenarios pin what
  `angzarr lint` reports: cross-component warnings for declarations that
  compile but are unlikely to work (a warning leaves the exit status
  unaffected), and errors for declarations the contract forbids (an error
  fails the run).

  @C-0514
  Scenario: A command emitting an event its aggregate has no applier for is a lint warning
    Given an aggregate "OrderState" owning domain "order"
    And a command "order.ShipOrder" for "OrderState" whose (command).emits lists "order.OrderShipped"
    And no (event) entry for "order.OrderShipped" names "OrderState"
    When the protos are linted
    Then lint reports warning ANZ100 naming command "order.ShipOrder" and event "order.OrderShipped"
    And lint exits with status 0

  @C-0515
  Scenario Outline: A saga or process manager targeting a domain no aggregate owns is a lint warning
    Given an aggregate "OrderState" owning domain "order"
    And a <kind> component "Fulfillment" triggered by domain "order" with output_domain "inventory"
    When the protos are linted
    Then lint reports warning ANZ101 naming "Fulfillment" and output domain "inventory"
    And lint exits with status 0

    Examples:
      | kind            |
      | SAGA            |
      | PROCESS_MANAGER |

  @C-0516
  Scenario Outline: A saga or process manager triggering on a domain no aggregate produces is a lint warning
    Given an aggregate "InventoryState" owning domain "inventory"
    And a <kind> component "Fulfillment" triggered by domain "order" with output_domain "inventory"
    When the protos are linted
    Then lint reports warning ANZ102 naming "Fulfillment" and source domain "order"
    And lint exits with status 0

    Examples:
      | kind            |
      | SAGA            |
      | PROCESS_MANAGER |

  @C-0517
  Scenario Outline: A component declaring no commands or events is a lint warning
    Given a <kind> component "Idle" that no (command) or (event) entry names
    When the protos are linted
    Then lint reports warning ANZ103 naming "Idle"
    And lint exits with status 0

    Examples:
      | kind            |
      | AGGREGATE       |
      | PROCESS_MANAGER |
      | SAGA            |
      | PROJECTOR       |

  @C-0581
  Scenario: A saga declaring several destination domains is a lint error
    # A saga translates between exactly two domains; several destinations
    # need a process manager.
    Given aggregates owning domains "order", "inventory" and "shipping"
    And a SAGA component "Fulfillment" triggered by domain "order" with output_domain "inventory" and output_domains "shipping"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its output_domains
    And lint exits with a non-zero status

  @C-0582
  Scenario: A saga declaring no destination domain is a lint error
    Given aggregates owning domains "order" and "inventory"
    And a SAGA component "Fulfillment" triggered by domain "order" with no output_domain
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its missing output_domain
    And lint exits with a non-zero status
