---
title: Replay
---
# Replay

Reconstruct current aggregate state by applying all events from sequence 0 (or from a [snapshot](/glossary/snapshot)).

## How It Works

```mermaid
flowchart TB
    S["Snapshot<br/>seq: 100<br/>(optional optimization)"]
    E1[Event 101]
    E2[Event 102]
    E3[Event 103]
    CS["Current State<br/>seq: 103"]

    S --> E1
    E1 --> E2
    E2 --> E3
    E3 --> CS
    E1 --> CS
```

## When Replay Happens

1. **Aggregate load:** Before processing a command
2. **Projector startup:** Catching up on missed events
3. **Debugging:** Understanding how state evolved
4. **Recovery:** Rebuilding state after data loss

## Replay vs Temporal Query

| Aspect | Replay | Temporal Query |
|--------|--------|----------------|
| Target | Current state | Historical state |
| Events used | All (or from snapshot) | Up to timestamp/sequence |
| Use case | Normal operation | Audit, debugging |

## Optimization

[Snapshots](/glossary/snapshot) avoid replaying all events by caching state at checkpoints.
