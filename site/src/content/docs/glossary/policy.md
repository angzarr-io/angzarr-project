---
title: Policy
---
# Policy

Domain bridge component. Events from one source domain in, commands for one destination domain out. Stateless translation between bounded contexts.

A policy translates between exactly two domains, and there is one policy per (source, destination) pair. Anything that needs several destinations, or state, is a [process manager](/glossary/process-manager).

Policies should contain minimal logic — just enough to map fields and construct target commands. If you need conditionals or business rules, that logic belongs in the source aggregate.

Policies are stateless — each event is processed independently with no memory of previous events.

## Output

A policy's business code emits what its destination declares: a **command** for a type declared `(command)`, a **fact** for one declared `(fact)` (decision 14.69). Each output is a root and a payload; the policy's coordinator stamps its identity (its causation, a derived command id and the trigger's correlation) and delivers it through a transactional outbox.

When a target refuses one of its commands, the policy's one refusal callback translates the refusal into a domestic fact of its source, which the coordinator delivers to the stream of the triggering event. That refusal fact is the only output a policy delivers to its own source.

See [Policies](/components/policy) and [Commands vs Facts](/components/commands-vs-facts).
