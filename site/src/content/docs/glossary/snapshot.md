---
title: Snapshot
---
# Snapshot

Cached aggregate state at a point in time. Snapshots optimize [replay](/glossary/replay) by avoiding the need to apply all historical events.

## When to Snapshot

The coordinator persists a snapshot whenever a command handler returns aggregate state that differs from the stored snapshot, anchored at the sequence of the last new event. There is no fixed event-count cadence: a handler that returns state on every command is snapshotted on every command. Snapshot writes are best-effort; a failed write only means the next load replays more events.

Retention decides how many snapshots accumulate. Under `RETENTION_DEFAULT` and `RETENTION_TRANSIENT` only the newest snapshot of an aggregate survives, so storage stays bounded regardless of how often snapshots are written.

## Snapshot Retention Policies

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `RETENTION_DEFAULT` | Delete when newer written (same as TRANSIENT) | Normal operation |
| `RETENTION_PERSIST` | Keep indefinitely | Business milestones |
| `RETENTION_TRANSIENT` | Delete when newer written | Temporary checkpoints |

## Structure

A snapshot contains:
- Serialized aggregate state
- Sequence number at snapshot time
- Timestamp
- Retention policy

## Trade-offs

**Without snapshots:**
- Replay all events from beginning
- Slower aggregate load
- No storage overhead

**With snapshots:**
- Replay only events after snapshot
- Faster aggregate load
- Additional storage for snapshot data
