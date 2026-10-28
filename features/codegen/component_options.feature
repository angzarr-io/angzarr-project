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
  Scenario Outline: The generator gives each refusal path its handler
    # Decision 14.31: pass-through generates the source domain's
    # on_refused_<Command>(refusal, state); translate generates the saga's
    # on_refused_<Command>(Refusal) returning the domestic fact.
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And a SAGA component "OrderToInventory" from "order" to "inventory" whose sends entry for "inventory.ReserveStock" <refusal_fact>
    And "OrderState" <refusals>
    When the handler interfaces are generated
    Then <generated>

    Examples:
      | refusal_fact                                | refusals                                   | generated                                                                                                         |
      | names no refusal_fact                       | lists "inventory.ReserveStock" in refusals | "OrderState" has a handler on_refused_ReserveStock taking the CommandRefused and its state, returning events      |
      | names refusal_fact "order.StockUnavailable" | lists no refusals                          | "OrderToInventory" has a callback on_refused_ReserveStock taking a Refusal and returning "order.StockUnavailable" |

  @C-0620
  Scenario Outline: Every command a saga sends has exactly one refusal path
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And a SAGA component "OrderToInventory" from "order" to "inventory" whose sends entry for "inventory.ReserveStock" <refusal_fact>
    And "OrderState" <refusals>
    When the protos are linted
    Then lint reports <diagnostic>
    And lint exits with <status>

    Examples:
      | refusal_fact                                | refusals                                   | diagnostic                                                         | status            |
      | names no refusal_fact                       | lists no refusals                          | a warning naming "inventory.ReserveStock": no refusal path         | status 0          |
      | names refusal_fact "order.StockUnavailable" | lists "inventory.ReserveStock" in refusals | an error naming "inventory.ReserveStock": two refusal paths        | a non-zero status |
      | names refusal_fact "inventory.ReserveStock" | lists no refusals                          | an error: the refusal fact is not a fact of the source domain      | a non-zero status |

  @C-0623
  Scenario Outline: The CLI's refusal switch selects the mode at generation time
    # "cli may have to have that switch, as it's compile time" (the owner,
    # 2026-10-28). The proto's refusal_fact is the default; the switch
    # overrides it, per saga or per saga command.
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable" that lists "inventory.ReserveStock" in refusals
    And a SAGA component "OrderToInventory" from "order" to "inventory" whose sends entry for "inventory.ReserveStock" <refusal_fact>
    When the handler interfaces are generated with the refusal switch <switch>
    Then <outcome>

    Examples:
      | refusal_fact                                | switch                                                         | outcome                                                                                       |
      | names refusal_fact "order.StockUnavailable" | unset                                                          | the saga's callback on_refused_ReserveStock is generated (translate)                          |
      | names refusal_fact "order.StockUnavailable" | pass-through for saga "OrderToInventory"                       | the saga forwards CommandRefused and "OrderState"'s on_refused_ReserveStock is used           |
      | names no refusal_fact                       | translate for command "inventory.ReserveStock" of the saga     | generation fails naming "inventory.ReserveStock": translate needs a refusal_fact              |
