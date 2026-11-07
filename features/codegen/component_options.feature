Feature: Component declarations - lint warnings and errors
  angzarr-cli reads the component options from compiled descriptors, lints
  the declarations across the whole proto tree, and generates per-component
  handler interfaces and dispatch tables (docs/design/component-options.md).
  A component is declared on its anchor message by
  (io.angzarr.v1.component): its one required component_name and a kind
  oneof, aggregate { domain }, process_manager { domain, starting_types },
  policy { output_domain } or projector {} (decisions 14.78, 14.87). A
  policy's and a projector's sources are never declared: they are derived
  from the events their (event) entries name (decision 14.78). A command
  carries (command), a fact its own option (fact), never both (decision
  14.91). These scenarios pin what `angzarr lint` reports: cross-component
  warnings for declarations that compile but are unlikely to work (a
  warning leaves the exit status unaffected), and errors for declarations
  the contract forbids, which are the generator's own failures (an error
  fails the run; component-options.md §13).

  @C-0514
  Scenario: A command emitting an event its aggregate has no applier for is a lint warning
    Given an aggregate "OrderState" owning domain "order"
    And a command "order.ShipOrder" for "OrderState" whose (command).emits lists "order.OrderShipped"
    And no (event) entry for "order.OrderShipped" names "OrderState"
    When the protos are linted
    Then lint reports warning ANZ100 naming command "order.ShipOrder" and event "order.OrderShipped"
    And lint exits with status 0

  @C-0515
  Scenario: A policy targeting a domain no aggregate owns is a lint warning
    # A process manager declares no output domain: its decisions leave
    # through policies from its domain (decision 14.31).
    Given an aggregate "OrderState" owning domain "order"
    And a policy "Fulfillment" with output_domain "inventory" whose (event) entries name "order.OrderPlaced"
    When the protos are linted
    Then lint reports warning ANZ101 naming "Fulfillment" and output domain "inventory"
    And lint exits with status 0

  @C-0516
  Scenario: A policy whose derived source no aggregate produces is a lint warning
    # Its source is derived from the events it names (decision 14.78); an
    # event whose owner is outside the descriptor set names its domain by
    # the (event) entry's override.
    Given an aggregate "InventoryState" owning domain "inventory"
    And a policy "Fulfillment" with output_domain "inventory"
    And an (event) entry for "order.OrderPlaced" naming "Fulfillment" with the domain override "order"
    And no component in the descriptor set folds "order.OrderPlaced"
    When the protos are linted
    Then lint reports warning ANZ102 naming "Fulfillment" and source domain "order"
    And lint exits with status 0

  @C-0604
  Scenario: A process manager folding another domain's event fails generation
    # A process manager has no triggers; other domains' events reach it as
    # commands and facts through policies (decision 14.31). An event folded
    # by two stateful components fails generation (component-options.md §4).
    Given an aggregate "OrderState" owning domain "order" that folds "order.OrderPlaced"
    And a process manager "Fulfillment" owning domain "fulfillment"
    And an (event) entry for "order.OrderPlaced" naming "Fulfillment"
    When the protos are linted
    Then lint reports an error naming "order.OrderPlaced" and its two stateful consumers "OrderState" and "Fulfillment"
    And lint exits with a non-zero status

  @C-0517
  Scenario Outline: A stateful component declaring no inputs or events is a lint warning
    # A policy or projector naming no event fails generation instead
    # (C-0855; decision 14.78).
    Given <kind> "Idle" owning domain "idle" that no (command), (fact) or (event) entry names
    When the protos are linted
    Then lint reports warning ANZ103 naming "Idle"
    And lint exits with status 0

    Examples:
      | kind              |
      | an aggregate      |
      | a process manager |

  @C-0855
  Scenario Outline: A policy or projector naming no event fails generation
    # Its sources are derived from the events it names (decision 14.78), so
    # one naming none would react to or fold nothing.
    Given <kind> "Idle" that no (event) entry names
    When the protos are linted
    Then lint reports an error naming "Idle": it names no event
    And lint exits with a non-zero status

    Examples:
      | kind                                     |
      | a policy with output_domain "inventory"  |
      | a projector                              |

  @C-0856
  Scenario: A policy whose events come from more than one domain fails generation
    # One source and one destination per policy (component-options.md §5).
    Given an aggregate "OrderState" owning domain "order" that folds "order.OrderPlaced"
    And an aggregate "PaymentState" owning domain "payment" that folds "payment.PaymentCaptured"
    And a policy "Fulfillment" with output_domain "inventory"
    And (event) entries naming "Fulfillment" for "order.OrderPlaced" and "payment.PaymentCaptured"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its source domains "order" and "payment"
    And lint exits with a non-zero status

  @C-0857
  Scenario: A domain override on an event whose owner is in the set fails generation
    # EventConsumer.domain is an override only, for an owner outside the
    # descriptor set (decision 14.78).
    Given an aggregate "OrderState" owning domain "order" that folds "order.OrderPlaced"
    And a policy "Fulfillment" with output_domain "inventory"
    And an (event) entry for "order.OrderPlaced" naming "Fulfillment" with the domain override "order"
    When the protos are linted
    Then lint reports an error naming "order.OrderPlaced" and the override on its entry for "Fulfillment"
    And lint exits with a non-zero status

  @C-0858
  Scenario: A consumer outside the generated set is skipped with a warning naming it
    # A reference, not an error (decision 14.50), but warned by name
    # (decision 14.99): cross-domain references, which generally should not
    # exist, are flagged so they get checked.
    Given an aggregate "OrderState" owning domain "order" that folds "order.OrderPlaced"
    And an (event) entry for "order.OrderPlaced" naming the component "shipping.ShippingPolicy"
    And no message "shipping.ShippingPolicy" is in the descriptor set being generated
    When the protos are generated
    Then generation warns that consumer "shipping.ShippingPolicy" of "order.OrderPlaced" is outside this generation and was skipped
    And no handler is generated for that entry
    And generation exits with status 0

  # C-0581 (a policy declaring several destinations through output_domains)
  # is retired: ComponentOptions.output_domains is deleted (decision
  # 14.31), so no declaration can name several destinations.

  # C-0605 (a process manager declaring an output domain) is retired: the
  # kind is a oneof and ProcessManagerDecl has no output_domain, so the
  # declaration is unrepresentable (decision 14.78).

  @C-0582
  Scenario: A policy declaring no destination domain is a lint error
    Given aggregates owning domains "order" and "inventory"
    And a policy "Fulfillment" with no output_domain whose (event) entries name "order.OrderPlaced"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its missing output_domain
    And lint exits with a non-zero status

  @C-0859
  Scenario Outline: A component name that is empty or ill-formed fails generation
    # component_name is the one required name: lower-case ASCII letters,
    # digits and "-", starting with a letter; no default (decision 14.87).
    Given an aggregate anchored on "order.OrderState" owning domain "order" whose component_name is <name>
    When the protos are linted
    Then lint reports an error naming "order.OrderState" and its component_name
    And lint exits with a non-zero status

    Examples:
      | name       |
      | empty      |
      | "Order"    |
      | "1-order"  |
      | "order_v2" |

  # C-0606 (a starts flag on an aggregate's (command) entry) is retired:
  # CommandOptions.starts is deleted, and a process manager lists its
  # starting inputs in ProcessManagerDecl.starting_types, which nothing an
  # aggregate declares can hold (decision 14.91).

  @C-0607
  Scenario: A process manager's starting types are copied into its descriptor
    Given a process manager "Fulfillment" owning domain "fulfillment"
    And "Fulfillment" declares starting_types "fulfillment.StartFulfillment"
    And "Fulfillment" takes the command "fulfillment.StartFulfillment" and the fact "fulfillment.RecordStockReserved"
    When the component's descriptor is generated
    Then the descriptor's process_manager arm lists starting type "fulfillment.StartFulfillment" only
    And it names domain "fulfillment"

  @C-0611
  Scenario: A process manager listing no starting types is a generator warning
    # It could never start an instance (component-options.md §9).
    Given a process manager "Fulfillment" owning domain "fulfillment"
    And "Fulfillment" declares no starting_types
    When the protos are linted
    Then lint reports a warning naming "Fulfillment" and its empty starting_types
    And lint exits with status 0

  @C-0860
  Scenario: A starting type that is not one of the process manager's own inputs fails generation
    Given a process manager "Fulfillment" owning domain "fulfillment"
    And an aggregate "OrderState" owning domain "order" with command "order.PlaceOrder"
    And "Fulfillment" declares starting_types "order.PlaceOrder"
    When the protos are linted
    Then lint reports an error naming "Fulfillment" and its starting type "order.PlaceOrder"
    And lint exits with a non-zero status

  @C-0612
  Scenario: A generated policy has one required refusal callback over its target's refusals
    # One refusal callback per policy (decision 14.89), required when its
    # target has a command that can refuse (decision 14.99): it takes the
    # refused command and a choice of the target's refusal messages, one arm
    # per refusal its commands name (typed only, decision 14.95), and answers
    # a fact of its source or a Bug; it cannot decline.
    Given an aggregate "InventoryState" owning domain "inventory" with commands "inventory.ReserveStock" and "inventory.ReleaseStock"
    And "inventory.ReserveStock" refuses with "inventory.OutOfStock" and "inventory.SkuUnknown"
    And "inventory.ReleaseStock" refuses with "inventory.SkuUnknown"
    And an aggregate "OrderState" owning domain "order" with fact "order.StockUnavailable"
    And a policy "OrderToInventory" with output_domain "inventory" whose (event) entries name "order.OrderPlaced"
    When the handler interfaces are generated
    Then "OrderToInventory" must implement one refusal callback taking the refused command and the refusal
    And the refusal is a choice of exactly "inventory.OutOfStock" and "inventory.SkuUnknown"
    And the callback answers a fact of "order" or a Bug
    And the callback cannot decline the refusal

  @C-0861
  Scenario: A target command that cannot refuse adds no refusal arm
    # An empty refuses means the command cannot refuse (decision 14.95), so
    # it needs no path (decision 14.99, dropping 14.76's rule).
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And "inventory.ReserveStock" declares no refuses
    And an aggregate "OrderState" owning domain "order" that takes no fact
    And a policy "OrderToInventory" with output_domain "inventory" whose (event) entries name "order.OrderPlaced"
    When the protos are linted
    Then lint reports no error for "OrderToInventory"
    And "OrderToInventory" is generated with no refusal callback

  # C-0620 (exactly one refusal path per sent command) is retired: nothing
  # declares what a policy sends (decision 14.31), so coverage is checked at
  # run time (policy_refusal.feature, C-0618).

  # C-0623 (the CLI's translate switch naming the fact a refusal callback's
  # scaffold returns) is retired: angzarr-cli selects no refusal mode and
  # has no translate switch; there is one path, the one callback (decisions
  # 14.78 and 14.89).

  @C-0625
  Scenario: A command's refuses annotation shapes its generated handler
    # The parallel of emits (decision 14.31, the owner's ruling).
    Given an aggregate "WalletState" owning domain "wallet" with command "wallet.HoldFunds"
    And a command "wallet.HoldFunds" for "WalletState" whose (command).refuses lists "wallet.InsufficientFunds"
    When the handler interfaces are generated
    Then the HoldFunds handler returns either its events or an InsufficientFunds refusal
    And the client library packs the InsufficientFunds returned into the refusal's gRPC status details as an Any

  @C-0745
  Scenario Outline: A refusal message's status option sets the status it is refused with
    # One message per refusal (decision 14.82), its status a MESSAGE option
    # it must declare (decision 14.95: no default); every typed refusal
    # travels under one wire key.
    Given an aggregate "OrderState" owning domain "order" with command "order.AddLine"
    And a command "order.AddLine" for "OrderState" whose (command).refuses lists "order.<refusal>"
    And the message "order.<refusal>" is marked (refusal_status) <marked>
    When the handler interfaces are generated
    And the AddLine handler refuses with "order.<refusal>"
    Then the command is refused <status> with reason ANGZARR_REASON_COMMAND_REFUSED
    And the refusal's error info carries refusal_type "order.<refusal>"
    And the status details carry the "order.<refusal>" object

    Examples:
      | refusal          | marked                             | status              |
      | QuantityNotWhole | REFUSAL_STATUS_INVALID_ARGUMENT    | INVALID_ARGUMENT    |
      | OrderClosed      | REFUSAL_STATUS_FAILED_PRECONDITION | FAILED_PRECONDITION |

  @C-0862
  Scenario Outline: A refusal message that declares no status fails generation
    # Every refusal declares its status (decision 14.95): there is no
    # default.
    Given an aggregate "OrderState" owning domain "order" with command "order.AddLine"
    And a command "order.AddLine" for "OrderState" whose (command).refuses lists "order.OrderClosed"
    And the message "order.OrderClosed" <marked>
    When the protos are linted
    Then lint reports an error naming "order.OrderClosed" and its (refusal_status)
    And lint exits with a non-zero status

    Examples:
      | marked                                       |
      | carries no (refusal_status)                  |
      | is marked (refusal_status) REFUSAL_STATUS_UNSPECIFIED |

  @C-0746
  Scenario: A status option on a message no command refuses with fails generation
    # Decision 14.82: the option marks a refusal message, so it belongs only
    # on a message some command's refuses names.
    Given an aggregate "OrderState" owning domain "order" with command "order.AddLine"
    And a command "order.AddLine" for "OrderState" whose (command).refuses lists "order.OrderClosed"
    And the message "order.LineSummary", which no command's refuses names, is marked (refusal_status) REFUSAL_STATUS_INVALID_ARGUMENT
    When the protos are linted
    Then lint reports an error naming "order.LineSummary" and its (refusal_status)
    And lint exits with a non-zero status

  @C-0863
  Scenario: The framework's ExpectedSequenceMismatch is the one status-marked message no command refuses with
    # The coordinator raises it, and no command lists it in refuses
    # (decision 14.94).
    Given an aggregate "OrderState" owning domain "order" with command "order.AddLine"
    And the descriptor set includes "io.angzarr.v1.ExpectedSequenceMismatch", marked (refusal_status) REFUSAL_STATUS_FAILED_PRECONDITION
    And no command's refuses names "io.angzarr.v1.ExpectedSequenceMismatch"
    When the protos are linted
    Then lint reports no error naming "io.angzarr.v1.ExpectedSequenceMismatch"

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
  Scenario Outline: The message's option, command or fact, shapes the handler's attribute and signature
    # Two attributes, #[handles_cmd] and #[handles_fact] (decision 14.110):
    # the generator writes the one the message's option calls for. A
    # command's handler returns Emit and may refuse; a fact's returns
    # FactEmit and fails only with a Bug (decisions 14.91, 14.95).
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.<input>"
    And the message "buy-in.<input>" carries <option> naming "BuyInState"
    When angzarr-cli scaffolds the component
    Then its handler for "buy-in.<input>" is marked <attribute>
    And its generated signature returns <returns>

    Examples:
      | input                   | option    | attribute       | returns                         |
      | RecordFundsHeld         | (command) | #[handles_cmd]  | Result<Emit<Self>, Refuses<..>> |
      | SeatConfirmationRefused | (fact)    | #[handles_fact] | Result<FactEmit<Self>, Bug>     |

  @C-0864
  Scenario: Converting a message from a command to a fact changes its option, its attribute and its signature
    # Decision 14.110: the generated attribute and return type follow the
    # option; nothing else in the declaration changes.
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.RecordFundsHeld" carrying (command)
    When "buy-in.RecordFundsHeld"'s option is changed to (fact) with the same component and emits
    And the handler interfaces are generated again
    Then its handler is marked #[handles_fact]
    And its generated signature returns Result<FactEmit<Self>, Bug>

  @C-0865
  Scenario: A message carrying both (command) and (fact) fails generation
    # A message is a command or a fact, never both (decision 14.91).
    Given a process manager "BuyInState" owning domain "buy-in"
    And the message "buy-in.SeatConfirmationRefused" carries (command) and (fact) naming "BuyInState"
    When the protos are linted
    Then lint reports an error naming "buy-in.SeatConfirmationRefused" and both its options
    And lint exits with a non-zero status

  # C-0649 (a refuses annotation on a fact) is retired: a fact's option,
  # FactOptions, has no refuses, so the declaration is unrepresentable
  # (decision 14.91).

  # C-0650 (#[handles_cmd] or #[handles_fact] markup contradicting the
  # proto) is retired: the generator writes the attribute from the option,
  # and a hand-written attribute that disagrees with it is C-0877
  # (decision 14.110).

  @C-0876
  Scenario: A fact handler's step cannot return a refusal
    # FactEmit's failure type is Bug, which holds no refusal, no typed
    # refusal and no re-run (decision 14.110): the mistake is a failure to
    # generate or compile, never a runtime answer.
    Given an aggregate "OrderState" owning domain "order" with the fact "order.ItemDelivered"
    And its #[handles_fact] handler has a step returning the refusal object "order.ItemOutOfStock"
    When the handler is generated and compiled
    Then it fails: a fact handler's failure type is Bug, which cannot hold the refusal "order.ItemOutOfStock"

  @C-0877
  Scenario Outline: A message handled under the attribute of the other kind fails generation
    # The kind is the attribute (decision 14.110); the message's option must
    # agree with it.
    Given an aggregate "OrderState" owning domain "order" with the message "order.<message>" carrying <option> naming "OrderState"
    And its handler is marked <attribute>
    When the handler interfaces are generated
    Then generation fails naming "order.<message>", its option <option> and the attribute <attribute>
    And generation exits with a non-zero status

    Examples:
      | message       | option    | attribute       |
      | ItemDelivered | (fact)    | #[handles_cmd]  |
      | AddItem       | (command) | #[handles_fact] |

  @C-0651
  Scenario Outline: A process manager may start from a command or from a fact
    Given a process manager "BuyInState" owning domain "buy-in" with input "buy-in.<input>"
    And the message "buy-in.<input>" carries <option> naming "BuyInState"
    And "BuyInState" declares starting_types "buy-in.<input>"
    When the protos are linted
    Then lint reports no error for "buy-in.<input>"
    And the PM's descriptor lists "buy-in.<input>" among its starting types

    Examples:
      | input       | option    |
      | StartBuyIn  | (command) |
      | BuyInLapsed | (fact)    |

  @C-0794
  Scenario Outline: A policy's generated code sends each output in the arm its destination declares
    # Decision 14.69: business code never picks the arm; the policy's
    # generated code reads the destination's option, (command) or (fact),
    # and fills Output's command or fact arm (decision 14.91), in every
    # language the generator writes (decision 14.73).
    Given an aggregate "WalletState" owning domain "wallet" that folds "wallet.FundsHeld"
    And a process manager "BuyInState" owning domain "buy-in" with input "buy-in.<input>"
    And the message "buy-in.<input>" carries <option> naming "BuyInState"
    And a policy "WalletToBuyIn" with output_domain "buy-in" whose (event) entries name "wallet.FundsHeld"
    When the handler interfaces are generated
    Then the reaction of "WalletToBuyIn" to "wallet.FundsHeld" may return "buy-in.<input>"
    And the generated code of "WalletToBuyIn" sends "buy-in.<input>" in the Output's <arm> arm

    Examples:
      | input                   | option    | arm     |
      | RecordFundsHeld         | (command) | command |
      | SeatConfirmationRefused | (fact)    | fact    |

  # C-0795 (a domain given a refusal handler for each command its policies
  # send) is retired: there is no source-domain dispatch by the refused
  # command's type; the policy's one callback translates a refusal into a
  # fact of its source, which the source handles as any fact (decision 46
  # #5, 14.78).

  @C-0797
  Scenario Outline: A handler returns a list of its component's events
    # Decision 14.75: there is no emits cardinality; a handling returns a
    # list of events, empty, one or many, in every language the generator
    # writes.
    Given an aggregate "OrderState" owning domain "order" with <input> "order.<message>" whose emits lists "order.OrderPlaced"
    When the handler interfaces are generated
    Then the <message> handler returns a list of the component's events
    And it may return an empty list

    Examples:
      | input   | message        |
      | command | PlaceOrder     |
      | fact    | RecordPayment  |

  # C-0798 (a command a policy may send that declares no refuses fails
  # generation) is retired: an empty refuses means the command cannot
  # refuse, so every sent command has a path by construction (decision
  # 14.99, dropping 14.76's rule; C-0861).

  @C-0799
  Scenario: A policy that may send a command that can refuse, to a source taking no fact, fails generation
    # The policy's refusal callback answers a fact of its source, so its
    # source must take one, when its target has a command that can refuse
    # (decisions 14.89, 14.99); with none, it needs none (C-0861).
    Given an aggregate "InventoryState" owning domain "inventory" with command "inventory.ReserveStock"
    And "inventory.ReserveStock" refuses with "inventory.OutOfStock"
    And an aggregate "OrderState" owning domain "order" that folds "order.OrderPlaced" and takes no fact
    And a policy "OrderToInventory" with output_domain "inventory" whose (event) entries name "order.OrderPlaced"
    When the protos are linted
    Then lint reports an error naming "OrderToInventory" and its source domain "order": no fact to translate a refusal into
    And lint exits with a non-zero status

  # C-0664 (a policy names a process manager's root only by implementing a
  # root callback) is retired: there is no root callback; a policy always
  # names its command's root (decision 14.36, as amended).
