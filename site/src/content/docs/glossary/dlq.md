---
title: Dead Letter Queue (DLQ)
---
# Dead Letter Queue (DLQ)

A destination for messages that cannot be processed automatically. Messages are routed to the DLQ when:

1. **Sequence mismatch**: a queued command with a caller-provided expected sequence answered `ABORTED` (resending it verbatim cannot succeed), or a command or fact that lost a race at every write until a retry cap (`ANGZARR_REASON_RETRY_CAP_EXHAUSTED`; decisions 14.45 and 14.46)
2. **Processing failures** after retry exhaustion
3. **Payload retrieval failures** (external storage unavailable)
4. **Failed edition removals**: a deleted edition's rows in one stream that could not be removed (`ANGZARR_REASON_EDITION_REMOVAL_FAILED`)
5. **Unrecoverable errors** in handlers

## DLQ Entry Types

Each entry carries exactly one of three detail messages, chosen by its reason (the mapping on `AngzarrDeadLetter.rejection_details`):

- **SequenceMismatchDetails** — the expected sequence the command carried and the stream's head (its `next_sequence`) when it was refused.
- **CommandRefusedDetails** — a typed business refusal of an asynchronous command: the refusal's type and the refusal object itself.
- **ProcessingFailedDetails** — why a handler or the coordinator failed to process the entry's events, command or edition removal, with retry count and transience.

The distributed transport wraps each entry in a `DeadLetterEnvelope` (decision 14.64) that adds what only it knows: a structured stack trace. When an externally stored (claim-checked) payload cannot be retrieved, the entry's why is the transport's **PayloadRetrievalFailed** (the payload's reference and the retrieval's failure), packed in the dead letter's `transport` arm. The angzarr-embedded kernel stores the core entry bare.

```protobuf file=proto/io/angzarr/v1/types.proto region=dlq_details
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
