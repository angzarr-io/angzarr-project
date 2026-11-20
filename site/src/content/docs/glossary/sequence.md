---
title: Sequence Number
---
# Sequence Number

The ordered position of an event within an aggregate's timeline. Sequence numbers start at 0 and increment by 1.

## Purpose

1. **Ordering:** Guarantees events are applied in correct order
2. **Idempotency:** Prevents double-application of the same event
3. **Concurrency control:** A write is appended at the head its coordinator loaded, so a concurrent write to the same stream is detected and re-run

## In Commands

A command may carry an **expected sequence** (`Handling.expected_sequence`): the stream's `next_sequence` the client decided against ("I decided having seen version N"). The coordinator has no conflict-resolution concept (decision 14.92); it checks this one thing (decision 14.94; `docs/design/pipeline.md` §5), before the handler is called:

- **At the head**: the command is decided against the current state.
- **Not the head, behind or ahead**: refused `FAILED_PRECONDITION`, the framework's typed refusal `ExpectedSequenceMismatch { expected, head }`, and nothing is persisted. The caller re-reads and decides again.
- **None given**: the command is decided on the current state. The coordinator never stamps one.

Either way the coordinator appends at the head it loaded; a write that loses a race to another write to the same stream is re-run on the new head, where a command with an expected sequence is then refused and one without is decided again, under the race re-run cap (decision 14.84). Ordering is per stream: another stream's writes never matter. See [Patterns: Concurrency](/reference/patterns#concurrency).

## Example

```
Stream: order-123
Events at sequences 0..4, so next_sequence (the head) is 5

Command expecting 5
  → At the head: decided, its first event persisted at sequence 5

Command expecting 3
  → FAILED_PRECONDITION, ExpectedSequenceMismatch { expected: 3, head: 5 }

Command expecting 7
  → FAILED_PRECONDITION, ExpectedSequenceMismatch { expected: 7, head: 5 }

Command with no expected sequence
  → decided on the state at head 5
```

## Sequence vs Timestamp

- **Sequence:** Logical ordering within aggregate (gaps not allowed)
- **Timestamp:** Physical time (may have gaps, clock skew)

Use sequence for state reconstruction; use timestamp for temporal queries.

## Facts

Not every event comes from a decision. A **fact** (payment confirmed, delivery updated) is something that already happened outside the system. It is delivered through the command coordinator like any command, its `CommandPage.body` a `Fact` rather than a `Command`, and its handler records it and never refuses it.

A fact carries no sequence of its own and is never checked against one: a `Fact` has no `Handling` to set. It is appended at the head the coordinator loaded, like any input, so the events the fact's handler records get ordinary sequence numbers, and downstream consumers (policies, projectors, process managers) see them like any other events.

Its origin rides on `Fact.origin` (`FactOrigin { external_id, description }`) and is copied onto every event the fact produces (`EventMeta.causation`'s fact arm). The fact's `command_id` is derived from `origin.external_id`, so a redelivery of the same external id to the same stream is deduplicated, like any command.

See [Commands vs Facts](/components/commands-vs-facts) and the `Fact` and `FactOrigin` messages in `io/angzarr/v1/types.proto`.
