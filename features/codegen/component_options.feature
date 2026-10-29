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
  Scenario Outline: A policy targeting a domain no aggregate owns is a lint warning
    # A process manager declares no output domain (decision 14.31; C-0605).
    Given an aggregate "OrderState" owning domain "order"
    And a <kind> component "Fulfillment" triggered by domain "order" with output_domain "inventory"
    When the protos are linted
    Then lint reports warning ANZ101 naming "Fulfillment" and output domain "inventory"
    And lint exits with status 0

    Examples:
      | kind            |
      | POLICY            |

  @C-0516
  Scenario Outline: A policy triggering on a domain no aggregate produces is a lint warning
    # The process manager's case, which declares no output domain, is C-0604.
    Given an aggregate "InventoryState" owning domain "inventory"
    And a <kind> component "Fulfillment" triggered by domain "order" with output_domain "inventory"
    When the protos are linted
    Then lint reports warning ANZ102 naming "Fulfillment" and source domain "order"
    And lint exits with status 0

    Examples:
      | kind            |
      | POLICY            |

  @C-0604
  Scenario: A process manager subscribing to another domain's events is a lint error
    # A process manager has no triggers; other domains' events reach it as
    # facts through policies (decision 14.31).
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
      | POLICY            |
      | PROJECTOR       |

  # C-0581 (a policy declaring several destinations through output_domains)
  # is retired: ComponentOptions.output_domains is deleted (decision
  # 14.31), so no declaration can name several destinations.

  @C-0605
  Scenario: A process manager declaring an output domain is a lint error
    # A process manager sends no commands; its decisions reach other
    # domains through policies from its domain (decision 14.31).
    Given aggregates owning domains "order" and "shipping"
    And a PROCESS_MANAGER component "Fulfillment" owning domain "fulfillment" with output_domain "shipping"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its output_domain
    And lint exits with a non-zero status

  @C-0582
  Scenario: A policy declaring no destination domain is a lint error
    Given aggregates owning domains "order" and "inventory"
    And a POLICY component "Fulfillment" triggered by domain "order" with no output_domain
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
  Scenario Outline: The generator gives each refusal mode its handler
    # Decision 14.31: pass-through generates the policy's CommandRefused
    # builder and, in the source domain, the dispatch to the
    # on_refused_<Command> handlers it defines; translate requires the
    # policy's callback.
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And a POLICY component "OrderToInventory" triggered by domain "order" with output_domain "inventory"
    When the handler interfaces are generated with ReserveStock in <mode> mode for "OrderToInventory"
    Then <generated>

    Examples:
      | mode         | generated                                                                                                                   |
      | pass-through | "OrderToInventory" answers a refusal with a generated CommandRefused, and "OrderState" may define on_refused_ReserveStock   |
      | translate    | "OrderToInventory" must implement on_refused_ReserveStock taking a Refusal and returning a fact of "order"                 |

  # C-0620 (exactly one refusal path per sent command) is retired: nothing
  # declares what a policy sends (decision 14.31), so coverage is checked at
  # run time (policy_refusal.feature, C-0618).

  @C-0623
  Scenario Outline: The CLI's refusal switch selects the mode at generation time, and nothing else does
    # "cli may have to have that switch, as it's compile time" (the owner,
    # 2026-10-28). No proto option carries the mode; pass-through is the
    # CLI's default.
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And a POLICY component "OrderToInventory" triggered by domain "order" with output_domain "inventory" <callback>
    When the handler interfaces are generated with the refusal switch <switch>
    Then <outcome>

    Examples:
      | callback                                         | switch                                                     | outcome                                                                         |
      | and no on_refused_ReserveStock callback          | unset                                                      | ReserveStock's refusals pass through as CommandRefused                          |
      | with an on_refused_ReserveStock callback         | translate for command "inventory.ReserveStock" of the policy | ReserveStock's refusals are translated by the callback                          |
      | and no on_refused_ReserveStock callback          | translate for policy "OrderToInventory"                      | generation fails naming "inventory.ReserveStock": translate needs its callback |

  @C-0625
  Scenario: A command's refuses annotation shapes its generated handler
    # The parallel of emits (decision 14.31, the owner's ruling).
    Given an aggregate "WalletState" owning domain "wallet" with command "wallet.HoldFunds"
    And a command "wallet.HoldFunds" for "WalletState" whose (command).refuses lists "wallet.InsufficientFunds"
    When the handler interfaces are generated
    Then the HoldFunds handler returns either its events or an InsufficientFunds refusal
    And the client library packs the InsufficientFunds returned into the rejection as an Any

  @C-0626
  Scenario: A refuses type from another domain fails generation
    Given an aggregate "WalletState" owning domain "wallet" with command "wallet.HoldFunds"
    And an aggregate "TableState" owning domain "table" with message "table.SeatNotConfirmable"
    And a command "wallet.HoldFunds" for "WalletState" whose (command).refuses lists "table.SeatNotConfirmable"
    When the protos are linted
    Then lint reports an error naming "wallet.HoldFunds" and its refuses type "table.SeatNotConfirmable"
    And lint exits with a non-zero status

  @C-0627
  Scenario: A refuses type that does not resolve fails generation
    Given an aggregate "WalletState" owning domain "wallet" with command "wallet.HoldFunds"
    And a command "wallet.HoldFunds" for "WalletState" whose (command).refuses lists "wallet.NoSuchRefusal"
    When the protos are linted
    Then lint reports an error naming "wallet.HoldFunds" and the unresolved refuses type "wallet.NoSuchRefusal"
    And lint exits with a non-zero status

  @C-0648
  Scenario Outline: The (command) annotation's fact field picks the handler the scaffold writes
    # Decision 14.34, the owner's ruling: a command is refusable, a fact is not.
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.<input>"
    And the input "buy-in.<input>" for "BuyInState" has (command).fact <fact>
    When angzarr-cli scaffolds the component
    Then its handler for "buy-in.<input>" is marked <markup>
    And that handler <may> refuse

    Examples:
      | input                   | fact  | markup            | may     |
      | RecordFundsHeld         | false | #[handles_cmd]    | may     |
      | SeatConfirmationRefused | true  | #[handles_fact]   | may not |

  @C-0649
  Scenario: A refuses annotation on a fact fails generation
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.SeatConfirmationRefused"
    And the input "buy-in.SeatConfirmationRefused" for "BuyInState" has (command).fact true
    And its (command).refuses lists "buy-in.SomeRefusal"
    When the protos are linted
    Then lint reports an error naming "buy-in.SeatConfirmationRefused": a fact cannot be refused
    And lint exits with a non-zero status

  @C-0650
  Scenario Outline: Markup that contradicts the proto's command or fact fails generation
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.<input>"
    And the input "buy-in.<input>" for "BuyInState" has (command).fact <fact>
    And the component's handler for it is marked <markup>
    When the generator checks the markup against the protos
    Then it reports an error naming "buy-in.<input>"

    Examples:
      | input                   | fact  | markup          |
      | RecordFundsHeld         | false | #[handles_fact] |
      | SeatConfirmationRefused | true  | #[handles_cmd]  |

  @C-0651
  Scenario Outline: A process manager may start from a command or from a fact
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.<input>"
    And the input "buy-in.<input>" for "BuyInState" has (command).fact <fact> and (command).starts true
    When the protos are linted
    Then lint reports no error for "buy-in.<input>"
    And the PM's descriptor lists "buy-in.<input>" among its starting types

    Examples:
      | input       | fact  |
      | StartBuyIn  | false |
      | BuyInLapsed | true  |

  # C-0664 (a policy names a process manager's root only by implementing a
  # root callback) is retired: there is no root callback; a policy always
  # names its command's root (decision 14.36, as amended).
