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
- Its identity: a `command_id` and a `correlation_id`
- `Handling`: the optional expected sequence (`ExpectedSequenceMismatch` when the stream has moved), on client commands only

A policy's reaction command is not a CommandBook: its coordinator delivers it as a `ReactionDelivery`, with its derived id, its trigger's correlation and its trigger as causation, and no Handling.

Reaction commands come from policies only. A process manager sends no commands: it records an event carrying the data a command needs, and a policy from its domain builds the command. A target that refuses a reaction command records nothing; the policy's one refusal callback translates the refusal into a fact of its own source domain (see [Policies](/components/policy)). There is no compensation channel.

A process manager is a domain: it takes commands like an aggregate and may refuse them. When a policy's command is refused, the refusing domain records nothing; the policy delivers an unrefusable refusal fact, with the refused command's id, to the policy's own source domain.

## Commands vs Facts

Not all messages to aggregates are rejectable requests. External realities (payments processed, packages delivered) are **facts** that must be recorded, not decided upon.

Angzarr distinguishes these by the page's body arm: a `Command` or a [`Fact`](/components/commands-vs-facts), declared by its own option, `(command)` or `(fact)`. A fact's `command_id` is derived from its origin, so a redelivery is deduplicated. This preserves semantic clarity: commands request decisions, facts notify of external reality.
