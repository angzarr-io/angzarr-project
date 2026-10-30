---
title: Policy
---
# Policy

Domain bridge component. Events from one source domain in, commands for one destination domain out. Stateless translation between bounded contexts.

A policy translates between exactly two domains, and there is one policy per (source, destination) pair. Anything that needs several destinations, or state, is a [process manager](/glossary/process-manager).

Policies should contain minimal logic — just enough to map fields and construct target commands. If you need conditionals or business rules, that logic belongs in the source aggregate.

Policies are stateless — each event is processed independently with no memory of previous events.

## Output

A policy's business code emits **commands** only, never facts. The policy's coordinator stamps each command's identity (its causation, a derived command id and the trigger's correlation) and delivers it through a transactional outbox.

When a target refuses one of those commands, the coordinator builds one **refusal fact** for the stream of the triggering event: the standard `CommandRefused` passed through, or a domestic fact the policy translates the refusal into. That refusal fact is the only fact a policy delivers.

See [Policies](/components/policy) and [Commands vs Facts](/components/commands-vs-facts).
