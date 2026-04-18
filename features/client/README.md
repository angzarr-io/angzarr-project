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

Synchronous. Direct state. Factories invoked per dispatch.

- State is a plain in-memory object constructed in the scenario's `Given`
- `EventBook` / `CommandBook` built in-process from proto types
- No `CommandClient`, no sidecars, no gRPC, no `within N seconds`
- One step = one handler invocation or one builder call

If a scenario needs a real router, real bus, or real time — it's not in this
tier. It's either `example/acceptance/` (if it's poker E2E) or pytest (if
it's framework integration).

## Scenario IDs

Tag format: `@C-NNNN`. Allocated sequentially in authoring order, never
reused. To allocate the next:

```bash
git grep -hoE '@C-[0-9]{4}' features/client/ | sort -u | tail -1
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
