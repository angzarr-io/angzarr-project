# Future

What angzarr doesn't have yet, why each one matters, and the shape we expect it to take. Nothing here is
decided. Each entry ends with what would settle it.

## Why there is no saga primitive

"Saga" means two different things, and angzarr covers both without a primitive of its own.

- **The original saga** (Garcia-Molina and Salem, 1987) is a long-lived transaction split into local
  transactions, each with a *compensating* transaction that undoes it if a later step fails. Its defining
  feature is compensation.
- **The CQRS-framework "saga"** (NServiceBus, Axon) is a stateful event handler that dispatches commands.
  That is Hohpe's *Process Manager* pattern from *Enterprise Integration Patterns*; Microsoft's CQRS
  Journey points out that the name is borrowed. It puts state and decisions in a handler beside the
  aggregates, a second kind of decision-maker with its own persistence, concurrency and testing story.

In angzarr the only decisions are a domain's command handlers, and everything else is assembled from them:

- A **process manager is a domain** (decision 14.31). Its state is aggregate state, rooted at the
  correlation id (14.30), and its decisions are a decide function.
- A **policy** is a stateless event-to-command mapping with no logic of its own (14.33).
- **Compensation** uses the refusal path. When step N's command is refused, `CommandRefused` reaches the
  process manager, which decides to compensate; its events become, through policies, the commands that
  undo steps 1 to N-1.

So orchestration is a process manager, choreography is policies alone, and a 1987 saga is a process
manager that compensates.

The cost is more hops and more streams than a single saga class: event → policy → process-manager command
→ process-manager events → policy → command. That cost is real in the distributed system and close to free
in angzarr-embedded, where a process manager can be built into one binary from standard components.

## Timers and deadlines

*"If no payment arrives within 15 minutes, cancel the order."*

The spec already gives this its shape: a timeout reaches a process manager as a **fact** from a clock or
scheduler source, which it never refuses (see `process_manager.proto` and the commands-vs-facts guide).
Time then stays an input, and replay stays deterministic.

What's missing is anything that produces those facts. There is no scheduler component and no way to say
"deliver this fact at time T". Other frameworks make this central: Axon has `DeadlineManager`, NServiceBus
has `RequestTimeout`, and Temporal is built around timers.

Expected shape: a standard component, not a new primitive. A scheduler domain stores "deliver fact F to
stream S at T" as its own events, and something that watches the clock emits F once T passes. Cancelling
a deadline is a command to that domain.

Wanted first by: turn timers in the blackjack example, and taskloom's deferred tasks, which wake on a
revive condition.

Settled by: a red-reviewed scheduler component in angzarr-embedded that delivers a fact on time, survives a
restart, and delivers each fact exactly once, together with a decision on how the distributed system runs
the same component.

## Set-based validation

*"Usernames are unique." "A player holds at most one active seat."*

The rule spans many streams, but an aggregate enforces rules within one stream only. Two approaches:

- **A reservation domain:** a domain whose streams are the constrained values (for example, one stream per
  username). Claiming a value is a command to it, and a duplicate claim is refused. This can be built today
  with no new mechanism.
- **Dynamic Consistency Boundaries** (Sara Pellegrini and others): events carry tags, and a write's
  consistency check is a query over tags instead of one stream's expected version. This removes the
  reservation domains, but it changes the storage contract.

The storage contract (`angzarr-ports`) is now shared by both runtimes and every adapter, so this is
cheapest to decide while it is young, even if the answer is "reservation domains, no DCB".

Settled by: a decision recorded in the decision log; if it's DCB, a ports amendment proved by the store
suite.

## Outbound side effects

*Sending an email, calling a payment API, publishing to a partner.*

Facts bring the outside world in. Nothing yet defines how events go out. Today a projector or a policy
would do it ad hoc, with no stated delivery guarantee and no stated retry or deduplication behaviour.
Other frameworks call this a gateway, a connector, or an integration event handler.

Expected shape: assembled from a projector and the outbox, with the external call keyed by the event's id
so a retry stays idempotent. The external system's answer comes back in as a fact.

Settled by: a guide page and one example that sends and retries an external call without sending it twice,
plus a decision on whether this needs a named component.

## Forgetting personal data

*A GDPR erasure request.*

Event stores are append-only, and deleting an edition doesn't cover this: erasure targets one person's
data across every stream they appear in. The usual technique is crypto-shredding: encrypt personal fields
with a key per data subject, and delete the key to forget them. Upcasters and projections then have to
cope with fields that can no longer be decrypted.

This isn't needed for the proof of concept, but it is hard to retrofit onto data that is already stored,
so it should be decided before real personal data is.

Settled by: a decision on the technique and on where keys live, and a store-suite check that a shredded
subject's fields are unreadable after the key is deleted.

## Already covered

Not gaps, listed so they aren't rediscovered as missing:

- **Snapshots:** separate from the event write, in the storage contract.
- **Upcasters:** event and command upcasting, in the router.
- **Outbox:** written atomically with events in the store's single `write`.
- **Inbox:** deduplication on arrival, by command or fact id.
- **Read-your-writes:** a call can wait for the system to settle.
- **Catch-up subscriptions:** the `Watch` port.
- **Projection rebuilds:** `Purge` and resume by position.
- **Compensation:** the refusal path, as described above.
