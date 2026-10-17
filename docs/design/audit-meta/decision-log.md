# Audit-meta decision log (passes 1–5)

Part of the [audit-meta design record](../audit-meta-followups.md).

Each entry gives the decision, why it was made, the cost accepted with it,
and the established practice it aligns with (or knowingly diverges from).
The yardstick for every pass: be consistent with established CQRS/ES
frameworks, and diverge only for polyglot ease or to hide CQRS/ES complexity
from business code.

Claims about other frameworks come from knowledge unless marked otherwise.
They were not re-verified against each framework's current documentation for
this note. Three of them were wrong in earlier passes; the
[corrections](#corrections) section records them.

Only the protos and the `rust/angzarr-proto` crate changed in these passes.
Every code consequence is in the [backlog](backlog.md).

## Pass 1 (9cfed59, 17bc1cd): provenance, sequences, one command per book

**1.1 Every persisted event carries `EventMeta`.** The fields are
`Provenance` (actor, correlation), the origin (request, causation or fact),
`recorded_at`, the base sequence, and `rules_version`.
- Why: any event must be explainable after the fact: who caused it, why, when,
  against what state and under which rules.
- Cost: bytes on every event, and stamping work in every coordinator.
- Aligns with: event metadata in Marten (correlation and causation ids,
  headers), Axon `MetaData`, the KurrentDB `$correlationId`/`$causationId`
  metadata convention, and CloudEvents context attributes.

**1.2 Sequences are `uint64` everywhere.**
- Why: a stream's sequence space is not bounded at 2^32.
- Cost: a WIRE_JSON break, plus code changes in six client languages and every
  storage backend.
- Aligns with: KurrentDB stream revisions (u64) and Marten's `long` versions.

**1.3 Correlation is recorded per page, never on the `Cover`.**
`Query.correlation_id` selects by it, and one write has one correlation.
- Why: a cover is stream identity. Correlation varies per write.
- Cost: core reads correlation from the cover in many places.
- Aligns with: correlation as message metadata (NServiceBus, MassTransit,
  KurrentDB), not stream identity.

**1.4 A `CommandBook` holds exactly one command.**
- Why: deduplication and the outcome are per command. Core already ran only
  the first page and silently ignored the rest.
- Cost: no wire batching. A client library may batch calls.
- Aligns with: Axon, Marten/Wolverine and Eventuous, which all dispatch one
  command at a time.

**1.5 The expected sequence is optional.** When it is present it is checked;
when it is absent the head is stamped. Both happen before business code, and
the base the decision used is always recorded.
- Why: decide always sees a concrete sequence, and the record always says
  what the decision saw.
- Cost: coordinator work on every command.
- Aligns with: expected-version appends in Marten, Eventuous, Equinox and
  KurrentDB, and the Decider pattern.

**1.6 Deferred sequences are deleted.** `EventPage.sequence` is always
definite.
- Why: deferred types existed only for facts and 2PC, and both are gone.
- Cost: none beyond deleting code.

**1.7 Facts are commands.** A fact is an external-only command, idempotent on
`external_id`, handled by an infallible ingest handler. A failing ingest is a
bug: it is dead-lettered, never rejected.
- Why: one input path into an aggregate. The framework deduplicates before
  business code, and the type system enforces "facts can't be rejected"
  (`ingest` has no error arm).
- Cost: facts share the command pipeline and its configuration.
- Aligns with: **Equinox ingesters**, which feed external sources into
  streams idempotently, and the Wolverine/NServiceBus inbox. *Correction:*
  pass 1 claimed this matched Event Modeling's translation pattern. It does
  not (see [C1](#corrections)).

**1.8 Only two conflict strategies: `STRICT` (the default) and
`AGGREGATE_HANDLES`.** `COMMUTATIVE`, `MANUAL` and the `Replay` RPC are
deleted. Conflict-resolution helpers live in the client libraries.
- Why: the other strategies hid business decisions inside the framework.
- Cost: users of `COMMUTATIVE` move the rule into decide.
- Aligns with: optimistic concurrency, and Axon's `ConflictResolver`, where
  the handler sees the unseen events.

**1.9 `Cover.ext` is removed.** Parent references live in event payloads,
and sagas route from payloads.
- Why: a cover is identity only.
- Cost: storage `ext` columns, router stamping, about 60 core sites, Python's
  `unpack_parent_cover`, and the poker protos.

**1.10 No `reserved` statements.** Removed fields and messages are deleted
outright.
- Why: nothing has been released, and stored data is wiped across schema
  changes.
- Cost: old binaries mis-decode new data. This is accepted until v0.1.0.
- Diverges from: protobuf's own guidance, deliberately, while pre-freeze.

**1.11 Editions stay in wire identity, and the main timeline is `""`.**
`Cover.edition` and `EventRef.stream.edition` carry it, and
`DeleteEditionEvents` refuses `""`.
- Why: an edition's events can never be mistaken for, or copied as,
  main-timeline events. Placement is a storage choice.
- Cost: the edition column stays in every schema.

**1.12 `rust/angzarr-proto` is a leaf crate.** It is prost only (no tonic,
no `google.api`) and builds for wasm32.
- Why: annals and hatpick share the wire types without pulling in angzarr's
  runtime.
- Cost: a fourth Rust generation of the same types, until core, the router
  and client-rust remap onto it (backlog TG-1).

## Pass 2 (46404df): removals and DRY

**2.1 `CASCADE`, `ISOLATED` and the cascade error modes are deleted.**
Reactions always run asynchronously.
- Why: synchronous cascades coupled aggregates' availability and hid
  partial failure.
- Cost: replay, migration and recovery tooling cannot write silently. It must
  let reactions run, or rebuild projections afterwards.
- Aligns with: Axon, Marten/Wolverine and NServiceBus, where reactions are
  asynchronous messages.

**2.2 The compensation and notification channel is deleted.** In its place,
process managers handle replies, and refusals are domain events.
- Why: a refusal is a business fact and belongs in a stream. A side channel
  duplicated the saga mechanism.
- Cost: compensating flows are re-modelled as refusal events plus a saga or
  PM.
- Aligns with: event-driven choreography, where a refusal is an event (as in
  Event Modeling and Axon sagas reacting to events).

**2.3 `undoes`/`compensates` annotations are removed.** This follows from
2.2.

**2.4 Speculative execution is replaced by editions.** A what-if is an
ordinary command in an edition. An unconfigured edition falls back to the
configured default edition store, and projector output follows the edition's
storage.
- Why: one execution path. A what-if needs no special RPCs.
- Cost: edition lifetime and multi-instance affinity are still open (see the
  open questions in the [index](../audit-meta-followups.md)).

**2.5 Snapshots are framework policy only.** `SnapshotRetention` is deleted.
The default keeps the newest snapshot, and business milestones are events.
- Why: a snapshot is an optimisation, not data.
- Cost: users of `PERSIST` re-model milestones as events, and as-of queries
  are slower where old snapshots used to exist.
- Aligns with: Marten, Axon and Eventuous, where snapshots are caches.

**2.6 `PayloadReference` is transport-only.** It belongs on a bus envelope,
never on a persisted page.
- Why: the event store records resolved payloads.
- Aligns with: the claim-check pattern (Enterprise Integration Patterns).

**2.7 The DRY refactor.** `EventRef { Cover stream; sequence }`, a shared
`Provenance`, and `Cover.edition` as a name. `EventPage.created_at` is
deleted, so `recorded_at` is the event's only timestamp.

**2.8 `CommandPage.body` is `oneof { Command, Fact }`, with each kind's
origin inside its arm.** Dispatch is reflective: the arm picks the pipeline,
and the type URL picks the handler. `ReactionOrigin` is renamed `Causation`.
- Why: the arm is the fact marker, so a fact structurally cannot carry a
  causation origin.
- Cost: regenerated clients.

**2.9 The dedup signal is an enum, never persisted** (now
`Outcome.delivery`).

## Pass 3 (9ded171): handling separated from data

**3.1 `Handling { optional expected_sequence; merge }` lives on
`CommandBook`.** The coordinator resolves it in place before business code,
and it is never persisted.
- Why: commands cross boundaries as bare books (saga and PM output, the DLQ,
  `ContextualCommand`), so the request envelope cannot carry handling.
- Aligns with: Marten/Eventuous/Axon, where the expected version travels with
  the command.

**3.2 Request wrappers are deleted.** These are `CommandRequest`,
`ContextualCommandRequest`, `SagaHandleRequest` and
`ProcessManagerCoordinatorRequest`.

**3.3 Defaults come from configuration.** Precedence: Handling, then
command-type config, then component config, then STRICT.
- Why: operators set policy, and a caller may override it only where
  configuration allows.

**3.4 Violations are refused loudly.** A client is answered
`INVALID_ARGUMENT`. A reaction command is dead-lettered as a bug. Reaction
commands carry no `Handling`.

## Pass 4 (8a803c9): sync is a call-level choice

**4.1 One RPC per mode.** `Handle` is DECISION, `HandleAsync` is ASYNC (it
returns `Empty`), and `HandleSync` is SIMPLE. `SyncMode` and `EventRequest`
are deleted.
- Why: how long the caller waits is not a property of the command.
- Aligns with: Google AIP-style method naming, and the gRPC convention of one
  method per response shape.

**4.2 DLQ replay delivers through `HandleAsync`.** Replay already rides the
bus, and its response carries no decision.

## Pass 5 (this change): the critical review's fixes

The review's findings are in [critical-review.md](critical-review.md). The
idempotency research and design are in [idempotency.md](idempotency.md).

**5.1 Idempotency key store (claims).** Keys are `request_id`+index, the
causation tuple, and the fact's `external_id`. They are scoped per addressed
aggregate, and a claim is written in the same transaction as the append. The
outcome is an applied sequence range, and zero events is allowed. Concurrency
is optimistic. A duplicate re-reads its events by range.
- Why: `HandleAsync` and DLQ replay deliver at least once, and request-origin
  commands had no deduplication at all (W1).
- Cost: a store. A backend without atomic claims cannot offer `HandleAsync`
  or replay.
- Aligns with: Stripe and the IETF Idempotency-Key draft (client keys, a
  fingerprint, 24-hour retention), and the NServiceBus outbox (atomic with
  business data, 7-day retention). Divergences are in
  [idempotency.md](idempotency.md).

**5.2 Rejections are released, not claimed** (Wolverine-style).
- Why: a rejected command wrote nothing, so a retry after the state changes
  must be able to succeed.
- Cost: a retried rejection runs business code again.
- Aligns with: Wolverine, AWS Powertools (which deletes the record when the
  handler throws) and the NServiceBus outbox (rollback). Diverges from Stripe,
  which stores error results.

**5.3 Payload fingerprint.** It is computed over the bytes as received. SDKs
serialise deterministically. A request key that comes back with a different
fingerprint is refused `FAILED_PRECONDITION`.
- Why: a reused key with a different body is a client bug, never a duplicate.
- Aligns with: Stripe, which errors on changed parameters, and the IETF draft
  (422).

**5.4 Retention is 24 hours for client keys and 7 days for causation and
fact keys.** DLQ replay refuses entries older than their key's retention
unless overridden.
- Aligns with: Stripe (24 hours) and the NServiceBus outbox's default
  deduplication window (7 days).

**5.5 `request_id` is required for `HandleAsync` and DLQ replay.**

**5.6 A transient outbox for all reactors.** Output is stored atomically with
the source checkpoint, dispatched, then cleared, so that only keys remain.
Redelivery re-sends verbatim. There is no purity contract and no
nondeterminism dead-letter.
- Why: without it, a reactor re-run can emit different commands under the
  same causation keys (W2). The user was wary of purity contracts: only
  workflow engines require determinism.
- Cost: an outbox write per reaction.
- Aligns with: the NServiceBus outbox, MassTransit's transactional outbox and
  Wolverine's durable outbox. Diverges from Temporal-style deterministic
  replay, deliberately.

**5.7 The coordinator stamps reaction provenance (W4, W5).** Actor and
correlation are copied from the trigger, and a reactor that sets differing
values is refused. Correlation is never empty: it is the caller's value, or
it is derived from `request_id` (or `external_id`). A keyless request gets a
newly minted correlation (pass-5 choice).
- Aligns with: correlation propagation in NServiceBus, MassTransit and the
  KurrentDB conventions.

**5.8 Business output is payloads plus an optional snapshot (W7).** Setting
meta, a sequence or a different cover is refused. The "custom covers" escape
hatch is removed from `CommandOptions.emits`.
- Pass-5 choice: a caller of `Handle`/`HandleSync` is answered `INTERNAL`,
  and asynchronous and reaction paths dead-letter. It is never a business
  rejection.

**5.9 `rules_version` is declared at registration and stamped by the
coordinator (W8).**
- Pass-5 choice: it is declared on `ComponentDescriptor.rules_version` (field
  4). That is the runtime self-description a component gives when it
  registers, and the rules version changes per deployment, not per proto.
  `ComponentOptions` in `options.proto` is a compile-time annotation and the
  wrong lifetime.
- annals treats the value as load-bearing; see
  [annals-divergence.md](annals-divergence.md).

**5.10 Non-main editions never reach external sinks, and the edition is in
the default CloudEvent id and source (W10).**
- Pass-5 choice: the id is `{domain}:{edition}:{root}:{sequence}` (main gives
  `{domain}::{root}:{sequence}`). The source is `angzarr/{domain}` on main and
  `angzarr/{domain}/editions/{edition}` otherwise.

**5.11 HandleSync answers OK, with per-projector failures in the `Outcome`
(W11).** It adds `Outcome.projector_failures` and `ProjectorFailure
{ projector, code, message }`.

**5.12 A failed fact ingest is answered "accepted, parked" (W11).**
- Pass-5 choice: a new value, `DeliveryOutcome.DELIVERY_OUTCOME_PARKED` (3),
  rather than an `Outcome` field. The delivery outcome already answers "what
  happened to this delivery", and PARKED excludes APPLIED and DUPLICATE. A
  separate boolean could contradict it. A parked fact is not claimed.

**5.13 One set of retryable status codes (W11).**
- Pass-5 choice: `UNAVAILABLE`, `DEADLINE_EXCEEDED`, `RESOURCE_EXHAUSTED` and
  `ABORTED` are retryable. Everything else is terminal.
- A stale expected sequence under STRICT moves from `FAILED_PRECONDITION` to
  `ABORTED`, which gRPC's status-code guide names for a failed test-and-set.
  That frees `FAILED_PRECONDITION` for business rejections and fingerprint
  mismatches, so nothing has to parse messages.
- Cost: core retries `INTERNAL`, `UNKNOWN`, `DATA_LOSS` and `CANCELLED`
  today, and detects sequence conflicts by a message prefix. Backends must map
  transient faults to `UNAVAILABLE` (backlog ST-1).

**5.14 Under AGGREGATE_HANDLES the snapshot delivered is at or below
`expected_sequence-1` (W12).** The conflict window always arrives as pages.

**5.15 `recorded_at` is non-decreasing per stream, and `as_of_time` is a
prefix (W13).** The coordinator stamps max(previous, now).
- Aligns with: KurrentDB's and Marten's per-stream ordering.

**5.16 Renames (W14).** `EventMeta.decided_at` becomes `base_sequence`, and
the projector coordinator's fire-and-forget `Handle` becomes `HandleAsync`
(HTTP `/v1/projector/async`).
- Why: `decided_at` read as a time but holds a sequence, and the mode names
  should match the command coordinator's.

**5.17 PM replies route by correlation, and causation always names the
triggering event (W6).** The process_manager.proto text that said a reply's
causation "names the PM's own event" was wrong.

**5.18 A DLQ replay keeps the original provenance, origin and keys (W9).**
The replay's operator, time, mode, retention override and outcome are
recorded in the entry. An event-book replay re-delivers to the failed
component only.
- Pass-5 choice: the audit fields are on the admin row,
  `StoredDeadLetter.replays` (a list of `DeadLetterReplay` with a
  `ReplayOutcome`). They are not on `AngzarrDeadLetter`, because the
  published entry stays immutable and its bytes are what replay re-sends.
  `ReplayDeadLetterOk.new_correlation_id` becomes `correlation_id` (the
  original), and `ReplayDeadLetterRequest.override_retention` is added. The
  operator comes from the call's credentials, never from the request body.

**5.19 `IdempotencyClaim` is a storage-only documented schema.**
- Pass-5 choice: add it. It pins the key union, scope, fingerprint, range and
  expiry in one typed place that every backend (and annals' optional unique
  index) can match. It reuses the origin messages as the key, so the key
  cannot drift from the wire.
- Cost: a message that no RPC carries, which is labelled storage-only.

**5.20 annals keeps its atomic in-process chain** as a documented,
intentional divergence. See [annals-divergence.md](annals-divergence.md).

**5.21 Scope: protos and documentation only.** No angzarr code changes now.
The user is not taking on heavy refactoring, and everything is recorded in
the [backlog](backlog.md).

## Corrections

Facts the earlier passes or the design note got wrong:

- **C1. Facts-as-commands is not Event Modeling's translation pattern.**
  Event Modeling's translation brings external information in as events,
  read through views by a translator that then issues commands. The real
  analogue for "external facts ingested idempotently into a stream" is
  **Equinox's ingesters**, together with the inbox pattern in Wolverine and
  NServiceBus. (Plan item 4 and decision 1.7 originally cited Event
  Modeling.)
- **C2. KurrentDB has `MultiStreamAppend`** (25.1 and later). Known gap 8
  previously said KurrentDB has "no multi-stream transactions". The
  comparison is corrected in the [backlog](backlog.md)
  (GAP-2).
- **C3. Axon has no "decision commands" versus "notification commands"
  distinction.** Its command handlers are uniform. The site page
  `components/commands-vs-facts.md` claims otherwise, and must lose that
  section (backlog DOC-3).
