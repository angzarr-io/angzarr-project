---
title: Coordinator
---
# Coordinator

The angzarr sidecar that abstracts framework functionality away from business logic code. Deployed as sidecar container with business logic. Thin wrapper around library code reused in standalone mode.

Coordinators handle:
- Event persistence and retrieval
- Command routing
- Subscription management
- Health checks
