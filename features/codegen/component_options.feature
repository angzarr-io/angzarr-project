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
  Scenario: A process manager subscribing to another domain's events is a lint error
    # A process manager has no triggers; other domains' events reach it as
    # facts through sagas (decision 14.31).
    Given an aggregate "OrderState" owning domain "order"
    And a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment"
    And an (event) entry for "order.OrderPlaced" naming "Fulfillment" with domain "order"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and the (event) entry's domain
    And lint exits with a non-zero status

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
    And a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment" with output_domain "shipping"
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
  Scenario: Marking an aggregate's (command) entry as starting is a lint error
    # Only a process manager's fact entry may set starts (ruling B1 as
    # adapted to facts, decision 14.31).
    Given an aggregate "OrderState" owning domain "order"
    And a (command) entry for "order.PlaceOrder" naming "OrderState" that sets starts
    When the protos are linted
    Then lint reports an error naming "order.PlaceOrder" and starts
    And lint exits with a non-zero status

  @C-0607
  Scenario: A process manager's starting inputs are advertised in its descriptor
    Given a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment"
    And its (command) entry for "fulfillment.StartFulfillment" sets starts
    And its (command) entry for "fulfillment.RecordStockReserved" does not
    When the component's descriptor is generated
    Then the descriptor lists starting type "/fulfillment.StartFulfillment"
    And the descriptor lists no input domains

  @C-0611
  Scenario: A process manager with no starting input is a lint warning
    # It could never start an instance.
    Given a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment"
    And no (command) entry naming "Fulfillment" sets starts
    When the protos are linted
    Then lint reports a warning naming "Fulfillment" and its missing starting input
    And lint exits with status 0

  @C-0612
  Scenario: An (on_refused) option generates the saga's callback and lists the command in its descriptor
    # Decision 14.31: a saga's on-refused callback takes one Refusal
    # { event, command, response } and returns the fact the option sits on.
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And a SAGA component "OrderToInventory" triggered by domain "order" with output_domain "inventory"
    And "order.StockUnavailable" carries (on_refused) naming saga "OrderToInventory" and command "inventory.ReserveStock"
    When the saga's handler interface is generated
    Then the saga has a handler on_refused_ReserveStock taking a Refusal and returning "order.StockUnavailable"
    And the saga's descriptor lists refusal type "/inventory.ReserveStock"

  @C-0620
  Scenario Outline: A mismatched (on_refused) option is a lint error
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And an aggregate "ShippingState" owning domain "shipping" with fact "shipping.Lost"
    And a SAGA component "OrderToInventory" triggered by domain "order" with output_domain "inventory"
    And <message> carries (on_refused) naming <saga> and command <command>
    When the protos are linted
    Then lint reports an error naming the (on_refused) option
    And lint exits with a non-zero status

    Examples:
      | message                  | saga                      | command                   |
      | "shipping.Lost"          | saga "OrderToInventory"   | "inventory.ReserveStock"  |
      | "order.StockUnavailable" | aggregate "InventoryState" | "inventory.ReserveStock" |
      | "order.StockUnavailable" | saga "OrderToInventory"   | "order.PlaceOrder"        |
