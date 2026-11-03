---
title: Edition
---
# Edition

An identifier for diverged timelines. Editions enable branching scenarios like speculative execution, historical analysis, and what-if queries.

## Concepts

**Main timeline:** no edition name (`Cover.edition` unset)
**Edition:** a named set of per-stream forks (decision 14.32)

## Forks

Forking a stream into an edition (the first fork creates it): an `EditionCreated` meta-event is appended to the stream's edition version at the sequence `ForkStream` states (`fork_sequence`), at most main's next sequence; one above main's head is a conflict. That stream reads main's events below its fork sequence, then the edition's own. Every stream is forked explicitly, since an edition is a deliberately crafted system: a command or fact in the edition (a client's or a policy's) addressed to a stream not forked is refused `ANGZARR_REASON_EDITION_NOT_FORKED`. Every fork is per stream (one domain and root): there is no global position to fork at, and no cross-stream snapshot is promised. There is no edition registry: listing editions queries the fork events.

## Use Cases

1. **Speculative execution:** Test command outcomes without committing
2. **What-if analysis:** Explore alternative scenarios
3. **Historical branches:** Point-in-time forks for analysis
4. **Testing:** Isolated test scenarios

## No Merge

Edition events cannot be merged back into the main timeline. Events build upon each other—inserting branch events would corrupt the main timeline's causal chain. The event stream is immutable by design.

If an edition reveals the correct outcome, inject corrective facts into the main timeline. The original events remain for audit; the facts record the adjustment.

## Angzarr-Specific

Editions are an Angzarr-specific concept not found in standard event sourcing. They extend temporal queries with branching capability.

## Cleanup

`EditionAdminService.DeleteEdition` enumerates the edition's forked streams from their `EditionCreated` events and removes each stream's edition rows directly, the fork event included. Nothing is appended and nothing propagates; a removal that fails is retried, then dead-lettered and alerted. After deletion an input in the edition is refused by the not-forked rule; only an explicit `ForkStream` brings the name back. Main cannot be deleted, and knows nothing of an edition's creation or deletion.
