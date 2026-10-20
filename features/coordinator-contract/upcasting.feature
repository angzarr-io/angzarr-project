Feature: Upcasting - readers only ever see current event shapes
  Stored events keep the shape they were written in. The coordinator that
  owns a stream brings them up to date on every way out of the store: when
  it loads the stream for its own component, when it answers a query, and
  when it publishes events for subscribers. It does so by asking its own
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
  Scenario: Subscribers receive current shapes
    Given a saga "OrderFulfillment" subscribed to "order"
    When the "order" coordinator publishes order "order-1"'s event at sequence 0
    Then the saga receives an OrderPlaced event
    And the saga is never given an OrderPlacedV1 event

  @upcasting
  @C-0587
  Scenario: Upcasting never rewrites the store
    When the coordinator delivers an AddItem command for order "order-1"
    Then order "order-1"'s stored event at sequence 0 is still an OrderPlacedV1
