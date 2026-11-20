---
title: Dead Letter Queue (DLQ)
---
# Dead Letter Queue (DLQ)

A destination for messages that cannot be processed automatically. Messages are routed to the DLQ when:

1. **Lost races**: work with no caller waiting (a `HandleAsync` command, a reaction), or a fact, that lost a race at every write until the race re-run cap (`ANGZARR_REASON_RETRY_CAP_EXHAUSTED`; decisions 14.46 and 14.85). A command whose caller waits is answered the key instead and not dead-lettered.
2. **Refusals with no caller**: a `HandleAsync` command refused (by its handler, or by the coordinator's `ExpectedSequenceMismatch`)
3. **Processing failures** after retry exhaustion, and fatal bugs at once
4. **Payload retrieval failures** (external storage unavailable)
5. **Failed edition removals**: a deleted edition's rows in one stream that could not be removed (`ANGZARR_REASON_EDITION_REMOVAL_FAILED`)

## What an Entry Holds

An entry (`AngzarrDeadLetter`) is its payload and exactly one statement of why (decisions 14.101 and 14.107):

- **Payload**: the rejected client command or fact, a policy's rejected reaction (`ReactionDelivery`), the events a policy or projector failed on, or the stream whose edition removal failed (its `Cover`).
- **Why**, one of:
  - **refusal** — a typed business refusal of an asynchronous command, packed; its key is implied (`ANGZARR_REASON_COMMAND_REFUSED`) and its type is the `Any`'s type URL.
  - **reason** — every other failure: a key and its args (a `Diagnostic`), never text.
  - **transport** — a transport's own why, packed, its key implied by its type: today the distributed transport's **PayloadRetrievalFailed** (the payload's reference and the retrieval's failure; `DISTRIBUTED_REASON_PAYLOAD_UNAVAILABLE`).
- **retry_count**: the retries after the first attempt.

The distributed transport wraps each entry in a `DeadLetterEnvelope` (decision 14.64) that adds what only it knows: a structured stack trace. The angzarr-embedded kernel stores the core entry bare. Which reason each failure records, and how each payload is replayed: `docs/design/dead-letters.md`.

```protobuf file=proto/io/angzarr/v1/types.proto region=dead_letter
```

### Stack traces

`DeadLetterEnvelope.stack_trace` (the distributed transport's) carries a Sentry-compatible structured capture from the [sererr](https://sererr.fyi) schema: per-frame function/file/line, optional source context, and an `ExceptionMechanism` that links chain entries. The array is the cause chain, most-causal-first; the originating caught error is the last element. Producers capture it at the originating failure site, not at the DLQ-publish layer, and operators read it from the status console's DLQ detail view. See [Stack-trace Proto](/reference/stack-trace-proto) for the shape and producer/consumer conventions.

## Topic Structure

Per-domain DLQ topics: `angzarr.dlq.{domain}`

## Resolution

DLQ messages require manual intervention:
1. Inspect the failed message and context
2. Fix the underlying issue
3. Resubmit or discard the message
4. Update monitoring/alerting as needed
