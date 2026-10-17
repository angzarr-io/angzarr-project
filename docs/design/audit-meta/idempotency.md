# Idempotency: research and the chosen design

Part of the [audit-meta design record](../audit-meta-followups.md). The
contract text is in `proto/io/angzarr/v1/types.proto`, in the `origin`
region and `IdempotencyClaim`.

## Problem

Before pass 5, the framework deduplicated caused commands and facts, but
`types.proto` stated that "request-origin commands are not deduplicated by
the framework". Two paths deliver client commands at least once:
`HandleAsync`, which enqueues them on the bus, and DLQ replay. A redelivered
client command could therefore apply twice (review finding W1). The user
leaned against storing commands anywhere. The question was what other CQRS/ES
systems do, and which design fits angzarr.

## Comparison

These descriptions come from knowledge, not from fetching each product's
current documentation for this note. Treat the specific numbers (retention
windows, status codes) as "verify before citing externally".

| System | Where the key lives | Scope | What is stored | Failed / rejected attempt | Payload check | Retention | Atomic with the write? |
|---|---|---|---|---|---|---|---|
| Stripe API | `Idempotency-Key` header, chosen by the client | per account | status code and body of the first attempt that started executing | stored and replayed, 500s included (validation failures and concurrent conflicts are not stored) | yes: changed parameters are an error | at least 24 hours | yes (internal) |
| IETF Idempotency-Key draft (httpapi WG) | `Idempotency-Key` header | per resource | the server's choice | the server's choice | fingerprint recommended; reuse with a different payload is 422 | resource-defined | not specified; concurrent use is 409, a missing key 400 |
| AWS Lambda Powertools Idempotency | key derived from the event (JMESPath) | per function | the result, with an IN_PROGRESS/COMPLETED status | record deleted on exception, so a retry runs again | optional payload-validation hash | 1 hour by default | conditional write before the handler, completed after |
| NServiceBus Outbox | message id | per endpoint | outgoing messages plus a dedup record | the transaction rolls back, nothing is stored, and the message is retried | no | 7 days by default (`TimeToKeepDeduplicationData`) | **yes**: the same transaction as the business data |
| MassTransit inbox/outbox | message id + consumer (`InboxState`) | per consumer | inbox state and outbox messages | rolled back and retried | no | a duplicate-detection window (30 minutes by default) | yes, with EF Core/Mongo |
| Wolverine | envelope/message id (durable inbox) | per endpoint | inbox and outbox envelopes | not marked handled, so it is retried | no | configurable cleanup | **yes**: transactional with Marten/EF |
| KurrentDB | event ids on append | per stream | the events themselves | n/a: a conflict is a failed append | event ids must match | a recent-append window | inherent: it is the append |
| Marten (alone) | none for commands; expected version | per stream | the events | n/a | no | n/a | n/a (Wolverine adds an inbox) |
| Axon | none built in for commands | per aggregate | the events | n/a | no | n/a | n/a (event processors use tracking tokens) |
| Equinox | in the decider's state (processed ids folded in) | per stream | the events | n/a | domain-specific | as long as state remembers | inherent: the ids are in the stream |
| Temporal | workflow id plus reuse policy; request id on start | per namespace | workflow history | depends on the reuse policy | no | the retention period | yes (internal) |

Three families emerge:
- **API key stores** (Stripe, the IETF draft, Powertools): a client key, a
  fingerprint and a retention window.
- **Messaging inboxes and outboxes** (NServiceBus, MassTransit, Wolverine):
  dedup by message id, recorded in the same transaction as the business data,
  with failures rolled back so they can be retried.
- **Event-store-native** (KurrentDB, Equinox, Marten/Axon with expected
  versions): idempotency rides on the append or on the domain state, with no
  separate store.

## The chosen design

The user decided on a key store, as proposed. The coordinator checks it
before business code.

| Aspect | Decision |
|---|---|
| Keys | `(request_id, index)` for a request origin, **client-supplied only** (pass 8: a minted request id is never a key); `(event, component, index)` for causation; `external_id` for a fact |
| Scope | per addressed aggregate: the unique key is (`CommandBook.cover`, key) |
| Claim | written **in the same transaction as the event append**, so a claim exists if and only if its events do |
| What is claimed | only an **applied** outcome: a sequence range on the stream, where zero events is a valid, claimed range |
| Rejections | **released, not claimed**. A rejected command writes nothing and can be retried with the same key (Wolverine-style). Parked facts are not claimed either. |
| Duplicate answer | business code does not run. The coordinator **re-reads the claimed range** and answers with those events and `DELIVERY_OUTCOME_DUPLICATE`. |
| Concurrency | **optimistic**: the stream's expected sequence and the claim's uniqueness. One concurrent delivery commits, and the loser re-reads and answers DUPLICATE. There is no IN_PROGRESS state. |
| Fingerprint | a hash over the body payload **as received** (the `Any` type URL and value bytes, never re-serialised). SDKs serialise deterministically. A request key that arrives with a different fingerprint is refused `FAILED_PRECONDITION`. |
| Retention | **24 hours** for client (request) keys; **7 days** for causation and fact keys |
| DLQ replay | keeps the original keys. It refuses an entry older than its key's retention unless the operator overrides it. |
| Required keys | A client-supplied `request_id` is required for `HandleAsync` and DLQ replay. `Handle`/`HandleSync` accept requests without one, which are simply not deduplicated. Request ids are still **always assigned** (pass 8): the coordinator mints a UUIDv7 and sets `RequestOrigin.minted`, for audit only; minted ids are never claimed or fingerprinted. |
| Backend capability | a backend that cannot write the claim atomically with the append does not offer `HandleAsync` or replay (`UNIMPLEMENTED`) |
| Schema | `IdempotencyClaim` in `types.proto`, documented as storage-only |

### Alignments

- **Client key, fingerprint, 24-hour retention**: Stripe and the IETF draft.
- **Atomic with the business write, 7-day retention for message keys**: the
  NServiceBus outbox. The Wolverine and MassTransit transactional inboxes are
  the same idea.
- **Release on failure**: Wolverine, the NServiceBus rollback, and AWS
  Powertools deleting the record when the handler throws.
- **No separate command log**: like KurrentDB, Equinox and Marten, the events
  are the record. The claim stores a range into the stream, not a copy of the
  response. This honours the user's lean against storing commands.

### Divergences, and why

- **Rejections are not replayed** (Stripe stores and replays error results).
  An angzarr rejection depends on stream state. A retry after the state moves
  on must be able to succeed, and storing the rejection would block that.
- **The scope is the addressed aggregate, not the account.** The claim must
  share the append's transaction, which is per stream. The same request may
  legitimately address two streams, with different indexes.
- **Duplicates re-read events instead of storing a response.** The events are
  already durable, which keeps claims small.
- **No IN_PROGRESS state, and no 409 on concurrent use** (the IETF draft and
  Powertools have both). Because the claim commits with the append, a
  concurrent duplicate loses the optimistic race and is answered DUPLICATE,
  with no lock to expire.
- **Fingerprint mismatch is `FAILED_PRECONDITION`, not 422.** gRPC has no 422;
  `FAILED_PRECONDITION` is the closest terminal code ("the system is not in a
  state required for the operation": the key is bound to another payload).
  The REST gateway may map it to 422.

### Still open

- **Fingerprint mismatch on causation and fact keys.** The contract defines
  the refusal for request keys only. With the transient outbox, a causation
  mismatch means a framework bug. A fact mismatch means the external system
  re-used an id for a different payload. Options: answer DUPLICATE and alert,
  or refuse and dead-letter.
- **Repeated parks.** A parked fact is not claimed, so a webhook that keeps
  redelivering a fact whose ingest fails produces a dead-letter entry per
  attempt, unless the DLQ deduplicates entries per key (backlog KS-9).
- **Reactions on backends without atomic claims.** The capability note
  removes `HandleAsync` and replay. Reaction delivery is also at least once,
  so it is unclear whether such a backend can run sagas and PMs at all, or
  whether it runs them unsafely and flags them.

## annals

annals needs no idempotency store. It is in-process and atomic, with no
at-least-once bus. The residual risks are covered without one: webhook facts
use a unique index on (stream, `external_id`), and an optional
`record_command` port protects HTTP retries. See
[annals-divergence.md](annals-divergence.md).

annals **fingerprints** like angzarr (user, after pass 7): it records the
payload fingerprint with each request key it records and refuses a request
key reused with a different payload. It also follows pass 8: request ids are
always assigned (a UUIDv7 minted when absent, flagged `minted`), and only
client-supplied ones deduplicate.
