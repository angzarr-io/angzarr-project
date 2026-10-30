---
title: Event
---
# Event

An immutable fact that something has occurred. Events represent state changes that **have already happened** and cannot be rejected.

## Naming Convention

Events use **past tense** naming - they describe what happened:
- `OrderCreated`
- `StockReserved`
- `PlayerRegistered`
- `FundsDeposited`

## Event vs Command vs Fact

| Aspect | Event | Command | Fact |
|--------|-------|---------|------|
| Tense | Past | Imperative | Past |
| Persisted | Yes | No (transient) | No: the events its handler records are |
| Sequenced | Yes | Optional expected sequence | Never: the head is stamped |
| Rejectable | No | Yes | No |
| Example | `OrderCreated` | `CreateOrder` | `PaymentReceived` (from Stripe) |

## In Angzarr

Events are wrapped in an [EventPage](/glossary/event-page) containing:
- Sequence number (position in aggregate timeline)
- Timestamp
- Payload (or PayloadReference for large events)

Events are stored in the [Event Store](/glossary/event-store) and are the source of truth for aggregate state.

## Internal vs External Events

Events can originate from:
- **Internal decisions**: Aggregate processed a command and decided to emit events
- **External facts**: An external system reporting something that already happened (or a policy's refusal fact)

An external fact is delivered as a command whose body is a `Fact` (see [Commands vs Facts](/components/commands-vs-facts)). Its origin (`CommandPage.fact_origin`) is copied onto every event it produces (`EventMeta.fact`), and its `command_id` is derived from `fact_origin.external_id`, enabling:
- Deduplication of redeliveries to the same stream
- Traceability from the external system to the events it caused
- Ordinary sequence numbers on those events, for every downstream consumer
