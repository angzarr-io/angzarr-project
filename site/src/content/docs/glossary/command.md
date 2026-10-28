---
title: Command
---
# Command

A request to perform an action. Commands express intent and **may be rejected** if business rules are violated.

## Naming Convention

Commands use **imperative** naming - they tell the system what to do:
- `CreateOrder`
- `ReserveStock`
- `RegisterPlayer`
- `DepositFunds`

## Command vs Event

| Aspect | Command | Event |
|--------|---------|-------|
| Tense | Imperative (do this) | Past (this happened) |
| Rejection | Can be rejected | Cannot be rejected |
| Validation | Validated by aggregate | Already validated |
| Example | `CreateOrder` | `OrderCreated` |

## In Angzarr

Commands are wrapped in a [CommandBook](/glossary/command-book) containing exactly one command:
- The command payload
- Its identity: a `command_id`, a `correlation_id`, and for a saga's reaction command the triggering event (`causation_id`)
- `Handling`: the expected sequence number (for optimistic concurrency) and the conflict resolution, on client commands to an aggregate only

Reaction commands come from sagas only. A process manager sends no commands: it records an event carrying the data a command needs, and a saga from its domain builds the command. A target that refuses a reaction command records nothing; the saga's on-refused callback crafts a fact of the refusal for the saga's own domain (see [Process Managers](/components/process-manager)). There is no compensation channel.

A process manager is a domain: it takes commands like an aggregate and may refuse them. When a saga's command is refused, the refusing domain records nothing; the saga's on-refused callback turns the refusal into an unrefusable fact for the saga's own source domain.

## Commands vs Facts

Not all messages to aggregates are rejectable requests. External realities (payments processed, packages delivered) are **facts** that must be recorded, not decided upon.

Angzarr distinguishes these by allowing [fact events](/components/commands-vs-facts) — events sent directly to aggregates with idempotency keys instead of sequence numbers. This preserves semantic clarity: commands request decisions, facts notify of external reality.
