---
title: Snapshot
---
# Snapshot

Cached aggregate state at a point in time. Snapshots optimize [replay](/glossary/replay) by avoiding the need to apply all historical events.

## When to Snapshot

Snapshots are a framework optimisation, never business data. The client library returns the post-command state on every answer (`HandleResponse.state`); business code never decides when. The coordinator persists it per the domain's storage policy (by default only the newest snapshot of a stream is kept), anchored at the sequence of the last event folded in and stamped with the answer's rules version. A failed snapshot write only means the next load replays more events. Business milestones are domain events, never retained snapshots.

## When One Is Offered

The coordinator offers a snapshot with a delivery only when its state type is the one the component registered and its rules version is compatible with the registered one (major.minor for SemVer versions, exact equality otherwise). One that fails either check is simply not offered: the delivery carries every page from sequence 0. The rules are `docs/design/snapshots.md`.

## Structure

```protobuf file=proto/io/angzarr/v1/types.proto region=aggregate_snapshot
```

## Trade-offs

**Without snapshots:**
- Replay all events from beginning
- Slower aggregate load
- No storage overhead

**With snapshots:**
- Replay only events after snapshot
- Faster aggregate load
- Additional storage for snapshot data
