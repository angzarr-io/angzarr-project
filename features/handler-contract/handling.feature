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
    When the process manager handles an OrderPlaced event
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
    Then the registration is refused, naming the "order" aggregate already registered
    And the business process describes only the "order" aggregate

    Examples:
      | kind            | name             |
      | aggregate       | payment          |
      | saga            | OrderFulfillment |
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
    When the process manager handles an OrderPlaced event <writing>
    Then the answer's process state is the process manager's state after the reaction
    And none of the answer's process events carry a state

    Examples:
      | writing                                   |
      | and writes a FulfillmentStarted event     |
      | without writing a process event           |

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
    Then the command is refused INVALID_ARGUMENT
    And the refusal message names the type URL "/orders.v1.AddLine"
    And the refusal's error info carries upcast_type_url "/orders.v1.AddLineItem"
    And business code is not invoked

  @upcasting
  @C-0540
  Scenario: A type with no handler and no upcaster is refused naming the type as sent
    When RemoveEverything "apple" is handled over no prior events
    Then the command is refused INVALID_ARGUMENT
    And the refusal message names the type URL "/orders.v1.RemoveEverything"
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
