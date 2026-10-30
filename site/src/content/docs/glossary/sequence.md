---
title: Sequence Number
---
# Sequence Number

The ordered position of an event within an aggregate's timeline. Sequence numbers start at 0 and increment by 1.

## Purpose

1. **Ordering:** Guarantees events are applied in correct order
2. **Idempotency:** Prevents double-application of the same event
3. **Concurrency control:** Detects conflicting concurrent writes

## In Commands

A command may carry an **expected sequence** (`Handling.expected_sequence`): the stream's head, its `next_sequence`, when the command was decided. What happens when the stream has moved is the command's **conflict resolution** (`STRICT`, `AGGREGATE_HANDLES` or `COMMUTATIVE`), defined in the `ConflictResolution` region of `io/angzarr/v1/types.proto`; see [Patterns: Conflict Resolution](/reference/patterns#conflict-resolution) for a summary.

- **At the head**: the command is decided against the current state.
- **Behind the head** (stale): the resolution decides. `STRICT` refuses it `ABORTED`, `COORDINATOR_REASON_EXPECTED_SEQUENCE_STALE`; `AGGREGATE_HANDLES` and `COMMUTATIVE` deliver the events the command did not see and apply their own rule (decision 14.45).
- **Ahead of the head**: malformed under every resolution, refused `INVALID_ARGUMENT`, `COORDINATOR_REASON_EXPECTED_SEQUENCE_AHEAD` (decision 14.47).
- **None given**: the coordinator stamps the head it decides against, so the command is never stale; a race lost at the write re-runs it on the new head (decision 14.46).

Ordering is per stream: another stream's writes never conflict.

## Example

```
Stream: order-123
Events at sequences 0..4, so next_sequence (the head) is 5

Command expecting 5
  → At the head: decided, its first event persisted at sequence 5

Command expecting 3
  → Behind the head: stale, handled per its conflict resolution

Command expecting 7
  → Ahead of the head: INVALID_ARGUMENT, COORDINATOR_REASON_EXPECTED_SEQUENCE_AHEAD
```

## Sequence vs Timestamp

- **Sequence:** Logical ordering within aggregate (gaps not allowed)
- **Timestamp:** Physical time (may have gaps, clock skew)

Use sequence for state reconstruction; use timestamp for temporal queries.

## Fact Sequences

Not all events come from command processing. External facts (payment confirmations, delivery updates) use a **FactSequence** marker instead of an integer:

```protobuf
message EventPage {
  oneof sequence_type {
    uint32 sequence = 1;        // Normal: position in stream
    FactSequence fact = 5;      // External fact marker
  }
}

message FactSequence {
  string source = 1;            // Origin system (e.g., "stripe")
  string description = 2;       // Human-readable description
}
```

The idempotency key lives on `Cover.external_id`, not in FactSequence. This ensures:
- System-wide propagation through sagas, PMs, and projectors
- Consistent deduplication at every coordinator
- Full traceability from external source to all effects

### FactSequence Elimination

The `FactSequence` marker is **replaced with a real sequence number at persistence time**. When the coordinator receives a fact event:

1. Routes to aggregate (if `route_facts_to_aggregate = true`, the default)
2. Aggregate updates state and returns events
3. Coordinator assigns the next sequence number
4. Persists with `sequence` instead of `fact`
5. Publishes event with valid sequence

Downstream consumers (sagas, projectors, process managers) always receive events with proper sequence numbers—they never see `FactSequence` markers.

See [Commands vs Facts](/components/commands-vs-facts) for details.
