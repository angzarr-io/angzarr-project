---
title: Dead Letter Queue (DLQ)
---
# Dead Letter Queue (DLQ)

A destination for messages that cannot be processed automatically. Messages are routed to the DLQ when:

1. **Sequence mismatch** with `MERGE_MANUAL` strategy
2. **Processing failures** after retry exhaustion
3. **Payload retrieval failures** (external storage unavailable)
4. **Compensation delivery failures** after the notification's retries are exhausted
5. **Unrecoverable errors** in handlers

## DLQ Entry Types

Each entry carries one of four detail messages:

- **SequenceMismatchDetails** — expected vs. actual sequence and the merge strategy that routed the command to the DLQ.
- **EventProcessingFailedDetails** — why a saga, projector, or process manager failed to process events, with retry count, transience, and a structured stack trace.
- **PayloadRetrievalFailedDetails** — claim-check failures when an externally stored payload cannot be retrieved.
- **CompensationDeliveryFailedDetails** — a compensation notification that could not be delivered; the entry's `rejected_command` is the notification's delivery envelope.

```protobuf file=proto/io/angzarr/v1/types.proto region=dlq_details
```

### Stack traces

`EventProcessingFailedDetails.stack_trace` carries a Sentry-compatible structured capture from the [sererr](https://sererr.fyi) schema: per-frame function/file/line, optional source context, and an `ExceptionMechanism` that links chain entries. The array is the cause chain, most-causal-first; the originating caught error is the last element. Producers capture it at the originating failure site, not at the DLQ-publish layer, and operators read it from the status console's DLQ detail view. See [Stack-trace Proto](/reference/stack-trace-proto) for the shape and producer/consumer conventions.

## Topic Structure

Per-domain DLQ topics: `angzarr.dlq.{domain}`

## Resolution

DLQ messages require manual intervention:
1. Inspect the failed message and context
2. Fix the underlying issue
3. Resubmit or discard the message
4. Update monitoring/alerting as needed
