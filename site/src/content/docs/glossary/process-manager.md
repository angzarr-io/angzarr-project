---
title: Process Manager
---
# Process Manager

Multi-domain orchestrator, and a domain like any other: commands and facts in, its own events out. Stateful correlation via correlation ID.

**Abbreviation:** `pmg`

Process managers are their own aggregate, with the correlation ID as aggregate root. The PM tracks the state of a specific cross-domain business process. It takes commands (which it may refuse) and facts (which it never refuses); it subscribes to no domain, and policies turn other domains' events into commands to it. It sends no commands; policies from its domain turn its events into commands (decision 14.31).

Use a process manager when you need to:
- Gather what happened in several domains (as commands, through policies)
- Maintain workflow state across domain boundaries
- Coordinate complex multi-step business processes
