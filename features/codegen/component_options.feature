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
  Scenario Outline: A saga targeting a domain no aggregate owns is a lint warning
    # A process manager declares no output domain (decision 14.31; C-0605).
    Given an aggregate "OrderState" owning domain "order"
    And a <kind> component "Fulfillment" triggered by domain "order" with output_domain "inventory"
    When the protos are linted
    Then lint reports warning ANZ101 naming "Fulfillment" and output domain "inventory"
    And lint exits with status 0

    Examples:
      | kind            |
      | SAGA            |

  @C-0516
  Scenario Outline: A saga triggering on a domain no aggregate produces is a lint warning
    # The process manager's case, which declares no output domain, is C-0604.
    Given an aggregate "InventoryState" owning domain "inventory"
    And a <kind> component "Fulfillment" triggered by domain "order" with output_domain "inventory"
    When the protos are linted
    Then lint reports warning ANZ102 naming "Fulfillment" and source domain "order"
    And lint exits with status 0

    Examples:
      | kind            |
      | SAGA            |

  @C-0604
  Scenario: A process manager triggering on a domain no aggregate produces is a lint warning
    Given an aggregate "InventoryState" owning domain "inventory"
    And a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment" triggered by domain "order"
    When the protos are linted
    Then lint reports warning ANZ102 naming "Fulfillment" and source domain "order"
    And lint exits with status 0

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

  # C-0581 (a saga declaring several destinations through output_domains)
  # is retired: ComponentOptions.output_domains is deleted (decision
  # 14.31), so no declaration can name several destinations.

  @C-0605
  Scenario: A process manager declaring an output domain is a lint error
    # A process manager sends no commands; its decisions reach other
    # domains through sagas from its domain (decision 14.31).
    Given aggregates owning domains "order" and "shipping"
    And a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment" triggered by domain "order" with output_domain "shipping"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its output_domain
    And lint exits with a non-zero status

  @C-0582
  Scenario: A saga declaring no destination domain is a lint error
    Given aggregates owning domains "order" and "inventory"
    And a SAGA component "Fulfillment" triggered by domain "order" with no output_domain
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its missing output_domain
    And lint exits with a non-zero status

  @C-0606
  Scenario Outline: Marking a non-trigger (event) entry as starting is a lint error
    # Only a process manager's trigger entry may set starts (ruling B1,
    # decision 14.31).
    Given an aggregate "OrderState" owning domain "order"
    And <entry> that sets starts
    When the protos are linted
    Then lint reports an error naming the (event) entry and starts
    And lint exits with a non-zero status

    Examples:
      | entry                                                                      |
      | an (event) entry for "order.OrderPlaced" naming aggregate "OrderState"     |
      | an (event) entry for "order.OrderPlaced" naming a SAGA from "order"        |
      | an (event) entry for "order.OrderPlaced" naming a PROJECTOR from "order"   |
      | a process manager's own applier (event) entry, with applies set            |

  @C-0607
  Scenario: A process manager's starting triggers are advertised in its descriptor
    Given a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment"
    And its (event) entry for "order.OrderPlaced" from domain "order" sets starts
    And its (event) entry for "inventory.StockReserved" from domain "inventory" does not
    When the component's descriptor is generated
    Then its input for domain "order" lists starting type "/order.OrderPlaced"
    And its input for domain "inventory" lists no starting type
