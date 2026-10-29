---
title: Edition
---
# Edition

An identifier for diverged timelines. Editions enable branching scenarios like speculative execution, historical analysis, and what-if queries.

## Concepts

**Main timeline:** no edition name (`Cover.edition` unset)
**Edition:** a named set of per-stream forks (decision 14.32)

## Forks

Creating an edition forks an origin stream: an `EditionCreated` meta-event is appended to the stream's edition version at the sequence `ForkStream` states (`parent_sequence`), at most main's next sequence; one above main's head is a conflict. That stream reads main's events below its fork sequence, then the edition's own. The fork travels with the data: a saga's command in the edition forks the stream it reaches, on arrival, at the main head read for that stream (eventually consistent); a command from outside to a stream the edition hasn't reached is refused until then. Every fork is per stream (one domain and root): there is no global position to fork at, and no cross-stream snapshot is promised. There is no edition registry: listing editions queries the fork events.

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

`EditionAdminService.DeleteEdition` appends an `EditionDeleted` meta-event to the edition's origin streams. Per stream, in order: the event is recorded in the stream's own domain, after its earlier work; it travels onward through the saga flows the creations did, and each stream it reaches records its own; and only after it has propagated onward are that stream's edition rows removed, the event included. Nothing remains. A stream the delete can't reach through the saga flows keeps its rows, and the edition stays listed. After deletion a later arrival in the edition is refused `NOT_FOUND`; only an explicit `ForkStream` brings the name back. Main cannot be deleted, and knows nothing of an edition's creation or deletion.
