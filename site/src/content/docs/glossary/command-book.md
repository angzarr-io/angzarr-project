---
title: CommandBook
---
# CommandBook

A collection of commands to be sent to aggregates. The CommandBook is the output of sagas and process managers.

## Structure

```protobuf
message CommandBook {
  Cover cover = 1;           // Target aggregate identity
  repeated CommandPage pages = 2;  // Commands to execute
}
```

## CommandPage

Each page contains:
- **Command payload:** The actual command (Any type)
- **Header:** an explicit expected sequence (client commands), or `angzarr_deferred` provenance (saga/PM commands, appended at the destination head with no expected version)
- **Merge strategy:** How to handle conflicts

## Merge Strategies

| Strategy | Behavior |
|----------|----------|
| `MERGE_STRICT` | Reject on sequence mismatch |
| `MERGE_COMMUTATIVE` | Allow if mutations don't overlap |
| `MERGE_AGGREGATE_HANDLES` | Aggregate decides |
| `MERGE_MANUAL` | Route to DLQ for review |

## Deferred Provenance

A saga/PM command's page header carries `angzarr_deferred`:
- `source` — the aggregate whose event triggered the saga/PM
- `source_seq` — the triggering event's sequence
- `source_component` — the saga/PM's registered name (coordinator-stamped)
- `command_index` — the command's position in the emitted output

The tuple is the command's idempotency key. If the command is rejected, a [RejectionNotification](/glossary/notification) is delivered to the `source` aggregate's compensation handler.
