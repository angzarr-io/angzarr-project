# The router's conformance fixtures

The handler-contract tier is every router's complete contract (decision
14.42): the Rust router (angzarr-router, the reference) and the Python
router (client-python) both run every feature in `..` against these
fixtures, from this directory, in CI; `compensation.feature` is the client
libraries' process-manager tooling instead (14.74). The fixtures came from
angzarr-router's own `conformance/`, which this replaces.

- [`counter.proto`](counter.proto): the CounterAggregate (component
  `counter`, domain `counter`, state `CounterState.count`), the OrderPolicy
  (component `order-policy`, destination `inventory`; its source, `counter`,
  derived from the event it names, decision 14.78) and the CounterProjector
  (component `counter-projector`), over one `Increased` event, declared to
  options.proto (decisions 14.78, 14.87, 14.91 and 14.95). It compiles
  against `proto/`: `protoc -I proto -I features/handler-contract/fixture
  -o /dev/null counter.proto order.proto compensation.proto`. Used by `counter_dispatch.feature`, `context.feature`,
  `policy_dispatch.feature` and `projector_dispatch.feature`.
- [`order.proto`](order.proto): the order vocabulary of `handling.feature`.
  `OrderState` keeps a quantity per item, a shipping address and notes (the
  coordinator has no conflict concept, decision 14.92, so nothing is
  marked). `AddItem(item)` records `ItemAdded(item)`, or is refused with the
  typed refusal `ItemOutOfStock`; the fact `ItemDelivered` is recorded as
  received. The fulfillment process manager is a domain: `StartFulfillment`
  records `FulfillmentStarted` (or nothing). The order-fulfillment policy
  reacts to `OrderPlaced` with `ReserveStock` (and the fact
  `StockHoldRequested`) for `inventory`, and translates the inventory's
  refusal `StockShort` into the order fact `StockUnavailable`.
- [`compensation.proto`](compensation.proto): the shipment process
  manager of `compensation.feature` (14.74): its state (the journal, folded),
  its two steps' completing and undoing events, ShipmentFailed, and what
  the undos become, as their destinations declare them: ReleaseStock and
  RefundPayment facts, RestockItems a command (a step whose undo targets it
  is refused at registration, 14.83). Bound by the client libraries' compensation tooling
  (angzarr-embedded's markup, client-python), not by a router.
- [`txtpb/`](txtpb/): orthogonal requests the step definitions fill in:
  `HandleRequest`s (`io.angzarr.handler.v1`, its `input` book) for the
  commands, and an `EventPage` (its `event` arm) for a prior Increased.

## CounterAggregate

| Member | Type | Behaviour |
|---|---|---|
| applier | `test.counter.Increased` | folds into state: `count += 1` |
| command | `test.counter.IncreaseBy { n }` | `n > 0` emits `n` `Increased` events; `n == 0` is refused with the typed refusal `test.counter.ValueNotPositive { n }` (INVALID_ARGUMENT, `ANGZARR_REASON_COMMAND_REFUSED`), nothing emitted |
| command | `test.counter.FailHard` | fails with the language's unclassified error: `ANGZARR_REASON_UNHANDLED_HANDLER_ERROR`, no cause |

The `IncreaseBy` handler also records the context it observed
(`next_sequence`, `had_prior_events`), so scenarios can assert the
historical evidence the router supplies from `HandleRequest.history`. A command no handler claims
(`test.counter.Reserve`) is `ANGZARR_REASON_UNKNOWN_COMMAND_TYPE`, before any fold.

## What the router does not do

Every delivery is built by the coordinator, so the fixtures carry no
malformed envelopes, no upcast types, no covered pages and no descriptor
to check: admission, upcasting, snapshot loading, descriptor validation,
policy output checks, refusal addressing, error classification and the
expected-sequence check are the coordinator's (decisions 14.39, 14.40,
14.42 and 14.94).
