---
title: Correlation ID
---
# Correlation ID

Identifies a cross-domain business process. Not a domain entity ID (like `order_id` or `game_id`) - it's the identifier for the workflow/transaction that spans domains. Stable across all events in that process.

**Propagation rules** (`docs/design/identity-and-streams.md` §6):
- It rides each command page (`CommandPage.correlation_id`) and is copied onto every event (`EventMeta.correlation_id`); a cover never carries one
- A client may supply it on its command; when absent, the coordinator sets one before anything else runs (pipeline step 2), so a persisted event never lacks one
- A policy's outputs and refusal facts carry their trigger's correlation unchanged, so everything a request led to shares it (`GetCorrelatedEvents`, or a correlation `Subscribe`)
- A process manager's root is, by convention, the correlation its policies address it by; an input whose correlation differs from its root is still delivered to that root
