Feature: Handling a delivered command - versions, unknown types, outcomes and Emit
  What the client library's router does around business code when the
  coordinator delivers a command or a fact through the one call,
  CommandHandlerService.Handle (decision 14.98): it reports the business
  binary's version, picks the handler, folds the state it is given, and
  answers success only, every other outcome a gRPC error status (decision
  14.95). It never upcasts: the coordinator has already brought every
  payload and event up to date through the component's upcaster sidecar
  (decision 14.39; coordinator-contract/upcasting.feature), and has dropped
  the pages the delivered snapshot covers (decision 14.40). It never
  admits, never guards an envelope, never checks a descriptor and never
  checks an expected sequence: those are the coordinator's (decisions 14.42
  and 14.94). With this tier's other features it is the router's complete
  contract, run against every router (the Rust one and the Python one).

  The request (io.angzarr.handler.v1.HandleRequest) carries the input book
  (its Command or Fact arm), the stream's history, when the input was
  accepted and, for a policy's input, its trigger. The answer
  (HandleResponse) carries the events as payloads, the state after them and
  the rules version, and nothing the coordinator stamps (decision 14.78).

  The business binary's version is fixed when it is built. The library
  gives it when the coordinator asks the process to describe its
  component, and with every answer, and never judges a
  snapshot by it: the coordinator delivers only snapshots it has already
  judged compatible.

  The order aggregate keeps a quantity per item, a shipping address and
  free-form notes (fixture/order.proto). AddItem(item) records
  ItemAdded(item), or is refused with its typed refusal ItemOutOfStock, and
  the fact ItemDelivered(item) is recorded as received. Nothing handles
  RemoveEverything.

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
    Given a "fulfillment" process manager built as version "2.0.1"
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
    # One business process is one component (decision 14.19). One owner,
    # the router, and one arg set, each a component name (decisions 14.87
    # and 14.88).
    Given the "order" business binary has its "order" aggregate registered
    When a <kind> component "<name>" is registered in the same business process
    Then the registration is refused INTERNAL with reason ANGZARR_REASON_DUPLICATE_COMPONENT
    And the refusal's error info carries registered "order" and refused "<name>"
    And the business process describes only the "order" aggregate

    Examples:
      | kind            | name              |
      | aggregate       | payment           |
      | policy          | order-fulfillment |
      | process manager | fulfillment       |
      | projector       | order-summary     |

  @snapshot_source
  @C-0570
  Scenario Outline: Every answer carries the state after the delivery, whether or not business code asks
    Given business code that never mentions snapshots
    When <delivery> is handled over ItemAdded "pear"
    Then the answer carries the order state with <items> as its state

    Examples:
      | delivery                                            | items                             |
      | AddItem "apple"                                     | items "pear" and "apple"          |
      | a command that business code answers with no events | item "pear"                       |
      | a fact ItemDelivered "apple"                        | item "pear" and "apple" delivered |

  @snapshot_source
  @C-0571
  Scenario Outline: A process manager's answer always carries its process state
    # The answer is payloads, the state and the rules version (decision
    # 14.78): its events are payloads alone, so none carries a state.
    Given a "fulfillment" process manager built as version "2.0.1"
    When the process manager handles a StartFulfillment command <writing>
    Then the answer's state is the process manager's state after the command
    And the answer's events are <events>

    Examples:
      | writing                               | events                                       |
      | and writes a FulfillmentStarted event | one FulfillmentStarted payload, nothing else |
      | without writing a process event       | empty                                        |

  # ===========================================================================
  # Unknown types
  # ===========================================================================

  @unknown_type
  @C-0682
  Scenario: A type no handler claims is refused naming the type it was given
    When RemoveEverything "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ANGZARR_REASON_UNKNOWN_COMMAND_TYPE, which is also its status message
    And the refusal's error info carries type_url "/orders.v1.RemoveEverything"
    And the refusal's error info carries no upcast_type_url
    And business code is not invoked

  # ===========================================================================
  # The conflict nonce and the COMMUTATIVE units: retired
  # ===========================================================================

  # C-0541 to C-0550 (STRICT's absent window, the AGGREGATE_HANDLES nonce and
  # the COMMUTATIVE unit sets the router reported) are retired: the
  # coordinator has no conflict concept, so there is no resolution, window,
  # nonce, unit or report to deliver or answer (decision 14.92, the owner's
  # decision 47). A command's expected sequence is the coordinator's check,
  # before Handle is called (decision 14.94;
  # coordinator-contract C-0717): business code decides on the current state.

  # ===========================================================================
  # Outcomes: success is the answer, everything else a gRPC status
  # (decision 14.95, reversing decision 46's Q2; AIP-193, decision 14.37)
  # ===========================================================================

  @outcomes
  @C-0843
  Scenario Outline: Every outcome but success is a gRPC error status, never an answer
    # HandleResponse is success only: events, state and rules version.
    # There is no refusal, abort or result arm to fill in.
    Given business code for AddItem <outcome>
    When AddItem "apple" is handled over no prior events
    Then the call fails with status <status> and reason <reason>
    And no HandleResponse is answered

    Examples:
      | outcome                                                                        | status              | reason                                 |
      | refuses with the refusal object ItemOutOfStock with item "apple" and on_hand 0 | FAILED_PRECONDITION | ANGZARR_REASON_COMMAND_REFUSED         |
      | asks for a re-run with code PRICE_MOVED and arg item "apple"                   | ABORTED             | PRICE_MOVED                            |
      | fails with an unclassified error                                               | INTERNAL            | ANGZARR_REASON_UNHANDLED_HANDLER_ERROR |

  @outcomes
  @C-0844
  Scenario: A successful answer carries only what business code decided
    When AddItem "apple" is handled over no prior events
    Then the answer's events are one ItemAdded "apple" payload
    And the answer carries the order state with item "apple" as its state
    And the answer reports rules version "1.4.2+build.7"
    And the answer carries no cover, no sequence, no command id and no event metadata

  @outcomes
  @C-0845
  Scenario Outline: A fact's handling never refuses: any error it answers is a bug's status
    # Only a command's handling may refuse (decision 14.98); any error
    # status for a fact is a bug (decision 14.72), which the coordinator
    # dead-letters (coordinator-contract fact_flow.feature).
    Given business code for the fact ItemDelivered <fails>
    When a fact ItemDelivered "apple" is handled over no prior events
    Then the call fails with status <status> and reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR
    And the refusal's error info carries <cause>
    And the answer carries no refusal_type and no status details

    Examples:
      | fails                                                                                   | status      | cause                                          |
      | fails with an unclassified error                                                        | INTERNAL    | no cause                                       |
      | fails with code LEDGER_OFFLINE and arg ledger "main"                                    | INTERNAL    | cause "LEDGER_OFFLINE" and cause.ledger "main" |
      | fails with a retryable bug under UNAVAILABLE, code LEDGER_OFFLINE and arg ledger "main" | UNAVAILABLE | cause "LEDGER_OFFLINE" and cause.ledger "main" |

  @outcomes
  @C-0875
  Scenario: A refusal converted with Bug::from_error is demoted to a bug whose cause is the refusal's key
    # The conversion is explicit, with no blanket From (decision 14.110): a
    # refusal passed through it is no longer a refusal.
    Given business code for the fact ItemDelivered fails by passing the refusal object ItemOutOfStock with item "apple" and on_hand 0 through Bug::from_error
    When a fact ItemDelivered "apple" is handled over no prior events
    Then the call fails with status INTERNAL and reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR
    And the refusal's error info carries cause "orders.v1.ItemOutOfStock", the refusal's key
    And the answer carries no refusal_type and no status details

  # ===========================================================================
  # Refusals are typed only (decision 14.95)
  # ===========================================================================

  # C-0667 (an untyped business rejection crossing as its own code and args
  # under a business status) is retired: refusals are typed only, and
  # Refusal has no untyped arm (decision 14.95). A domain's own key now
  # travels only as a re-run (ABORTED, C-0679) or as a bug (C-0672, C-0846).

  @error_keys
  @C-0668
  Scenario: A typed refusal is its refusal object: its type is the key, its fields the map
    Given business code refuses AddItem with the refusal object ItemOutOfStock with item "apple" and on_hand 0
    When AddItem "apple" is handled over no prior events
    Then the command is refused FAILED_PRECONDITION with reason ANGZARR_REASON_COMMAND_REFUSED, which is also its status message
    And the refusal's error info carries refusal_type "orders.v1.ItemOutOfStock"
    And the refusal's status details carry the ItemOutOfStock with item "apple" and on_hand 0

  @error_keys @typed_refusals
  @C-0846
  Scenario: A rejection that is not a typed refusal crosses as a bug, never as a business status
    # A command whose refuses names nothing cannot refuse (decision 14.95):
    # a key business code raises of its own is a handler bug, and no
    # business status is answered without its typed refusal object.
    Given AddItem declares no refuses types
    And business code rejects AddItem with code ORDER_CLOSED and arg order_state "closed", and logs "this order is closed" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries cause "ORDER_CLOSED" and cause.order_state "closed"
    And the refusal's error info carries no refusal_type
    And no part of the answer carries the text "this order is closed"

  @error_keys @typed_refusals
  @C-0847
  Scenario: A refusal travels under the status its message declares
    # Every refusal message declares its (refusal_status), with no default
    # (decision 14.95); the router answers under that status.
    Given business code refuses the counter's IncreaseBy with the refusal object ValueNotPositive with n 0
    When IncreaseBy 0 is handled over no prior events
    Then the command is refused INVALID_ARGUMENT with reason ANGZARR_REASON_COMMAND_REFUSED, which is also its status message
    And the refusal's error info carries refusal_type "test.counter.ValueNotPositive"
    And the refusal's status details carry the ValueNotPositive with n 0

  # ===========================================================================
  # Errors are a key and an argument map, never English (decision 14.37)
  # ===========================================================================

  @error_keys
  @C-0669
  Scenario Outline: A handler bug is answered with a code, never the text of what escaped
    # Decision 14.42: in a language with only exceptions (Python), the
    # client library exports a named unclassified exception
    # (angzarr_client.UnclassifiedError); raising it is
    # "an unclassified error" below, and any other exception is "panics".
    Given business code for AddItem <fails>
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries <cause>
    And no part of the answer carries the text "<text>"

    Examples:
      | fails                                                             | cause                                   | text                |
      | fails with an unclassified error whose text is "connection reset" | no cause                                | connection reset    |
      | panics with "index out of bounds"                                 | cause "ANGZARR_REASON_HANDLER_PANICKED" | index out of bounds |

  @error_keys
  @C-0672
  Scenario: A handler bug with its own code crosses as that code and its args, nested under ANGZARR_REASON_UNHANDLED_HANDLER_ERROR
    Given business code for AddItem fails with code LEDGER_OFFLINE and arg ledger "main", and logs "the ledger is offline" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries cause "LEDGER_OFFLINE" and cause.ledger "main"
    And no part of the answer carries the text "the ledger is offline"

  @error_keys
  @C-0678
  Scenario Outline: A handler bug it marks retryable crosses as the status it picks, its code nested under ANGZARR_REASON_UNHANDLED_HANDLER_ERROR
    # Decision 14.37 (owner's rulings, 2026-10-29, latest): the handler
    # picks the retryable status, and they are not interchangeable:
    # UNAVAILABLE resend, DEADLINE_EXCEEDED resend only if idempotent,
    # RESOURCE_EXHAUSTED wait longer.
    Given business code for AddItem fails with a retryable bug under <status>, code LEDGER_OFFLINE and arg ledger "main", and logs "the ledger is offline" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused <status> with reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR, which is also its status message
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
    # re-decide. Returned at once to the caller; never a policy's Translate.
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
      | condition                                                                                      | status        | reason                              | metadata                                 |
      | the state fold fails on a persisted event at sequence 3                                        | INTERNAL      | ANGZARR_REASON_FOLD_FAILED          | sequence "3" and state_type_url          |
      | the state fold fails on an event the command emitted at sequence 4                             | INTERNAL      | ANGZARR_REASON_FOLD_FAILED_EMITTED  | sequence "4" and state_type_url          |
      | a command of type "/orders.v1.Unknown" arrives                                                 | INTERNAL      | ANGZARR_REASON_UNKNOWN_COMMAND_TYPE | type_url "/orders.v1.Unknown"            |
      | a fact of type "/orders.v1.Unheard" arrives                                                    | INTERNAL      | ANGZARR_REASON_NO_FACT_HANDLER      | type_url "/orders.v1.Unheard"            |
      | a policy written by hand with no refusal callback is given a refusal of a ReserveStock it sent | INTERNAL      | ANGZARR_REASON_NO_REFUSAL_HANDLER   | command_type "/orders.v1.ReserveStock"   |
      | a policy is dispatched to the business process hosting the "order" aggregate                   | UNIMPLEMENTED | ANGZARR_REASON_NO_COMPONENT_OF_KIND | no other metadata                        |
      | the router is built with the "order" aggregate and then a "payment" aggregate                  | INTERNAL      | ANGZARR_REASON_DUPLICATE_COMPONENT  | registered "order" and refused "payment" |
      | a fact ItemDelivered arrives whose payload does not decode                                     | INTERNAL      | ANGZARR_REASON_ANY_DECODE_FAILED    | message_type "orders.v1.ItemDelivered"   |

  # ===========================================================================
  # What a handler returns: Emit, with no step cap (decision 14.104;
  # docs/design/command-handling.md §9)
  # ===========================================================================

  @emit
  @C-0848
  Scenario: A continuation's events are answered after the handler's own, as one list
    Given business code for AddItem returns Emit of ItemAdded "apple", then a step that records OrderNoteAdded "restock apple" when an item's quantity reaches 1 and continues nowhere
    When AddItem "apple" is handled over no prior events
    Then the answer's events are ItemAdded "apple" and OrderNoteAdded "restock apple", in that order
    And the answer carries the order state with both folded in as its state

  @emit
  @C-0849
  Scenario: A step decides on the state with the earlier events folded in
    Given business code for AddItem returns Emit of ItemAdded "apple", then a step
    When AddItem "apple" is handled over ItemAdded "pear"
    Then the step saw items "pear" and "apple" in its state

  @emit
  @C-0850
  Scenario Outline: A refusal or a bug in any step fails the whole decision
    # All of it is one decision: nothing of the earlier steps is answered.
    Given business code for AddItem returns Emit of ItemAdded "apple", then a step that <fails>
    When AddItem "apple" is handled over no prior events
    Then the call fails with status <status> and reason <reason>
    And no events are answered

    Examples:
      | fails                                                                          | status              | reason                                 |
      | refuses with the refusal object ItemOutOfStock with item "apple" and on_hand 0 | FAILED_PRECONDITION | ANGZARR_REASON_COMMAND_REFUSED         |
      | fails with code LEDGER_OFFLINE and arg ledger "main"                           | INTERNAL            | ANGZARR_REASON_UNHANDLED_HANDLER_ERROR |

  @emit
  @C-0851
  Scenario: A fact's handler returns a FactEmit
    # A command handler returns an Emit, a fact handler a FactEmit, which
    # carries events and steps the same way and fails only with a Bug
    # (decisions 14.104 and 14.110).
    Given business code for the fact ItemDelivered returns FactEmit of the fact's own event, then a step that records OrderNoteAdded "delivered apple"
    When a fact ItemDelivered "apple" is handled over no prior events
    Then the answer's events are the fact's own event and OrderNoteAdded "delivered apple", in that order

  @emit
  @C-0852
  Scenario: There is no step cap: a long chain of steps is answered whole
    # The step cap is gone, with its key (decision 14.104: "the step cap is
    # accidental complexity"). A step that always continues never
    # terminates: a handler bug with no framework guard.
    Given business code for AddItem returns Emit of ItemAdded "apple", then 40 steps, each recording one OrderNoteAdded and continuing to the next
    When AddItem "apple" is handled over no prior events
    Then the answer's events are ItemAdded "apple" and 40 OrderNoteAdded events, in order
    And the call is not refused

  @emit
  @C-0853
  Scenario Outline: The library's test helper checks that a step is idempotent on its own result
    # A step run again on the state its own events produce must emit
    # nothing and continue nowhere (decision 14.104).
    Given a step that <behaves>
    When the client library's step-idempotence test helper runs it
    Then the helper <verdict>

    Examples:
      | behaves                                                                        | verdict                                         |
      | records OrderNoteAdded "restock apple" only while no such note is in the state | passes                                          |
      | records OrderNoteAdded "restock apple" whenever it runs                        | fails, naming the events the second run emitted |

  @emit
  @C-0878
  Scenario Outline: The library's test helper checks that a fact's step is idempotent on its own result
    # The same rule for a FactEmit's steps (decisions 14.104 and 14.110).
    Given a fact step that <behaves>
    When the client library's fact step-idempotence test helper runs it
    Then the helper <verdict>

    Examples:
      | behaves                                                                          | verdict                                         |
      | records OrderNoteAdded "delivered apple" only while no such note is in the state | passes                                          |
      | records OrderNoteAdded "delivered apple" whenever it runs                        | fails, naming the events the second run emitted |

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
  Scenario: A policy reacts to the one trigger event it is handed
    # React takes one trigger page and is called once per trigger
    # (decision 46, Q3): its answer is that event's outputs alone, with no
    # trigger sequence to group them by.
    Given an "order-fulfillment" policy translating "order" events into "inventory" inputs
    And its business code answers each OrderPlaced event with one ReserveStock command
    When React is handed a trigger book holding only OrderPlaced at sequence 3
    Then the answer holds one output, a ReserveStock in the command arm
    And no output names a trigger sequence

  @policy
  @C-0690
  Scenario: A policy's outputs are a root and a payload, answered as business code returned them
    # An Output holds the destination root and the payload in its arm, and
    # nothing else (decision 14.78): the coordinator addresses, stamps and
    # checks every one, a missing root included
    # (coordinator-contract policy_addressing.feature).
    Given an "order-fulfillment" policy translating "order" events into "inventory" inputs
    And its business code answers an OrderPlaced event with a ReserveStock command that names no root
    When React is handed a trigger book holding only that OrderPlaced event
    Then the answer's one output carries that ReserveStock in the command arm, with no root
    And the output carries no domain, no edition, no command id and no correlation
    And the answer is not refused

  @policy
  @C-0783
  Scenario: A policy's facts come back beside its commands, in the order business code returned them
    # A policy emits what its destination declares (decision 14.69): the
    # arm is the destination's declaration, picked by generated code
    # (decision 14.91); the router passes either arm through as returned;
    # the coordinator checks and stamps both.
    Given an "order-fulfillment" policy translating "order" events into "inventory" inputs
    And its business code answers an OrderPlaced event with a ReserveStock command and then a StockHoldRequested fact
    When React is handed a trigger book holding only that OrderPlaced event
    Then the answer's outputs are the ReserveStock in the command arm and then the StockHoldRequested in the fact arm, unchanged
    And the answer is not refused

  @policy @policy_refusal
  @C-0691
  Scenario: A policy's refusal callback answers the refusal with the domestic fact's payload alone
    # The one refusal path (decision 46 #5) and the one callback (decision
    # 14.89): Translate is handed the trigger, the command as delivered and
    # the typed refusal with its status; it answers a payload only.
    Given an "order-fulfillment" policy whose refusal callback translates a ReserveStock refused StockShort into the "order" fact StockUnavailable
    When Translate is handed the refusal StockShort with item "apple" and on_hand 0, under FAILED_PRECONDITION, of a ReserveStock it sent
    Then the callback is called with that ReserveStock and that StockShort
    And the answer is the fact StockUnavailable as its only content
    And the answer sets no cover, no handling and no identity

  # C-0692 (a policy with no translating callback answering "no
  # translation") is retired: there is no pass-through and no policy that
  # declines (decision 46 #5); a hand-written policy with no callback is a
  # bug, ANGZARR_REASON_NO_REFUSAL_HANDLER (C-0670), and a generated one
  # always has its one callback (decision 14.89).

  @policy @policy_refusal
  @C-0854
  Scenario: A refusal the callback does not handle is answered as a bug, never a fact
    # The author handles the refusals of the commands it sends, and every
    # other arm answers a Bug (decision 14.89); a policy cannot decline
    # (decision 46 #5).
    Given an "order-fulfillment" policy whose refusal callback answers a Bug for every refusal but StockShort
    When Translate is handed a refusal of another type of a ReserveStock it sent
    Then the call fails with status INTERNAL and reason ANGZARR_REASON_UNHANDLED_HANDLER_ERROR
    And no fact is answered

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
      | input                        |
      | AddItem "apple"              |
      | a fact ItemDelivered "apple" |
