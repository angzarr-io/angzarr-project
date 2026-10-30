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

## Facts

Not every event comes from a decision. A **fact** (payment confirmed, delivery updated) is something that already happened outside the system. It is delivered through the command coordinator like any command, its `CommandPage.body` a `Fact` rather than a `Command`, and its handler records it and never refuses it.

A fact carries no sequence of its own and is never checked against one: a `Fact` that sets any `Handling` field is malformed. The coordinator always stamps the stream's head, so the events the fact's handler records get ordinary sequence numbers, and downstream consumers (policies, projectors, process managers) see them like any other events.

Its origin rides on `CommandPage.fact_origin` (`FactOrigin { external_id, description }`) and is copied onto every event the fact produces (`EventMeta.fact`). The fact's `command_id` is derived from `fact_origin.external_id`, so a redelivery of the same external id to the same stream is deduplicated, like any command.

See [Commands vs Facts](/components/commands-vs-facts) and the `Fact` and `FactOrigin` messages in `io/angzarr/v1/types.proto`.
