# The router's conformance fixtures

The handler-contract tier is every router's complete contract (decision
14.42): the Rust router (angzarr-router, the reference) and the Python
router (client-python) both run every feature in `..` against these
fixtures, from this directory, in CI; `compensation.feature` is the client
libraries' process-manager tooling instead (14.74). The fixtures came from
angzarr-router's own `conformance/`, which this replaces.

- [`counter.proto`](counter.proto): the CounterAggregate (domain `counter`,
  state `CounterState.count`), the OrderPolicy (input domain `order`,
  destination `inventory`) and the CounterProjector, over one `Increased`
  event. Used by `counter_dispatch.feature`, `context.feature`,
  `policy_dispatch.feature` and `projector_dispatch.feature`.
- [`order.proto`](order.proto): the order vocabulary of `handling.feature`.
  `OrderState` keeps a quantity per item (conflict unit `items[<item>]`), a
  shipping address (its own unit) and unmarked notes (the wildcard
  `*notes`), with `changed()` what the generator emits. `AddItem(item)`
  records `ItemAdded(item)`; the fact `ItemDelivered` is recorded as
  received. The Fulfillment process manager is a domain: `StartFulfillment`
  records `FulfillmentStarted` (or nothing). The OrderFulfillment policy
  translates `OrderPlaced` into `ReserveStock` for `inventory`.
- [`compensation.proto`](compensation.proto): the shipment process
  manager of `compensation.feature` (14.74): its state (the journal, folded),
  its two steps' completing and undoing events, ShipmentFailed, and what
  the undos become, as their destinations declare them: ReleaseStock and
  RefundPayment facts, RestockItems a command (an undo targeting it is
  refused at registration, 14.83). Bound by the client libraries' compensation tooling
  (angzarr-embedded's markup, client-python), not by a router.
- [`txtpb/`](txtpb/): orthogonal envelopes the step definitions fill in.

## CounterAggregate

| Member | Type | Behaviour |
|---|---|---|
| applier | `test.counter.Increased` | folds into state: `count += 1` |
| command | `test.counter.IncreaseBy { n }` | `n > 0` emits `n` `Increased` events; `n == 0` is the rejection `VALUE_NOT_POSITIVE`, nothing emitted |
| command | `test.counter.FailHard` | fails with the language's unclassified error: `ANGZARR_REASON_UNHANDLED_HANDLER_ERROR`, no cause |

The `IncreaseBy` handler also records the `CommandContext` it observed
(`next_sequence`, `had_prior_events`), so scenarios can assert the
historical evidence the router supplies. A command no handler claims
(`test.counter.Reserve`) is `ANGZARR_REASON_UNKNOWN_COMMAND_TYPE`, before any fold.

## What the router does not do

Every delivery is built by the coordinator, so the fixtures carry no
malformed envelopes, no upcast types, no covered pages and no descriptor
to check: admission, upcasting, snapshot loading, descriptor validation,
policy output checks, refusal addressing, error classification and conflict
judgement are the coordinator's (decisions 14.39, 14.40 and 14.42).
