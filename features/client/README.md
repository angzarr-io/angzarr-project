# Tier: unit-client

Framework-harness cucumber. Exercises the angzarr client surface in isolation,
across every `client-*-lang` repo.

## What lives here

Scenarios that verify the framework machinery:

- `Router` construction and build-time validation
- `@command_handler`, `@saga`, `@process_manager`, `@projector` class decorators
- `@handles`, `@applies`, `@rejected`, `@state_factory` method decorators
- Dispatch semantics: state rebuild from prior events, multi-handler merge,
  sequence increment, rejection compensation

## Domain vocabulary

**Generic only.** `Order`, `Payment`, `Inventory`, `Shipping`, `Fulfillment`.
No poker concepts. See [STEP_VOCABULARY.md §12, §17](../STEP_VOCABULARY.md).

This tier's scenarios are run by every `client-*-lang` repo. Poker types
would force every language client to depend on poker proto definitions just
to exercise the framework — which would be absurd. Generic domains keep the
surface tight.

## Execution style

Synchronous and in-process. No sidecars, no network, no real time.

Two kinds of file live here:

- **Router / dispatch files** (`builder`, `command_handler`, `compensation`,
  `multi_handler`, `process_manager`, `projector`, `rejected_compensation`,
  `rejection`, `router`, `saga`, `upcaster`, `validation`): state is a plain
  in-memory object built in the scenario's `Given`; `EventBook` /
  `CommandBook` are built in-process from proto types; one step = one
  handler invocation or one builder call.
- **Client-surface files** (`aggregate_client`, `domain-client`,
  `query_client`, `speculative_client`): exercise the client objects
  (`CommandHandlerClient`, `QueryClient`, `SpeculativeClient`,
  `DomainClient`) against the **test backend** — an in-process fake of the
  coordinator gRPC stubs owned by each client repo. "A client connected to
  the test backend", "the service is unavailable" and "does not respond in
  time" are configurations of that fake; no coordinator runs.

A scenario that needs a real coordinator, bus or clock is not in this tier.
Coordinator behaviour belongs in [`../coordinator-contract/`](../coordinator-contract/);
poker end-to-end belongs in `example/acceptance/`.

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
