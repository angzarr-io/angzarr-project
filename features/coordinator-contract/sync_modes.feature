Feature: Sync modes - how much downstream work a command waits for
  CommandRequest.sync_mode decides what HandleCommand has finished when it
  returns. Every mode persists the aggregate's events before returning (or
  returns the rejection). They differ in downstream work:

  - ASYNC: projectors and sagas/PMs run asynchronously from the bus.
  - DECISION: as ASYNC; the point is that acceptance or rejection is the
    synchronous answer.
  - SIMPLE: projectors run synchronously and their projections are in the
    response; sagas/PMs run asynchronously.
  - CASCADE: projectors and sagas/PMs run synchronously, recursively through
    the commands they emit.
  - ISOLATED: nothing downstream runs, sync or async; events are not
    published to the bus.

  ASYNC is the zero value. DECISION exists for callers (typically process
  managers) that need only the accept/reject outcome synchronously.
  PageHeader.sync_mode on a CommandPage overrides the request's mode for
  that command; when unset the request's mode applies.

  Background:
    Given an "order" aggregate that accepts CreateOrder and rejects CancelOrder for unknown orders
    And a projector "OrderSummary" subscribed to "order"
    And a saga "OrderFulfillment" translating OrderCreated into a ReserveStock command for "inventory"

  @C-0425
  Scenario: ASYNC returns after persisting, with no projections
    When a CreateOrder command is handled with sync_mode ASYNC
    Then the response contains the OrderCreated event
    And the response contains no projections
    And the OrderCreated event is published to the bus
    And the OrderSummary projector and the OrderFulfillment saga receive it from the bus

  @C-0426
  Scenario: An unset sync_mode behaves as ASYNC
    When a CreateOrder command is handled with no sync_mode set
    Then the response contains the OrderCreated event
    And the response contains no projections

  @C-0427
  Scenario: DECISION surfaces acceptance synchronously and defers downstream work
    When a CreateOrder command is handled with sync_mode DECISION
    Then the response contains the OrderCreated event
    And the response contains no projections
    And the OrderCreated event is published to the bus

  @C-0428
  Scenario: DECISION surfaces rejection synchronously
    When a CancelOrder command for an unknown order is handled with sync_mode DECISION
    Then the command fails with the handler's rejection reason
    And no events are persisted

  @C-0429
  Scenario: SIMPLE waits for projectors only
    When a CreateOrder command is handled with sync_mode SIMPLE
    Then the response contains the OrderCreated event
    And the response contains the OrderSummary projection for the OrderCreated event
    And the OrderFulfillment saga has not run when the response is returned
    And the OrderCreated event is published to the bus

  @C-0430
  Scenario: CASCADE waits for projectors and sagas
    When a CreateOrder command is handled with sync_mode CASCADE
    Then the response contains the OrderSummary projection
    And the ReserveStock command has been handled by "inventory" when the response is returned

  @C-0431
  Scenario: CASCADE propagates to commands emitted downstream
    Given a projector "StockLevels" subscribed to "inventory"
    When a CreateOrder command is handled with sync_mode CASCADE
    Then the StockLevels projector has processed the StockReserved event when the response is returned

  @C-0432
  Scenario: ISOLATED persists without any downstream reaction
    When a CreateOrder command is handled with sync_mode ISOLATED
    Then the response contains the OrderCreated event
    And the response contains no projections
    And the OrderCreated event is not published to the bus
    And neither the OrderSummary projector nor the OrderFulfillment saga ever receives it

  @C-0433
  Scenario: ISOLATED still rejects invalid commands
    When a CancelOrder command for an unknown order is handled with sync_mode ISOLATED
    Then the command fails with the handler's rejection reason
    And no events are persisted

  @C-0434
  Scenario: A per-command sync_mode overrides the request's mode
    Given a process manager "Fulfillment" emitting a ReserveStock command with PageHeader.sync_mode DECISION
    And the inventory aggregate rejects ReserveStock
    When the PM is triggered by an OrderCreated event delivered with sync_mode ASYNC
    Then the rejection of ReserveStock is returned synchronously to the PM coordinator
    And the PM's rejection handling runs before the PM coordinator returns

  @C-0435
  Scenario: Without a per-command sync_mode the request's mode applies
    Given a process manager "Fulfillment" emitting a ReserveStock command with no PageHeader.sync_mode
    When the PM is triggered by an OrderCreated event delivered with sync_mode CASCADE
    Then the ReserveStock command is handled with sync_mode CASCADE
