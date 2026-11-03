---
title: Commands vs Facts
---
This document explores a fundamental tension in event-sourced systems: the difference between **commands** (requests that can be rejected) and **facts** (external realities that must be recorded).

---

## The Problem

In traditional CQRS/ES, the flow is clear:

```text title="illustrative - command flow"
Client → Command → Aggregate → Accept/Reject → Event
```

Commands express *intent*. The aggregate validates business rules and either:
- **Accepts**: Emits events recording what happened
- **Rejects**: Returns an error

But what happens when the thing has *already happened*? Consider:

| Scenario | Source | Can You Reject It? |
|----------|--------|-------------------|
| Stripe processed a payment | External webhook | No — money moved |
| FedEx delivered the package | External tracking | No — it's delivered |
| Game timer expired | Clock/scheduler | No — time passed |
| Regulatory ruling issued | Legal system | No — it's binding |

These aren't requests. They're **facts about external reality**. The aggregate can't reject them — the world has already changed.

---

## The Terminology Problem

Traditional CQRS conflates two distinct concepts:

| Concept | Traditional Term | Actual Meaning |
|---------|-----------------|----------------|
| Request for action | Command | "Please do X" — rejectable |
| Notification of fact | Command | "X happened" — not rejectable |

When a policy receives `PaymentProcessedByStripe` and needs to inform the Order aggregate, it sends a "command" like `RecordPaymentReceived`. But this isn't really a command — the aggregate can't refuse to acknowledge that payment occurred.

This creates awkward patterns:
- Aggregates with commands that "can never fail"
- Validation logic that always returns success
- Optimistic concurrency that doesn't make sense (sequence numbers guard against concurrent *decisions*, not concurrent *fact recording*)

---

## How Other Frameworks Handle This

### The Decider Pattern (Jérémie Chassaing)

The [Functional Event Sourcing Decider](https://thinkbeforecoding.com/post/2021/12/17/functional-event-sourcing-decider) separates concerns:

```text title="illustrative - decider pattern"
decide: Command → State → Event list    # Decision logic
evolve: State → Event → State           # State transitions
```

Some implementations extend this with a separate path for facts:

```text title="illustrative - fact recording path"
record: Fact → State → Event list       # No validation, just acknowledge
```

### Martin Fowler's Recording Pattern

From [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html):

> "Turn the interaction into events at the boundary of the system and use the record of events to remember what happened."

External interactions become `*Recorded` events:
- `PaymentReceived` (internal decision)
- `ExternalPaymentRecorded` (external fact)

### Anti-Corruption Layer

Many systems use an [ACL](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer) to translate external facts into internal domain concepts at the system boundary, before they reach aggregates.

---

## Angzarr's Solution

Angzarr delivers a fact through the same command coordinator as a command (`Handle`, `HandleAsync` or `HandleSync`), and tells them apart by the page's body: `CommandPage.body` is a `Command` or a `Fact`.

### Commands vs Facts

| Message | Body | Declared by | Can be refused | Sequence |
|---------|------|-------------|----------------|----------|
| Command (client) | `CommandPage.body` `Command` | `(command)` | Yes, typed refusals only | Optional expected sequence (`ExpectedSequenceMismatch` when the stream moved) |
| Command (policy) | `ReactionDelivery.body` `command` | `(command)` | Yes, back through the policy's `Translate` | None: appended at the head the destination loaded |
| Fact (external) | `CommandPage.body` `Fact`, with its `origin` | `(fact)` | No | None: appended at the head the coordinator loaded |

Both kinds reach the same handler call, `CommandHandlerService.Handle` (decision 14.98), and the generated code uses one attribute, `#[handles]`, for both: the message's option is the declaration. Converting a message between `(command)` and `(fact)` changes only its option; the generated handler then gains or loses its refusal return.

When the coordinator receives a fact:
1. **Validation** — a `Fact` requires an `origin` with a non-empty `external_id` (it has no `Handling` to set)
2. **Idempotency** — its `command_id` is derived from `origin.external_id`, so a redelivery to the same stream is answered `DUPLICATE`, like any command
3. **Handle** — the fact's handler records it (possibly with events that flag it, e.g. a payment for an unknown order) and never refuses it
4. **Append** — at the head the coordinator loaded, like any input; a lost race re-runs it on the new head, and at the race re-run cap it is dead-lettered

A failing fact handler is a bug, not a refusal: the fact is dead-lettered and alerted, and the sender is answered `INTERNAL` `ANGZARR_REASON_FACT_DEAD_LETTERED`, which it does not retry (decision 14.100).

### Protocol Structure

```protobuf file=proto/io/angzarr/v1/types.proto region=command_page
```

Where a fact came from rides on `Fact.origin` (`FactOrigin { external_id, description }`) and is copied onto every event the fact produces (`EventMeta.causation`'s fact arm), so the audit trail shows which events were externally sourced. The rules are `docs/design/pipeline.md` §6 and §7.

### Flow Comparison

**Policy flow (a command for another domain):**
```text title="illustrative - policy command flow"
Policy receives: OrderCompleted
Policy emits:    Output { root, command: StartFulfillment } (no ids, no Handling)
Coordinator:     Stamps causation, command_id, correlation → Deliver (a ReactionDelivery)
Destination:     Handle → Accept (events at its head) / Refuse (Translate: a refusal fact back to the source)
```

**External fact flow (webhook):**
```text title="illustrative - fact flow"
Stripe webhook: PaymentReceived fact
               - origin.external_id = "pi_xxx"
               - origin.description = "Stripe webhook"
Coordinator:   Derive command_id → deduplicate → Handle → append at head → publish
```

Downstream consumers (policies, projectors, process managers) see the events a fact produces like any other events, with ordinary sequence numbers.

### Benefits

1. **Semantic clarity**: Facts are not commands. The type system reflects reality.

2. **No fake validation**: Aggregates don't need "commands that can't fail."

3. **Correct concurrency**: Facts carry no expected sequence, so they are never stale — they're recorded at the current head.

4. **Idempotency by design**: External IDs naturally deduplicate (Stripe payment ID, tracking number, etc.).

5. **Audit trail accuracy**: Events record their fact origin, externally sourced vs internally decided.

---

## When to Use Each

### Use Commands when:

- The aggregate is making a **decision**
- Business rules can **reject** the request
- A stale decision should be **refused** (an expected sequence, checked by the coordinator)
- The source is an internal actor with intent

**Examples:**
- `CreateOrder` — validate inventory, customer status
- `ReserveFunds` — check available balance
- `PlaceBet` — validate game state, bet limits

### Use Facts when:

- Something **already happened** in the external world
- The aggregate must **acknowledge**, not decide
- Several deliveries of the same fact should **deduplicate**
- The source is an external system or physical reality

**Examples:**
- `PaymentReceived` — Stripe confirmed payment
- `PackageDelivered` — FedEx tracking update
- `GameTimeExpired` — clock exhausted
- `RegulatoryHoldPlaced` — compliance system action

---

## Policies Send What the Destination Declares

A policy emits, for each type, the arm its destination declares: a **Command** for a type declared `(command)`, which the destination may refuse, and a **Fact** for a type declared `(fact)` (its own option, decision 14.91), which the destination records and never refuses. The policy's generated code picks the arm (`Output.body`); business code never does. An output is only a root and a payload, so its coordinator stamps either arm the same identity (the reaction's derived id, commands and facts counted together), and the destination derives a fact's origin: a policy cannot set either. When a target refuses one of its commands, the policy's coordinator builds a **refusal fact** for the stream of the triggering event (see [Policies: Refusals](/components/policy#refusals)).

---

## Related Concepts

- [Command](/glossary/command) — Requests that may be rejected
- [Event](/glossary/event) — Immutable records of what happened
- [Policy](/glossary/policy) — Domain bridges that emit commands and facts
- [Sequence](/glossary/sequence) — Optimistic concurrency for commands

---

## Further Reading

- [Functional Event Sourcing Decider](https://thinkbeforecoding.com/post/2021/12/17/functional-event-sourcing-decider) — Jérémie Chassaing
- [Internal and External Events](https://event-driven.io/en/internal_external_events/) — Oskar Dudycz
- [Commands & Events: What's the difference?](https://codeopinion.com/commands-events-whats-the-difference/) — CodeOpinion
- [Martin Fowler - Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)
- [Anti-Corruption Layer](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer) — Azure Architecture
