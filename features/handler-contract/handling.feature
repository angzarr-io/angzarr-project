Feature: Handling a delivered command - versions, unknown types and conflict reports
  What the client library's router does around business code when the
  coordinator delivers a command or a fact: it reports the business
  binary's version, picks the handler, folds the state it is given, and
  reports a stale command's conflicts for the coordinator to judge. It never
  upcasts: the coordinator has already brought every payload and event up
  to date through the component's upcaster sidecar (decision 14.39;
  coordinator-contract/upcasting.feature), and has dropped the pages the
  delivered snapshot covers (decision 14.40). It never admits, never
  guards an envelope, never checks a descriptor and never judges a
  conflict: those are the coordinator's (decision 14.42). With this tier's
  other features it is the router's complete contract, run against every
  router (the Rust one and the Python one).

  The business binary's version is fixed when it is built. The library
  gives it when the coordinator asks the process to describe its
  component, and with every answer, and never judges a
  snapshot by it: the coordinator delivers only snapshots it has already
  judged compatible.

  The order aggregate keeps a quantity per item (one conflict unit per
  item), a shipping address (its own conflict unit) and free-form notes
  (unmarked, so they conflict with everything). AddItem(item) records
  ItemAdded(item), and the fact ItemDelivered(item) is recorded as
  received. Nothing handles RemoveEverything.

  Background:
    Given an "order" business binary built as version "1.4.2+build.7"

  # ===========================================================================
  # Reporting the version
  # ===========================================================================

  @rules_version
  @C-0533
  Scenario: Every answer reports the build version
    When AddItem "apple" is handled over no prior events
    Then the answer reports rules version "1.4.2+build.7"

  @rules_version
  @C-0534
  Scenario: A process manager's answer reports its build version
    Given a "Fulfillment" process manager built as version "2.0.1"
    When the process manager handles a StartFulfillment command
    Then the answer reports rules version "2.0.1"

  @rules_version
  @C-0536
  Scenario: A delivered snapshot is used whatever version recorded it
    Given a delivered snapshot of the order state recorded under rules version "0.9.0"
    When AddItem "apple" is handled over that snapshot
    Then business code decides on the snapshot's state
    And the command is accepted

  @describe
  @C-0580
  Scenario Outline: A business process refuses to register a second component of any kind
    # One business process is one component (decision 14.19).
    Given the "order" business binary has its "order" aggregate registered
    When a <kind> component "<name>" is registered in the same business process
    Then the registration is refused with reason ROUTER_REASON_DUPLICATE_COMPONENT, naming the "order" aggregate already registered
    And the business process describes only the "order" aggregate

    Examples:
      | kind            | name             |
      | aggregate       | payment          |
      | policy            | OrderFulfillment |
      | process manager | Fulfillment      |
      | projector       | OrderSummary     |

  @snapshot_source
  @C-0570
  Scenario Outline: Every answer carries the state after the delivery, whether or not business code asks
    Given business code that never mentions snapshots
    When <delivery> is handled over ItemAdded "pear"
    Then the answer carries the order state with <items> as its snapshot state

    Examples:
      | delivery                                            | items                              |
      | AddItem "apple"                                     | items "pear" and "apple"           |
      | a command that business code answers with no events | item "pear"                        |
      | a fact ItemDelivered "apple"                        | item "pear" and "apple" delivered  |

  @snapshot_source
  @C-0571
  Scenario Outline: A process manager's answer always carries its process state
    Given a "Fulfillment" process manager built as version "2.0.1"
    When the process manager handles a StartFulfillment command <writing>
    Then the answer's snapshot state is the process manager's state after the command
    And none of the answer's event pages carry a state

    Examples:
      | writing                                   |
      | and writes a FulfillmentStarted event     |
      | without writing a process event           |

  # ===========================================================================
  # Unknown types
  # ===========================================================================

  @unknown_type
  @C-0682
  Scenario: A type no handler claims is refused naming the type it was given
    When RemoveEverything "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ROUTER_REASON_UNKNOWN_COMMAND_TYPE, which is also its status message
    And the refusal's error info carries type_url "/orders.v1.RemoveEverything"
    And the refusal's error info carries no upcast_type_url
    And business code is not invoked

  # ===========================================================================
  # The conflict nonce: STRICT and AGGREGATE_HANDLES
  # ===========================================================================

  @conflict_nonce
  @C-0541
  Scenario: Under STRICT business code sees no window and no nonce
    When AddItem "apple" is handled STRICT at expected sequence 2 over ItemAdded "pear" and ItemAdded "plum"
    Then business code saw expected sequence 2 under STRICT
    And business code saw no conflict window and no nonce

  # The coordinator judges the report (decision 14.42;
  # coordinator-contract/conflict_resolution.feature, C-0683). The router
  # answers business code's events whatever it reports.

  @conflict_nonce
  @C-0542
  Scenario: Under AGGREGATE_HANDLES the answer reports the nonce business code settled with
    Given business code settles conflicts with the nonce it was given
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 1 over ItemAdded "pear", ItemAdded "plum" and ItemAdded "fig" with nonce "n-1"
    Then business code saw the window at sequences 1 and 2
    And the answer reports resolved nonce "n-1"
    And the answer carries business code's events

  @conflict_nonce
  @C-0543
  Scenario: Under AGGREGATE_HANDLES business code that ignores the window is reported as settling nothing
    Given business code does not settle conflicts
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 0 over ItemAdded "pear" with nonce "n-1"
    Then the answer reports no resolved nonce
    And the answer carries business code's events

  @conflict_nonce
  @C-0544
  Scenario: Under AGGREGATE_HANDLES a made-up nonce is reported as it was passed
    Given business code settles conflicts with nonce "made-up"
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 0 over ItemAdded "pear" with nonce "n-1"
    Then the answer reports resolved nonce "made-up"

  @conflict_nonce
  @C-0545
  Scenario: Under AGGREGATE_HANDLES an empty window is reported like any other
    Given business code does not settle conflicts
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 1 over ItemAdded "pear" with nonce "n-1"
    Then the answer reports no resolved nonce

  # ===========================================================================
  # COMMUTATIVE: the router reports the conflict units, the coordinator
  # judges them (decision 14.42; coordinator-contract C-0684)
  # ===========================================================================

  @commutative
  @C-0546
  Scenario: The answer reports the units the window changed and the units the command changed
    When AddItem "apple" is handled COMMUTATIVE at expected sequence 0 over ItemAdded "pear" and ItemAdded "pear" with nonce "n-1"
    Then the answer reports window units "items[pear]" and command units "items[apple]"
    And the answer carries business code's events
    And business code saw no conflict window and no nonce

  @commutative
  @C-0547
  Scenario: A command changing a unit the window changed is reported, not refused
    When AddItem "pear" is handled COMMUTATIVE at expected sequence 1 over ItemAdded "apple" and ItemAdded "pear" with nonce "n-1"
    Then the answer reports window units "items[pear]" and command units "items[pear]"
    And the answer carries business code's events

  @commutative
  @C-0548
  Scenario: Only events from the expected sequence on count as the window
    When AddItem "pear" is handled COMMUTATIVE at expected sequence 1 over ItemAdded "pear" and ItemAdded "apple" with nonce "n-1"
    Then the answer reports window units "items[apple]" and command units "items[pear]"

  @commutative
  @C-0549
  Scenario: Business code decides on the current state, window included
    When AddItem "apple" is handled COMMUTATIVE at expected sequence 0 over ItemAdded "pear" and ItemAdded "plum" with nonce "n-1"
    Then business code saw items "pear" and "plum" in its state

  @commutative
  @C-0550
  Scenario: A change to an unmarked field is reported as the wildcard unit
    When AddItem "apple" is handled COMMUTATIVE at expected sequence 0 over OrderNoteAdded "fragile" with nonce "n-1"
    Then the answer reports window units "*notes" and command units "items[apple]"

  # ===========================================================================
  # Errors are a key and an argument map, never English (decision 14.37)
  # ===========================================================================

  @error_keys
  @C-0667
  Scenario: An untyped business rejection crosses as its code and args, never its text
    Given business code rejects AddItem with code ORDER_CLOSED and arg order_state "closed", and logs "this order is closed" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused FAILED_PRECONDITION with reason ORDER_CLOSED, which is also its status message
    And the refusal's error info carries order_state "closed"
    And no part of the answer carries the text "this order is closed"

  @error_keys
  @C-0668
  Scenario: A typed refusal is its refusal object: its type is the key, its fields the map
    Given business code refuses AddItem with the refusal object ItemOutOfStock with item "apple" and on_hand 0
    When AddItem "apple" is handled over no prior events
    Then the command is refused FAILED_PRECONDITION with reason ROUTER_REASON_COMMAND_REFUSED, which is also its status message
    And the refusal's error info carries refusal_type "orders.v1.ItemOutOfStock"
    And the refusal's status details carry the ItemOutOfStock with item "apple" and on_hand 0

  @error_keys
  @C-0669
  Scenario Outline: A handler bug is answered with a code, never the text of what escaped
    # Decision 14.42: in a language with only exceptions (Python), the
    # client library exports a named unclassified exception
    # (angzarr_client.UnclassifiedError); raising it is
    # "an unclassified error" below, and any other exception is "panics".
    Given business code for AddItem <fails>
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ROUTER_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries <cause>
    And no part of the answer carries the text "<text>"

    Examples:
      | fails                                                             | cause                                  | text                |
      | fails with an unclassified error whose text is "connection reset" | no cause                               | connection reset    |
      | panics with "index out of bounds"                                 | cause "ROUTER_REASON_HANDLER_PANICKED" | index out of bounds |

  @error_keys
  @C-0672
  Scenario: A handler bug with its own code crosses as that code and its args, nested under ROUTER_REASON_UNHANDLED_HANDLER_ERROR
    Given business code for AddItem fails with code LEDGER_OFFLINE and arg ledger "main", and logs "the ledger is offline" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ROUTER_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries cause "LEDGER_OFFLINE" and cause.ledger "main"
    And no part of the answer carries the text "the ledger is offline"

  @error_keys
  @C-0678
  Scenario Outline: A handler bug it marks retryable crosses as the status it picks, its code nested under ROUTER_REASON_UNHANDLED_HANDLER_ERROR
    # Decision 14.37 (owner's rulings, 2026-10-29, latest): the handler
    # picks the retryable status, and they are not interchangeable:
    # UNAVAILABLE resend, DEADLINE_EXCEEDED resend only if idempotent,
    # RESOURCE_EXHAUSTED wait longer.
    Given business code for AddItem fails with a retryable bug under <status>, code LEDGER_OFFLINE and arg ledger "main", and logs "the ledger is offline" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused <status> with reason ROUTER_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries cause "LEDGER_OFFLINE" and cause.ledger "main"
    And no part of the answer carries the text "the ledger is offline"

    Examples:
      | status             |
      | UNAVAILABLE        |
      | DEADLINE_EXCEEDED  |
      | RESOURCE_EXHAUSTED |

  @error_keys
  @C-0679
  Scenario: A handler's immediate-return business error crosses as ABORTED under its own code
    # Decision 14.37 (owner's rulings, 2026-10-29, latest): re-read and
    # re-decide. Returned at once to the caller; never a policy's OnRefused.
    Given business code rejects AddItem for immediate return with code PRICE_MOVED and arg item "apple", and logs "the price moved" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused ABORTED with reason PRICE_MOVED, which is also its status message
    And the refusal's error info carries item "apple"
    And no part of the answer carries the text "the price moved"

  @error_keys
  @C-0670
  Scenario Outline: Every distinct condition has its own reason key
    # The conditions angzarr-router's error.rs told apart only by English text
    # (decision 14.37's inventory); each now has a key of its own, and its
    # details travel in the ErrorInfo metadata.
    When <condition>
    Then it is refused <status> with reason <reason>, which is also its status message
    And the refusal's error info carries <metadata>

    Examples:
      | condition                                                                         | status        | reason                                        | metadata                                         |
      | the state fold fails on a persisted event at sequence 3                           | INTERNAL      | ROUTER_REASON_FOLD_FAILED                     | sequence "3" and state_type_url                  |
      | the state fold fails on an event the command emitted at sequence 4                | INTERNAL      | ROUTER_REASON_FOLD_FAILED_EMITTED             | sequence "4" and state_type_url                  |
      | a command of type "/orders.v1.Unknown" arrives                                    | INTERNAL      | ROUTER_REASON_UNKNOWN_COMMAND_TYPE            | type_url "/orders.v1.Unknown"                    |
      | a fact of type "/orders.v1.Unheard" arrives                                       | INTERNAL      | ROUTER_REASON_NO_FACT_HANDLER                 | type_url "/orders.v1.Unheard"                    |
      | a CommandRefused for RemoveEverything arrives with no on_refused_RemoveEverything | INTERNAL      | ROUTER_REASON_NO_REFUSAL_HANDLER              | command_type "/orders.v1.RemoveEverything"       |
      | a policy is dispatched to the business process hosting the "order" aggregate      | UNIMPLEMENTED | ROUTER_REASON_NO_COMPONENT_OF_KIND            | no other metadata                                |
      | the router is built with two components                                           | INTERNAL      | ROUTER_REASON_DUPLICATE_COMPONENT             | component "order" and component_kind "AGGREGATE" |
      | a CommandRefused fact arrives whose payload does not decode                       | INTERNAL      | ROUTER_REASON_ANY_DECODE_FAILED               | message_type "io.angzarr.v1.CommandRefused"      |
      | a COMMUTATIVE command reaches a state with no resolver                            | INTERNAL      | ROUTER_REASON_CONFLICT_RESOLUTION_UNSUPPORTED | no other metadata                                |

  # ===========================================================================
  # Folding what it is given (decision 14.40)
  # ===========================================================================

  @folding
  @C-0688
  Scenario: Every delivered page is folded onto the starting state, whatever the snapshot's sequence
    # The coordinator drops the pages a snapshot covers; the router has no
    # covered-page guard of its own (owner, 2026-10-29).
    Given a delivered snapshot at sequence 5 of the order state with item "pear"
    And the delivery's pages are ItemAdded "plum" at sequence 5 and ItemAdded "fig" at sequence 6
    When AddItem "apple" is handled over that delivery
    Then business code saw items "pear", "plum" and "fig" in its state

  # ===========================================================================
  # Policies: the router translates, the coordinator checks (decision 14.42)
  # ===========================================================================

  @policy
  @C-0689
  Scenario: A policy's commands come back grouped by the page that triggered them
    Given an "OrderFulfillment" policy translating "order" events into "inventory" commands
    And its business code answers each OrderPlaced event with one ReserveStock command
    When a book holding OrderPlaced at sequence 3, an OrderNoteAdded at sequence 4 and OrderPlaced at sequence 5 is handled
    Then the answer holds two reactions, in page order:
      | trigger sequence | commands          |
      | 3                | one ReserveStock  |
      | 5                | one ReserveStock  |
    And no reaction names sequence 4

  @policy
  @C-0690
  Scenario: A policy's commands are answered as business code returned them, checked and stamped by nothing
    Given an "OrderFulfillment" policy translating "order" events into "inventory" commands
    And its business code answers an OrderPlaced event with a ShipOrder command for "shipping" that names no root, no edition and another correlation
    When the OrderPlaced event is handled
    Then the answer's one reaction carries that ShipOrder command unchanged
    And the answer is not refused

  @policy @policy_refusal
  @C-0691
  Scenario: A policy with a translating callback answers the refusal with the domestic fact's payload alone
    Given an "OrderFulfillment" policy whose ReserveStock refusals are translated by a callback returning the "order" fact StockUnavailable
    When the policy is given the refusal of a ReserveStock it sent
    Then the callback is called with that refusal
    And the answer's fact page carries StockUnavailable as its only content
    And the answer's fact sets no cover, no handling and no identity

  @policy @policy_refusal
  @C-0692
  Scenario: A policy with no translating callback answers that it has no translation
    Given an "OrderFulfillment" policy with no callback for ReserveStock refusals
    When the policy is given the refusal of a ReserveStock it sent
    Then the answer carries no fact
    And business code is not invoked

  # ===========================================================================
  # When the input was accepted (decision 14.37)
  # ===========================================================================

  @recorded_at
  @C-0671
  Scenario Outline: Business code reads when its input was accepted
    Given the delivery says its input was accepted at "2026-10-28T12:00:00Z"
    When <input> is handled over no prior events
    Then business code read "2026-10-28T12:00:00Z" as when its input was accepted
    And business code read no clock of its own for it

    Examples:
      | input                         |
      | AddItem "apple"               |
      | a fact ItemDelivered "apple"  |
