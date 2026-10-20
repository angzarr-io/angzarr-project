Feature: Upcasting - readers only ever see current event shapes
  Stored events keep the shape they were written in. The coordinator that
  owns a stream brings them up to date on every way out of the store: when
  it loads the stream for its own component, when it answers a query, and
  wherever stored events reach a subscriber, whether published live or read
  from stored history (catching up, filling a gap, rebuilding). Live
  publishing carries only newly appended events, already in the current
  shape, so old shapes reach subscribers through stored history. It does so by asking its own
  business process, whose component's upcasters know the old shapes.
  Sagas, process managers and projectors reading another component's
  stream never see an old shape and have no upcasters of their own.

  Background:
    Given an "order" aggregate whose business process upcasts OrderPlacedV1 to OrderPlaced
    And order "order-1" has a stored OrderPlacedV1 event at sequence 0

  @upcasting
  @C-0584
  Scenario: Loading a stream for a command delivers current shapes
    When the coordinator delivers an AddItem command for order "order-1"
    Then business code receives an OrderPlaced event at sequence 0

  @upcasting
  @C-0585
  Scenario: A query returns current shapes
    When a client queries the events of order "order-1" through the "order" coordinator
    Then the result carries an OrderPlaced event at sequence 0

  @upcasting
  @C-0586
  Scenario Outline: A subscriber reading stored history receives current shapes
    Given a projector "OrderSummary" subscribed to "order"
    When the projector <reads> order "order-1"'s stored history from sequence 0
    Then the projector receives an OrderPlaced event at sequence 0
    And the projector is never given an OrderPlacedV1 event

    Examples:
      | reads                     |
      | catches up on             |
      | fills a gap in            |
      | is rebuilt from           |

  @upcasting
  @C-0587
  Scenario: Upcasting never rewrites the store
    When the coordinator delivers an AddItem command for order "order-1"
    Then order "order-1"'s stored event at sequence 0 is still an OrderPlacedV1
