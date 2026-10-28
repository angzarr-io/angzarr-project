# Idempotency: research and the chosen design

Part of the [audit-meta design record](../audit-meta-followups.md). The
contract text is in `proto/io/angzarr/v1/types.proto`: the
`command_identity` region (command ids and deduplication), the
`derived_ids` region (the derivations), and the pipeline in the `handling`
region.

**Pass 12 replaced the design.** Passes 5–10 chose a key store
(`IdempotencyClaim`) with payload fingerprints and retention. Pass 12
(decisions 12.1 and 12.2) deleted the store and moved deduplication onto the
events, keyed by one `command_id` per command. The research below is
unchanged; the chosen design follows it, and the superseded key-store design
is summarised at the end.

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

## The chosen design (pass 12): dedup by `command_id`, on the events

The user chose the event-store-native family: the KurrentDB and Equinox
model, with the message-id convention of the messaging inboxes.

| Aspect | Decision |
|---|---|
| Key | **One `command_id` per command** (`CommandPage.command_id`, a `UUID`). A client Command's is client-supplied (any version; an SDK mints a v7 and reuses it on retry) or, when absent, a UUIDv7 the coordinator mints. A reaction command's is **derived**: UUIDv5(`ANGZARR_COMMAND_NAMESPACE`, netstrings of the trigger `EventRef`, the reacting component and the command's index). A Fact's is **derived**: UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`, `external_id`). The exact encodings and worked values are in the `derived_ids` region. |
| Where it lives | **On the events.** Every event the command produces carries it as its causation (`EventMeta.causation.command_id`, pass 13). There is no separate store. |
| Lookup | "Already applied?" means that the addressed stream holds events with this `command_id`. Every backend keeps an index on (stream, `command_id`), which is not unique: a command may write several events. |
| Scope | Per addressed stream (`CommandBook.cover`). The same id sent to two streams is two commands. |
| Order | **Normative**: validate, then assign ids (mint or derive), then **load the stream, then the dedup lookup**, then resolve and check Handling against the loaded head, then business code. A retry of an applied STRICT command whose expected sequence is now stale is therefore DUPLICATE, not ABORTED. |
| Duplicate answer | Business code does not run. The coordinator answers with the stored events, in sequence order, and `DELIVERY_OUTCOME_DUPLICATE`. |
| Atomicity | Inherent: the id is written in the append itself, on every backend. There is no "atomic claims" capability. |
| Concurrency | The append's optimistic sequence check: one concurrent delivery commits, and the loser re-runs from the load and lookup and is answered DUPLICATE. This relies on **loading before the lookup**: under READ COMMITTED, a lookup first can miss an original that commits before the load, and the retry, loading the new head, appends with no conflict (applied twice). Loaded first, a commit after the load is either seen by the lookup or fails the retry's append on its expected head. |
| Rejections and parked facts | Write nothing, so a retry with the same id runs business code again (Wolverine-style release, for free). |
| `HandleAsync` and DLQ replay | The id is assigned before enqueueing (and stored with the dead letter), so queue redelivery and replay are deduplicated. A client-supplied id is no longer required; the caller supplies one only to make its *own* retries safe. |
| Retention | **None. Dedup is forever**: the events are permanent, so a command id that applied to a stream never applies to it again. |
| PM process events (pass 13, revised in pass 14) | A PM takes facts only (decision 14.31, superseding 13.2), so its events are a fact's events: `causation.command_id` is the fact's id, and they deduplicate on it like any fact's. A saga's fact for a PM takes its id from the reaction origin (`"angzarr-reaction:"` + the reaction name), so a saga re-run is deduplicated too. There is no trigger lookup and no `triggering_event`. |
| Reactor re-runs (pass 13) | Same trigger, component and index give the same id, whatever the reactor's rules version, so a re-run always deduplicates. Repairs are new commands. See [Reactor re-runs](#reactor-re-runs). |

### Accepted costs

These are the user's, and they are deliberate:
- **Zero-event decisions are re-decided.** A decision that emitted nothing
  leaves nothing to find, so a redelivery decides again, against the state
  as it is then. This is Equinox's behaviour. The re-decision is correct
  against the current state, but it is not deduplicated. (Review finding
  W2 raised exactly this against an earlier design. Pass 5 answered it with
  claims; pass 12 accepts it.)
- **A reused id with a different payload goes undetected.** Without a
  fingerprint, a client that sends a new command under an old id is
  answered DUPLICATE with the old command's events. A fact source that
  re-sends one `external_id` with a changed payload is treated the same
  way. Clients must mint a new id for every new command.
- **Dedup is forever.** No expiry, no purge and no retention window. The
  index grows with the events, not faster.

### Alignments

- **Message id = command id; correlation and causation as metadata**:
  KurrentDB (`$correlationId`, `$causationId`, event ids), NServiceBus and
  MassTransit (message id, conversation and correlation ids), and Marten's
  causation and correlation metadata. Since pass 13 an event's causation
  is its direct cause only (its command, or a process event's trigger); a
  reaction command's trigger stays on the command and in traces, as in
  Marten and Wolverine (decision 13.3).
- **Deduplication on the stream, no separate store**: KurrentDB's
  idempotent appends (event ids) and Equinox (processed ids in the stream,
  zero-event decisions re-decided).
- **Release on failure**: Wolverine and the NServiceBus rollback. A
  rejection writes nothing.
- **No command log**: the events are the record, which honours the user's
  lean against storing commands.

### Divergences, and why

- **No payload check** (Stripe and the IETF draft detect a changed payload
  under a reused key). That would need a stored fingerprint, and so a store.
  The user judged misuse detection not worth one.
- **No retention** (Stripe keeps keys for 24 hours, NServiceBus for 7 days).
  The ids are on permanent events, so dedup is permanent, at no extra cost.
- **Derived ids for reactions and facts.** KurrentDB and the inboxes use
  whatever id the message carries. angzarr derives reaction and fact ids,
  so a redelivery reproduces the id without anyone storing it. The
  transient outbox re-sends verbatim regardless.
- **Dedup is per stream, not per endpoint.** The id is found where the
  events are.

### Still open

- **Repeated parks.** A parked fact writes nothing, so a webhook that keeps
  redelivering a fact whose ingest fails produces a dead-letter entry per
  attempt, unless the DLQ deduplicates entries per command id (backlog
  CI-8).

## Reactor re-runs

Decided in pass 13 (decision 13.4; review finding T8).

**What deduplicates.** A reaction command's id is UUIDv5 of (trigger,
component, index) and nothing else: not the reactor's `rules_version`, not
its code. A reactor run again over a trigger it already handled (a
checkpoint reset) emits the same ids, so every destination answers
DUPLICATE with the events the first run produced; a saga's facts for a
process manager reproduce their reaction origin, so the PM answers
DUPLICATE too (decision 14.31). This holds
even if the reactor's code changed in between and would now emit different
commands: that is the "reused id with a different payload" cost, applied to
reactions, and it is deliberate.

**History is never lost.** A re-run adds nothing where the first run
applied; it never overwrites, deletes or re-sequences an event. The
buggy-era events stay where they are, append-only.

**Checkpoint resets are for recovery only**: re-delivering triggers whose
output never reached the outbox. They are not a repair tool.

**Repairs are new commands.** To fix what a buggy reactor did, issue NEW
commands, with new command ids, that make the corrections (or re-drive the
fixed reactor over the affected triggers). Their ids are new, so they
apply, and their events append after the buggy-era ones, with later
sequence numbers; projections and readers see the correction as what it
is. The framework will ship standard re-drive commands for this (backlog
RD-1); until then they are ordinary client commands.

**Considered and dropped**: a per-reactor switch putting `rules_version`
into the derivation, so a re-run after a version bump would apply. It made
toggling the switch or bumping a version silently change every later id,
and turned a reset into an unrecorded repair.

The developer guide's "Re-running reactors" section
([state-and-conflicts.md](../../guide/state-and-conflicts.md)) gives the
procedure and the risks.

## Superseded: the key-store design (passes 5–10)

For the record, the design pass 12 replaced: a storage-only
`IdempotencyClaim` per (stream, key), written in the append's transaction
for applied outcomes only. The keys were `request_id` (client-supplied
only), the causation tuple, or `external_id`. Each claim held a v5
fingerprint of the payload (a mismatch was refused, or for facts optionally
answered DUPLICATE), and retention was 24 hours (requests) or 7 days
(causation and facts). DLQ replay refused entries older than their key's
retention unless overridden, and backends without atomic claims offered no
`HandleAsync` or replay. Decisions 5.1–5.5, 5.19 and 10.1–10.4 record it.
Decision 12.2 records why it went.

## annals

annals deduplicates the same way: by `command_id` on its events, with the
same derivations (through `angzarr_proto::ids`). Its `record_command` port,
its claims and its fingerprints are gone, and so is the fact-mismatch
setting. It is in-process and atomic, so redelivery inside it cannot
happen. The derived fact id covers webhook redeliveries, and a
client-supplied command id covers HTTP retries. See
[annals-divergence.md](annals-divergence.md).
