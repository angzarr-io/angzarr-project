# Tier: unit-client

Client-surface cucumber, run by every `client-*-lang` repo.

## The rule: dispatch is specified by the router, not here

Dispatch behaviour — routing by type, state rebuild, command/fact/
rejection/compensation/undo dispatch, saga and process-manager handling —
is specified **only** by angzarr-router's conformance suite
([`angzarr-router/conformance`](https://github.com/angzarr-io/angzarr-router/tree/main/conformance)).
Every client repo's CI must run that suite against its router binding.
This tier never restates dispatch behaviour; a scenario that would is added
to the conformance suite instead.

## What lives here

Scenarios about what a client itself provides:

- consumer clients — `CommandHandlerClient`, `QueryClient`,
  `SpeculativeClient`, `DomainClient` (`aggregate_client`, `query_client`,
  `speculative_client`, `domain-client`)
- builders, connection, errors, retry, identity (`compute_root`), event
  decoding, the `testing` namespace, the component host and the public
  surface — in [`../../parity/client/`](../../parity/client/)

## Domain vocabulary

**Generic only.** `Order`, `Payment`, `Inventory`, `Shipping`, `Fulfillment`.
No example concepts. See [STEP_VOCABULARY.md §12, §17](../STEP_VOCABULARY.md).
Clients contain no example or business-specific types or services, so
neither do their scenarios.

## Execution style

Synchronous and in-process. The consumer-client files exercise the client
objects against the **test backend** — an in-process fake of the
coordinator gRPC stubs owned by each client repo. "A client connected to
the test backend", "the service is unavailable" and "does not respond in
time" are configurations of that fake; no coordinator runs.

A scenario that needs a real coordinator, bus or clock is not in this tier.
Coordinator behaviour belongs in [`../coordinator-contract/`](../coordinator-contract/);
the example's end-to-end flows belong in `example/blackjack-acceptance/`.

## Scenario IDs

Tag format: `@C-NNNN`, shared with `coordinator-contract/` and
`../../parity/`. Allocated sequentially in authoring order, never reused.
To allocate the next:

```bash
git grep -hoE '@C-[0-9]{4}' -- features parity | sort -u | tail -1
```

Take `max + 1`. Concurrent PRs race; later-merger rebases.

## Consumer wiring

- **Python**: `client-python/main/tests/client/steps/` — behave, direct state
- **Go**: `client-go/main/tests/client/steps/` — godog
- **Rust**: `client-rust/main/tests/client/` — cucumber-rs
- **Java**: `client-java/main/tests/client/` — cucumber-junit5
- **C#**: `client-csharp/main/Tests/Client/Steps/` — SpecFlow
- **C++**: `client-cpp/main/tests/client/` — cucumber-cpp

Each repo configures its runner to read these feature files directly from the
`angzarr-project/` submodule mount. No copies, no symlinks.

## Adding a scenario

1. Edit (or create) a `.feature` file here
2. Pick the next `@C-NNNN` ID; tag the scenario
3. Land in `angzarr-project` first
4. Each consumer repo implements step defs in its own follow-up PR; consumer
   CI is red during the window by design
