---
title: Edition
---
# Edition

An identifier for diverged timelines. Editions enable branching scenarios like speculative execution, historical analysis, and what-if queries.

## Concepts

**Main timeline:** no edition name (`Cover.edition` unset)
**Edition:** a named set of per-stream forks (decision 14.32)

## Forks

Creating an edition forks an origin stream: an `EditionForked` event is appended to the stream's edition version at main's next sequence. That stream reads main's events below its fork sequence, then the edition's own. The fork travels with the data: a saga's command in the edition forks the stream it reaches, on arrival (eventually consistent); a command from outside to a stream the edition hasn't reached is refused until then. A time-based fork at one global commit position is an option. There is no edition registry: listing editions queries the fork events.

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

`EditionAdminService.DeleteEdition` removes every row of an edition in every store. Main cannot be deleted.
