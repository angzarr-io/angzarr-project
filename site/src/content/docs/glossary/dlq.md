---
title: Dead Letter Queue (DLQ)
---
# Dead Letter Queue (DLQ)

A destination for messages that cannot be processed automatically. Messages are routed to the DLQ when:

1. **Sequence mismatch**: a queued command with a caller-provided expected sequence answered `ABORTED` (resending it verbatim cannot succeed), or a command or fact that lost a race at every write until a retry cap (`COORDINATOR_REASON_RETRY_CAP_EXHAUSTED`; decisions 14.45 and 14.46)
2. **Processing failures** after retry exhaustion
3. **Payload retrieval failures** (external storage unavailable)
4. **Failed edition removals**: a deleted edition's rows in one stream that could not be removed (`COORDINATOR_REASON_EDITION_REMOVAL_FAILED`)
5. **Unrecoverable errors** in handlers

## DLQ Entry Types

Each entry carries exactly one of four detail messages, chosen by its reason (the mapping on `AngzarrDeadLetter.rejection_details`):

- **SequenceMismatchDetails** — the expected sequence the command carried and the stream's head (its `next_sequence`) when it was refused.
- **CommandRefusedDetails** — a typed business refusal of an asynchronous command: the refusal's type and the refusal object itself.
- **ProcessingFailedDetails** — why a handler or the coordinator failed to process the entry's events, command or edition removal, with retry count, transience, and a structured stack trace.
- **PayloadRetrievalFailedDetails** — claim-check failures when an externally stored payload cannot be retrieved.

```protobuf file=proto/io/angzarr/v1/types.proto region=dlq_details
```

### Stack traces

`ProcessingFailedDetails.stack_trace` carries a Sentry-compatible structured capture from the [sererr](https://sererr.fyi) schema: per-frame function/file/line, optional source context, and an `ExceptionMechanism` that links chain entries. The array is the cause chain, most-causal-first; the originating caught error is the last element. Producers capture it at the originating failure site, not at the DLQ-publish layer, and operators read it from the status console's DLQ detail view. See [Stack-trace Proto](/reference/stack-trace-proto) for the shape and producer/consumer conventions.

## Topic Structure

Per-domain DLQ topics: `angzarr.dlq.{domain}`

## Resolution

DLQ messages require manual intervention:
1. Inspect the failed message and context
2. Fix the underlying issue
3. Resubmit or discard the message
4. Update monitoring/alerting as needed
