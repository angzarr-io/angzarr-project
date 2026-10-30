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

### Axon Framework

Axon distinguishes between:
- **Decision commands**: Standard validation, can reject
- **Notification commands**: Minimal validation, expected to succeed

The aggregate handler checks which type and adjusts validation accordingly.

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

| Message | `CommandPage.body` | Handler | Can be refused | Sequence |
|---------|--------------------|---------|----------------|----------|
| Command (client) | `Command` | `decide` | Yes | Optional expected sequence, per its conflict resolution |
| Command (policy) | `Command` | `decide` | Yes | None: the destination stamps its head |
| Fact (external) | `Fact`, with `fact_origin` | `ingest` | No | None: the coordinator stamps the head |

When the coordinator receives a fact:
1. **Validation** — a `Fact` requires `fact_origin` with a non-empty `external_id`, and never carries any `Handling` field
2. **Idempotency** — its `command_id` is derived from `fact_origin.external_id`, so a redelivery to the same stream is answered `DUPLICATE`, like any command
3. **Ingest** — the fact's handler records it (possibly with events that flag it, e.g. a payment for an unknown order) and never refuses it
4. **Append** — at the stream's head: no sequence check, no conflict resolution

A failing fact handler is a bug, not a refusal: the fact is dead-lettered and alerted, and the sender is answered "accepted, parked" (`OK`, `Outcome.delivery` `PARKED`), never a rejection.

### Protocol Structure

```protobuf file=proto/io/angzarr/v1/types.proto region=command_page
```

Where a fact came from rides on `CommandPage.fact_origin` (`FactOrigin { external_id, description }`) and is copied onto every event the fact produces (`EventMeta.fact`), so the audit trail shows which events were externally sourced.

### Flow Comparison

**Policy flow (a command for another domain):**
```text title="illustrative - policy command flow"
Policy receives: OrderCompleted
Policy emits:    StartFulfillment command (no ids, no Handling)
Coordinator:     Stamps causation, command_id, correlation → delivers
Destination:     decide → Accept (events at its head) / Refuse (a refusal fact back to the source)
```

**External fact flow (webhook):**
```text title="illustrative - fact flow"
Stripe webhook: PaymentReceived fact
               - fact_origin.external_id = "pi_xxx"
               - fact_origin.description = "Stripe webhook"
Coordinator:   Derive command_id → deduplicate → ingest → append at head → publish
```

Downstream consumers (policies, projectors, process managers) see the events a fact produces like any other events, with ordinary sequence numbers.

### Benefits

1. **Semantic clarity**: Facts are not commands. The type system reflects reality.

2. **No fake validation**: Aggregates don't need "commands that can't fail."

3. **Correct concurrency**: Facts don't compete with decisions — they're recorded at the head.

4. **Idempotency by design**: External IDs naturally deduplicate (Stripe payment ID, tracking number, etc.).

5. **Audit trail accuracy**: Events record their fact origin, externally sourced vs internally decided.

---

## When to Use Each

### Use Commands when:

- The aggregate is making a **decision**
- Business rules can **reject** the request
- Concurrent commands should **conflict** (optimistic concurrency)
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

## Policies Send Commands, Not Facts

A policy's business code emits Commands only. The one fact a policy delivers is a **refusal fact**: when a target refuses one of its commands, the policy's coordinator builds a fact of the refusal for the stream of the triggering event (see [Policies: Refusals](/components/policy#refusals)). A policy that returns a Fact, or a Command carrying `fact_origin`, is a policy bug (`COORDINATOR_REASON_POLICY_COMMAND_IS_FACT`, `COORDINATOR_REASON_POLICY_COMMAND_FACT_ORIGIN`).

---

## Related Concepts

- [Command](/glossary/command) — Requests that may be rejected
- [Event](/glossary/event) — Immutable records of what happened
- [Policy](/glossary/policy) — Domain bridges that emit commands
- [Sequence](/glossary/sequence) — Optimistic concurrency for commands

---

## Further Reading

- [Functional Event Sourcing Decider](https://thinkbeforecoding.com/post/2021/12/17/functional-event-sourcing-decider) — Jérémie Chassaing
- [Internal and External Events](https://event-driven.io/en/internal_external_events/) — Oskar Dudycz
- [Commands & Events: What's the difference?](https://codeopinion.com/commands-events-whats-the-difference/) — CodeOpinion
- [Martin Fowler - Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)
- [Anti-Corruption Layer](https://learn.microsoft.com/en-us/azure/architecture/patterns/anti-corruption-layer) — Azure Architecture
