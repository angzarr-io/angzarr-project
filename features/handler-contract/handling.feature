Feature: Handling a delivered command - versions, upcasting and conflicts
  What the client library does around business code when the coordinator
  delivers a command or a fact: it reports the business binary's version,
  brings an old payload type up to date, picks the handler, and settles a
  stale command's conflicts before its events are kept.

  The business binary's version is fixed when it is built. The library
  gives it when the coordinator asks the process to describe its
  component, and with every answer, and never judges a
  snapshot by it: the coordinator delivers only snapshots it has already
  judged compatible.

  The order aggregate keeps a quantity per item (one conflict unit per
  item), a shipping address (its own conflict unit) and free-form notes
  (unmarked, so they conflict with everything). AddItem(item) records
  ItemAdded(item). AddItemV1 is AddItem's old name and upcasts to AddItem;
  the fact ItemDeliveredV1 likewise upcasts to ItemDelivered. AddLine
  upcasts to AddLineItem, which nothing handles, and RemoveEverything is
  neither handled nor upcast.

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
  @C-0535
  Scenario: Describing the process announces the same build version
    When the coordinator asks the "order" business binary to describe its component
    Then the "order" aggregate's description carries rules version "1.4.2+build.7"
    And the "order" aggregate's description carries the order state type

  @rules_version
  @C-0536
  Scenario: A delivered snapshot is used whatever version recorded it
    Given a delivered snapshot of the order state recorded under rules version "0.9.0"
    When AddItem "apple" is handled over that snapshot
    Then business code decides on the snapshot's state
    And the command is accepted

  @describe
  @C-0565
  Scenario: Describing a process gives its one component
    When the coordinator asks the "order" business binary to describe its component
    Then the answer describes one component:
      | name  | kind      | rules version | state type            |
      | order | AGGREGATE | 1.4.2+build.7 | /orders.v1.OrderState |
    And business code is not invoked

  @describe
  @C-0580
  Scenario Outline: A business process refuses to register a second component of any kind
    # One business process is one component (decision 14.19).
    Given the "order" business binary has its "order" aggregate registered
    When a <kind> component "<name>" is registered in the same business process
    Then the registration is refused with reason DUPLICATE_COMPONENT, naming the "order" aggregate already registered
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

  @policy
  @C-0583
  Scenario: A policy's command for a domain other than its one destination is refused before it answers
    Given an "OrderFulfillment" policy translating "order" events into "inventory" commands
    And its business code answers an OrderPlaced event with a ReserveStock command for "inventory" and a ShipOrder command for "shipping"
    When the OrderPlaced event is handled
    Then the policy's answer fails with INTERNAL status
    And the answer carries no commands

  # ===========================================================================
  # Upcasting and unknown types
  # ===========================================================================

  @upcasting
  @C-0537
  Scenario: An old command type is upcast and decided as the current type
    When AddItemV1 "apple" is handled over no prior events
    Then business code decides an AddItem for "apple"
    And the command is accepted

  @upcasting
  @C-0538
  Scenario: An old fact type is upcast and ingested as the current type
    When a fact ItemDeliveredV1 "apple" is handled over no prior events
    Then business code ingests an ItemDelivered for "apple"
    And the fact is accepted

  @upcasting
  @C-0539
  Scenario: A type that upcasts to something no handler claims is refused naming both types
    When AddLine "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason UNKNOWN_COMMAND_TYPE, which is also its status message
    And the refusal's error info carries type_url "/orders.v1.AddLine"
    And the refusal's error info carries upcast_type_url "/orders.v1.AddLineItem"
    And business code is not invoked

  @upcasting
  @C-0540
  Scenario: A type with no handler and no upcaster is refused naming the type as sent
    When RemoveEverything "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason UNKNOWN_COMMAND_TYPE, which is also its status message
    And the refusal's error info carries type_url "/orders.v1.RemoveEverything"
    And the refusal's error info carries upcast_type_url "/orders.v1.RemoveEverything"
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

  @conflict_nonce
  @C-0542
  Scenario: Under AGGREGATE_HANDLES business code that settles the window with the delivered nonce is accepted
    Given business code settles conflicts with the nonce it was given
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 1 over ItemAdded "pear", ItemAdded "plum" and ItemAdded "fig" with nonce "n-1"
    Then business code saw the window at sequences 1 and 2
    And the command is accepted

  @conflict_nonce
  @C-0543
  Scenario: Under AGGREGATE_HANDLES business code that ignores the window fails as stale
    Given business code does not settle conflicts
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 0 over ItemAdded "pear" with nonce "n-1"
    Then the command fails as ABORTED
    And business code's events are discarded

  @conflict_nonce
  @C-0544
  Scenario: Under AGGREGATE_HANDLES a made-up nonce fails as stale
    Given business code settles conflicts with nonce "made-up"
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 0 over ItemAdded "pear" with nonce "n-1"
    Then the command fails as ABORTED
    And business code's events are discarded

  @conflict_nonce
  @C-0545
  Scenario: Under AGGREGATE_HANDLES an empty window still has to be settled
    Given business code does not settle conflicts
    When AddItem "apple" is handled AGGREGATE_HANDLES at expected sequence 1 over ItemAdded "pear" with nonce "n-1"
    Then the command fails as ABORTED

  # ===========================================================================
  # COMMUTATIVE: the library settles the window itself
  # ===========================================================================

  @commutative
  @C-0546
  Scenario: A stale command that changes other conflict units than the window is kept
    When AddItem "apple" is handled COMMUTATIVE at expected sequence 0 over ItemAdded "pear" and ItemAdded "pear" with nonce "n-1"
    Then the command is accepted
    And business code saw no conflict window and no nonce

  @commutative
  @C-0547
  Scenario: A stale command that changes a conflict unit the window changed fails as stale
    When AddItem "pear" is handled COMMUTATIVE at expected sequence 1 over ItemAdded "apple" and ItemAdded "pear" with nonce "n-1"
    Then the command fails as ABORTED
    And business code's events are discarded

  @commutative
  @C-0548
  Scenario: Only events from the expected sequence on count as the window
    When AddItem "pear" is handled COMMUTATIVE at expected sequence 1 over ItemAdded "pear" and ItemAdded "apple" with nonce "n-1"
    Then the command is accepted

  @commutative
  @C-0549
  Scenario: Business code decides on the current state, window included
    When AddItem "apple" is handled COMMUTATIVE at expected sequence 0 over ItemAdded "pear" and ItemAdded "plum" with nonce "n-1"
    Then business code saw items "pear" and "plum" in its state

  @commutative
  @C-0550
  Scenario: A change to an unmarked field conflicts with every change
    When AddItem "apple" is handled COMMUTATIVE at expected sequence 0 over OrderNoteAdded "fragile" with nonce "n-1"
    Then the command fails as ABORTED
    And business code's events are discarded

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
    Then the command is refused FAILED_PRECONDITION with reason COMMAND_REFUSED, which is also its status message
    And the refusal's error info carries refusal_type "orders.v1.ItemOutOfStock"
    And the refusal's status details carry the ItemOutOfStock with item "apple" and on_hand 0

  @error_keys
  @C-0669
  Scenario Outline: A handler bug is answered with a code, never the text of what escaped
    Given business code for AddItem <fails>
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries <cause>
    And no part of the answer carries the text "<text>"

    Examples:
      | fails                                                          | cause                      | text                |
      | returns an unclassified error whose text is "connection reset" | no cause                   | connection reset    |
      | panics with "index out of bounds"                              | cause "HANDLER_PANICKED"   | index out of bounds |

  @error_keys
  @C-0672
  Scenario: A handler bug with its own code crosses as that code and its args, nested under UNHANDLED_HANDLER_ERROR
    Given business code for AddItem fails with code LEDGER_OFFLINE and arg ledger "main", and logs "the ledger is offline" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused INTERNAL with reason UNHANDLED_HANDLER_ERROR, which is also its status message
    And the refusal's error info carries cause "LEDGER_OFFLINE" and cause.ledger "main"
    And no part of the answer carries the text "the ledger is offline"

  @error_keys
  @C-0678
  Scenario Outline: A handler bug it marks retryable crosses as the status it picks, its code nested under UNHANDLED_HANDLER_ERROR
    # Decision 14.37 (owner's rulings, 2026-10-29, latest): the handler
    # picks the retryable status, and they are not interchangeable:
    # UNAVAILABLE resend, DEADLINE_EXCEEDED resend only if idempotent,
    # RESOURCE_EXHAUSTED wait longer.
    Given business code for AddItem fails with a retryable bug under <status>, code LEDGER_OFFLINE and arg ledger "main", and logs "the ledger is offline" for itself
    When AddItem "apple" is handled over no prior events
    Then the command is refused <status> with reason UNHANDLED_HANDLER_ERROR, which is also its status message
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
      | condition                                                                         | status           | reason                             | metadata                                          |
      | the state fold fails on a persisted event at sequence 3                           | INTERNAL         | FOLD_FAILED                        | sequence "3" and state_type_url                   |
      | the state fold fails on an event the command emitted at sequence 4                | INTERNAL         | FOLD_FAILED_EMITTED                | sequence "4" and state_type_url                   |
      | a command of type "/orders.v1.Unknown" arrives                                    | INTERNAL         | UNKNOWN_COMMAND_TYPE               | type_url and upcast_type_url "/orders.v1.Unknown" |
      | a fact of type "/orders.v1.Unheard" arrives                                       | INTERNAL         | NO_FACT_HANDLER                    | type_url and upcast_type_url "/orders.v1.Unheard" |
      | a CommandRefused for RemoveEverything arrives with no on_refused_RemoveEverything | INTERNAL         | NO_REFUSAL_HANDLER                 | command_type "/orders.v1.RemoveEverything"        |
      | a policy is dispatched to the business process hosting the "order" aggregate      | UNIMPLEMENTED    | NO_COMPONENT_OF_KIND               | no other metadata                                 |
      | a policy consuming "order" is given a book of domain "inventory"                  | UNIMPLEMENTED    | POLICY_SOURCE_OUTSIDE_INPUT_DOMAIN | domain "inventory" and expected_domain "order"    |
      | the router is built with two components                                           | INTERNAL         | DUPLICATE_COMPONENT                | component "order" and component_kind "AGGREGATE"  |
      | the router is built with two upcaster chains                                      | INTERNAL         | DUPLICATE_UPCASTER_CHAIN           | component "order" and component_kind "AGGREGATE"  |
      | a policy's OnRefused answer holds no fact                                         | INTERNAL         | REFUSAL_FACT_MISSING               | no other metadata                                 |
      | a policy's refusal fact sets its own cover or handling                            | INTERNAL         | REFUSAL_FACT_ADDRESSED             | no other metadata                                 |
      | a policy's refusal fact has no page                                               | INTERNAL         | REFUSAL_FACT_NO_PAGE               | no other metadata                                 |
      | a policy's refusal fact's page is a Command                                       | INTERNAL         | REFUSAL_FACT_NOT_A_FACT            | no other metadata                                 |
      | a policy's refusal fact sets its own command_id                                   | INTERNAL         | REFUSAL_FACT_IDENTIFIED            | no other metadata                                 |
      | a refusal to address names no refused command                                     | INTERNAL         | REFUSAL_WITHOUT_REFUSED_COMMAND    | no other metadata                                 |
      | a refusal to address names a refused command with no command_id                   | INTERNAL         | REFUSED_COMMAND_WITHOUT_ID         | no other metadata                                 |
      | a refusal to address names no triggering stream                                   | INTERNAL         | REFUSAL_WITHOUT_TRIGGER_STREAM     | no other metadata                                 |
      | a policy is given a Refusal with no command                                       | INTERNAL         | REFUSAL_WITHOUT_COMMAND            | no other metadata                                 |
      | a policy is given a Refusal with no event                                         | INTERNAL         | REFUSAL_WITHOUT_EVENT              | no other metadata                                 |
      | the host gives the router bytes that are no ContextualCommand                     | INTERNAL         | ANY_DECODE_FAILED                  | message_type "io.angzarr.v1.ContextualCommand"    |

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
