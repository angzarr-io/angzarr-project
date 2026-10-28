---
title: Process Manager
---
# Process Manager

Multi-domain orchestrator. Facts in, its own events out. Stateful correlation via correlation ID.

**Abbreviation:** `pmg`

Process managers are their own aggregate, with the correlation ID as aggregate root. The PM tracks the state of a specific cross-domain business process. Its only input is facts addressed to it: it subscribes to no domain, and sagas turn other domains' events into facts for it. It takes no commands and sends none; sagas from its domain turn its events into commands (decision 14.31).

Use a process manager when you need to:
- Gather what happened in several domains (as facts, through sagas)
- Maintain workflow state across domain boundaries
- Coordinate complex multi-step business processes
