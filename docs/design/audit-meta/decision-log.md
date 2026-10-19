# Audit-meta decision log (passes 1–14)

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

> **Amended by 12.4 (pass 12):** `EventMeta` is now `command_id`, `causation_id`, `fact`, `correlation_id`, `recorded_at` and `rules_version`; no actor, no origin, no base sequence.
>
> **Amended by 13.1 and 13.3 (pass 13):** `EventMeta` is now `oneof causation { command_id 17 | triggering_event 18 }`, `fact`, `correlation_id`, `recorded_at` and `rules_version`; `causation_id` is no longer on events.

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
- **Partly reversed in pass 6** (decision 6.12): `COMMUTATIVE` is back, as an
  opt-in resolver in the client libraries, never a coordinator-side diff or a
  `Replay` RPC. `MANUAL` stays deleted.

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
- **Superseded in pass 6** (decision 6.6, D6): reserve from the first stored
  production event onwards. Deletions up to and including pass 6 stay
  unreserved.

**1.11 Editions stay in wire identity, and the main timeline is `""`.**
`Cover.edition` and `EventRef.stream.edition` carry it, and
`DeleteEditionEvents` refuses `""`. (Pass 6 replaced `DeleteEditionEvents`
with the administrative `DeleteEdition`, which also refuses `""`; decision
6.5.)
- Why: an edition's events can never be mistaken for, or copied as,
  main-timeline events. Placement is a storage choice.
- Cost: the edition column stays in every schema.
- **Superseded in pass 7** (decision 7.1): editions stay in wire identity,
  but main is the **unset** edition (`optional string edition`), not `""`.

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
- **Origins revised in pass 6** (decision 6.1, D1): the arms stay, but the
  per-arm origins (`Command.origin`, `Fact.source`) moved to one shared
  `Origin` on the page, and "a fact cannot carry a causation origin" is now a
  validation rule rather than a structural one.

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

## Pass 5 (b5a4da8): the critical review's fixes

The review's findings are in [critical-review.md](critical-review.md). The
idempotency research and design are in [idempotency.md](idempotency.md).

> **Superseded by 12.2 (pass 12):** no key store; deduplication is by `command_id` on the events.

**5.1 Idempotency key store (claims).** Keys are `request_id`+index, the
causation tuple, and the fact's `external_id`. (Superseded by 10.1: a
request key is `request_id` alone.) They are scoped per addressed
aggregate, and a claim is written in the same transaction as the append. The
outcome is an applied sequence range, and zero events is allowed. Concurrency
is optimistic. A duplicate re-reads its events by range.
- Why: `HandleAsync` and DLQ replay deliver at least once, and request-origin
  commands had no deduplication at all (W1). Dedup inferred from event rows
  left no claim for a decision that emitted no events (W2).
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

> **Superseded by 12.2 (pass 12):** no fingerprint; a reused id with a different payload goes undetected (an accepted cost).

**5.3 Payload fingerprint.** It is computed over the bytes as received. SDKs
serialise deterministically. A request key that comes back with a different
fingerprint is refused `FAILED_PRECONDITION`. (Extended by 10.2 to fact
keys, by default, and by 10.4 to causation keys, always dead-lettered;
the fingerprint's exact form is 10.3.)
- Why: a reused key with a different body is a client bug, never a duplicate.
- Aligns with: Stripe, which errors on changed parameters, and the IETF draft
  (422).

> **Superseded by 12.2 (pass 12):** deduplication is forever; no retention, and no DLQ age refusal.

**5.4 Retention is 24 hours for client keys and 7 days for causation and
fact keys.** DLQ replay refuses entries older than their key's retention
unless overridden.
- Aligns with: Stripe (24 hours) and the NServiceBus outbox's default
  deduplication window (7 days).

> **Superseded by 12.2 (pass 12):** every command has a `command_id` before it is enqueued, so neither path requires a client-supplied one.

**5.5 `request_id` is required for `HandleAsync` and DLQ replay.**

**5.6 A transient outbox for all reactors.** Output is stored atomically with
the source checkpoint, dispatched, then cleared, so that only keys remain.
Redelivery re-sends verbatim. There is no purity contract and no
nondeterminism dead-letter.
- Why: without it, a reactor re-run can emit different commands under the
  same causation keys (W3). The user was wary of purity contracts: only
  workflow engines require determinism.
- Cost: an outbox write per reaction.
- Aligns with: the NServiceBus outbox, MassTransit's transactional outbox and
  Wolverine's durable outbox. Diverges from Temporal-style deterministic
  replay, deliberately.

> **Superseded in part by 12.1 and 12.3 (pass 12):** no actor exists to stamp. Correlation is still copied from the trigger, and the coordinator now also stamps `causation_id` and the derived `command_id`.

**5.7 The coordinator stamps reaction provenance (W4, W5).** Actor and
correlation are copied from the trigger, and a reactor that sets differing
values is refused. Correlation is never empty: it is the caller's value, or
it is derived from `request_id` (or `external_id`). A keyless request gets a
newly minted correlation (pass-5 choice; superseded by 8.3: request ids are
always assigned, so the derivation is the request id verbatim and nothing
mints a correlation).
- Aligns with: correlation propagation in NServiceBus, MassTransit and the
  KurrentDB conventions.

**5.8 Business output is payloads plus an optional snapshot (W7).** Setting
meta, a sequence or a different cover is refused. The "custom covers" escape
hatch is removed from `CommandOptions.emits`.
- Pass-5 choice: a caller of `Handle`/`HandleSync` is answered `INTERNAL`,
  and asynchronous and reaction paths dead-letter. It is never a business
  rejection.

> **Superseded by 12.6 (pass 12):** the business logic reports `rules_version` with every response; `ComponentDescriptor.rules_version` is deleted.

> **Partly restored by 14.1 (pass 14):** `ComponentDescriptor.rules_version` is back, as the binary's full build version, alongside the per-response report.

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
- **Amended in pass 7** (decision 7.1): main has no edition segment, so its
  id is `{domain}:{root}:{sequence}`; the source rule is unchanged.

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

> **Superseded in part by 12.4 (pass 12):** `base_sequence` is deleted (the projector rename stands).

**5.16 Renames (W14).** `EventMeta.decided_at` becomes `base_sequence`, and
the projector coordinator's fire-and-forget `Handle` becomes `HandleAsync`
(HTTP `/v1/projector/async`).
- Why: `decided_at` read as a time but holds a sequence, and the mode names
  should match the command coordinator's.

**5.17 PM replies route by correlation, and causation always names the
triggering event (W6).** The process_manager.proto text that said a reply's
causation "names the PM's own event" was wrong.

> **Amended by 12.2 and 12.3 (pass 12):** a replay keeps the original `command_id`, `correlation_id` and `causation_id`; the operator and `retention_overridden` are deleted (who replayed goes to the security log), and so is `override_retention`.

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

> **Superseded by 12.2 (pass 12):** `IdempotencyClaim` is deleted.

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

## Pass 6 (650d774): the debatable items decided

The user decided the review's D1–D11 (see
[critical-review.md](critical-review.md)) before this pass, and added the
restoration of `COMMUTATIVE` during it. As before, only the protos, the
`rust/angzarr-proto` crate and these documents changed. Wire breaks are
accepted, and this round's deletions stay unreserved (6.6).

> **Superseded by 12.1 (pass 12):** `Origin`, `RequestOrigin` and `Causation` are deleted; the page carries `command_id`, `correlation_id`, `causation_id` and `fact_origin`. The `Command`/`Fact` arms stay.

**6.1 One `Origin` message (D1).** `Origin { oneof kind { RequestOrigin
request; Causation causation; FactOrigin fact; } }` is the only origin
shape. It is on the command page (`CommandPage.origin`, field 7), copied
unchanged onto every event (`EventMeta.origin`, field 12, replacing the
inline oneof), and is the idempotency key (`IdempotencyClaim.key`, field 10,
replacing its inline oneof). `Command.origin` and `Fact.source` are
deleted.
- Validation: a Fact requires a fact origin (with a non-empty
  `external_id`); a Command requires a request or causation origin, and a
  Command sent with no origin is a keyless request (recorded as an empty
  `RequestOrigin`, so `EventMeta.origin` is always set). A mismatch is
  refused loudly: `INVALID_ARGUMENT` for a client, dead-letter and alert for
  a reactor.
- **Pass-6 choice: the `Command`/`Fact` arms stay**, each now holding only
  its payload. The arm still carries the payload's kind (a decision request
  or an already-happened fact) and drives reflective dispatch (decide or
  ingest), and generated code and the router's arm-versus-handler guard key
  on it. The origin says why the command exists; the arm says what it is.
  Collapsing to one `payload` plus the origin would make the origin double
  as the dispatch marker, which is the conflation D1 set out to remove.
- Why: the union was stated three times, splitting provenance across page
  and arm and needing mapping code in every language.
- Cost: "a fact cannot carry a causation" is no longer structural: it is a
  coordinator check (backlog OR-1).
- Aligns with: correlation and causation as message metadata, separate from
  the message body (NServiceBus headers, Marten metadata).

**6.2 No root-request pointer (D2).** Correlation is enough: every event of
a workflow carries the originating correlation, and `GetCorrelatedEvents`
(6.4) returns the workflow. A reaction's events keep only their causation.
annals' request-on-every-event is a documented divergence, or annals drops
it (see [annals-divergence.md](annals-divergence.md)).
- Aligns with: correlation as the workflow id (NServiceBus
  `ConversationId`), without MassTransit's separate `InitiatorId`.

**6.3 An optional attempt-audit sink (D3).** Attempts and their outcomes
(rejections included) are reported to an optional observability sink, never
to the event store. Only the interface and in-memory and no-op
implementations are planned; they are angzarr core code, held until the user
says when. The interface specification is backlog AU-1. No proto changed.
- Why: a rejection leaves nothing in any stream, and an operator sometimes
  needs to see what was tried.
- Aligns with: the NServiceBus audit queue, kept outside the business
  store.

> **Amended by 13.3 (pass 13):** forward causation from the result is exact only for PM process events (`triggering_event`); reaction commands' events are linked by correlation, and exact trigger edges come from traces.

**6.4 A cross-domain correlation query (D4).** `EventQueryService.
GetCorrelatedEvents(CorrelationQuery { correlation_id, edition })` streams
one `EventBook` per stream holding its pages of that correlation, across all
domains. `Query.correlation_id` stays within one domain.
- Forward causation is derived, not queried: reaction provenance copies the
  trigger's correlation, so the result is closed under "what did this event
  cause". The events caused by E are the result pages whose
  `EventMeta.origin.causation.event` equals E's `EventRef`.
- Backend indexes (a correlation index per backend) are backlog CQ-1.
- Aligns with: KurrentDB's `$by_correlation_id` system projection.

**6.5 Editions need an explicit, administrative create (D5).** A new
`EditionAdminService` in `meta.proto` has `CreateEdition` and
`DeleteEdition`. They are administrative operations: no domain command, no
event, no replay.
- `CreateEditionRequest { name, diverge_at, store }` records the divergence
  point (a time: the edition reads main's prefix recorded at or before it;
  the default is main's head at create) and an optional non-default edition
  store. The record is `Edition { name, diverged_at, store, created_at,
  created_by }`.
- A created edition with no store uses the default edition store (its name
  is recorded at create, so a later change of the default does not move
  it). A never-created name used by a command, query or subscription is
  refused `NOT_FOUND`.
- `DeleteEdition` deletes the record and everything stored under the
  edition in every domain (events, snapshots, projector output, claims). It
  refuses `""` (`INVALID_ARGUMENT`) and an unknown name (`NOT_FOUND`).
  (Pass 7, decision 7.1: main is unnamed, so the `""` rule reads "the name is
  required and non-empty"; the code is unchanged.)
- **Pass-6 choice: the RPCs live in a new `EditionAdminService` in
  `meta.proto`** (package `io.angzarr.v1`). `meta.proto` held
  `DeleteEditionEvents` with no service. The status console's
  `io.angzarr.status.v1` package is the operations console's own DLQ API,
  and editions are framework administration rather than a console concern.
  `meta.proto`'s "meta domain commands/events" framing is replaced by
  "administrative operations, not CQRS".
- **`DeleteEditionEvents` is retired.** It deleted one (edition, domain);
  `DeleteEdition` deletes the whole edition, and a per-domain delete has no
  user.
- Cost: what-if callers must create an edition first.

**6.6 Reserve from the first stored production event (D6).** Supersedes
1.10. Up to and including this pass, removed fields stay unreserved; from
the first production event any store keeps, every removal reserves its
number and name in the same change. The policy is written in
`proto/buf.yaml`. It ties to the gate-wire-compat trigger (backlog GAP-3).

**6.7 The AGGREGATE_HANDLES nonce (D7).** `ContextualCommand.conflict_nonce`
(bytes, field 3) is set when the resolved resolution is AGGREGATE_HANDLES or
COMMUTATIVE, and empty under STRICT. The client library passes it to the
handler and demands `resolve_conflicts(window, nonce)` with exactly that
value before the handler returns; otherwise it discards the output and fails
the command as stale (`ABORTED`).
- **Pass-6 choice: an opaque per-delivery value minted by the coordinator**,
  not `expected_sequence` itself. A handler cannot satisfy the check without
  receiving the parameter, which is the point. It is never persisted or
  returned, and the coordinator does not check it: enforcement is local to
  the client library, with no gRPC round trip.
- Set even for an empty window, so the handler path is uniform.
- Aligns with: Axon, which fails a command when conflicting events exist and
  the handler never examined them.

> **Amended by 12.6 (pass 12):** validity is checked in the client library, where the state is decoded, against the reported rules version; a refused snapshot is answered `snapshot_refused` and the coordinator re-delivers without it.

> **Amended by 14.1 (pass 14):** the coordinator checks validity before offering a snapshot, against the registered state type and the domain's version-compatibility rule; a snapshot that fails is not offered.

**6.8 Snapshots record what produced them (D8).** `Snapshot.rules_version`
(field 5; 4 was pass 2's retention field) is stamped by the framework, and
the state type is the `Any` type URL. On load, a mismatch with the current
registration (state type or `ComponentDescriptor.rules_version`) discards the
snapshot and replays from events.
- Cost: a deployment that changes `rules_version` replays every stream on its
  next load. That is the price of never migrating snapshots.
- Aligns with: snapshots as caches (Marten, Axon, Eventuous), invalidated
  rather than upcast.

**6.9 Cleanups (D9).**
- `AggregateRoot` is deleted; `GetAggregateRoots` streams `Cover`, which
  carries the edition.
- `ComponentKind` moves from `options.proto` to `types.proto`, and
  `options.proto` imports `types.proto` (no cycle: `types.proto` imports
  nothing from it). `ComponentDescriptor.component_type` becomes `kind`
  (field 5); `AngzarrDeadLetter.source_component_type` becomes
  `source_component_kind` (field 15); `StoredDeadLetter.source_component_type`
  becomes `source_component_kind` (field 14), so `dlq_admin.proto` imports
  `types.proto`.
- `AngzarrDeadLetter.cover` is dropped: the payload's cover is the stream.
- `Projection.sequence` becomes `next_sequence` (field 3 kept): it holds the
  stream's next_sequence after the projected events (client-rust sets it
  from `book.next_sequence`).
- **Pass-6 choice: `Synchronize` is deleted.** Core implements it as a
  bidirectional stream that answers each incoming `Query` with
  `GetEventBook`'s result. It never switches to live events, so it is not the
  catch-up subscription the site's `pitch.mdx` advertises. It skips the
  unary RPC's validation, is exposed through the gateway despite "not
  REST", and has no production caller (only core's own unit test). Bulk
  reads are `GetEvents`, and live events are `EventStreamService.Subscribe`.
  A real catch-up subscription, if wanted, is a new design, not this RPC.
- The edition admin RPCs (6.5).

**6.10 `MergeStrategy` becomes `ConflictResolution` (D10).** Values are
`CONFLICT_RESOLUTION_*` (lint-conformant), with numbers unchanged, and
`Handling.merge` becomes `Handling.conflict_resolution`. Cover, Book and Page
are kept.
- Aligns with: Axon's "conflict resolution".

**6.11 The fact codegen marker is resolved (D11).** Handler registration
(`#[handles_fact]` / ingest) is the declaration, and the router guards arm
against handler kind. There is no proto flag. `CommandPage`'s comment now
says so, matching the index and backlog FA-3.

> **Superseded in part by 12.7 (pass 12):** COMMUTATIVE is the DEFAULT where the state declares conflict units (otherwise STRICT); it is no longer opt-in only.

**6.12 `COMMUTATIVE` is restored, opt-in, in the client libraries (user,
during pass 6).** `CONFLICT_RESOLUTION_COMMUTATIVE = 1` (its old number).
- The window and the nonce are delivered exactly as under
  AGGREGATE_HANDLES, with the same snapshot bound (at or below
  `expected_sequence-1`). The client library compares, by protobuf
  reflection, the state fields the window changed with those the command's
  events change. If they are disjoint, the library acknowledges the nonce
  itself; otherwise the command fails as stale (`ABORTED`). There is no
  `Replay` RPC and no coordinator-side diff.
- Opt-in only: per command type or per component in configuration, or in
  `Handling` where configuration allows. STRICT stays the default.
- **Reverses part of 1.8**, which deleted `COMMUTATIVE` because it hid
  business decisions inside the framework. The reason for the reversal is
  goal 2: implementors should not have to write conflict logic for the
  common case of non-overlapping edits. Moving the resolver into the client
  library, behind an explicit opt-in, removes the earlier objections: the
  coordinator stays domain-blind, there is no replay RPC, and nothing is the
  default.
- Diverges from: every mainstream framework. None of Axon, Marten,
  Eventuous, KurrentDB or NServiceBus ships automatic field-overlap merging.
  It is justified by goal 2, and it is opt-in because a structural diff
  cannot see semantic links between fields: two commands that touch
  different fields can still break an invariant that spans them.
- The "protobuf reflection" diff was left unspecified here; pass 8 (8.1)
  replaces it with declared conflict units, and decide on the head (which
  keeps invariants checked).

## Pass 7: the main timeline is the unset edition

Decided by the user. As before, only the protos, the `rust/angzarr-proto`
crate and these documents changed, wire breaks are accepted, and nothing is
reserved: no field was removed, and the 6.6 policy (deletions unreserved
until the first stored production event) now covers passes up to and
including 7.

**7.1 Main is the absent edition, not `""` (supersedes 1.11's "main is
`""`").** `Cover.edition` becomes `optional string edition` (field 4
kept), so `EventRef.stream` and every other nested `Cover` follow.
- **Unset means main.** A set edition is a named edition and must be
  non-empty: a set `""` is malformed and refused `INVALID_ARGUMENT`
  wherever a `Cover` is accepted. Explicit presence makes the two
  distinguishable on the wire.
- `CorrelationQuery.edition` becomes `optional string` with the same
  convention.
- `CreateEditionRequest.name` and `DeleteEditionRequest.name` stay plain
  strings, documented as required and non-empty. Main cannot be named to
  them at all, so `DeleteEdition`'s "refuses `""`" rule becomes "a name is
  required" (`INVALID_ARGUMENT` when empty), and `CreateEdition` likewise.
  They stay plain strings because `DeleteEdition`'s name is an HTTP path
  segment and neither RPC has a main case to express. `Edition.name` is
  always non-empty.
- CloudEvents: the default id is `{domain}:{root}:{sequence}` on main (no
  edition segment) and `{domain}:{edition}:{root}:{sequence}` on a named
  edition; three segments against at least four, since domains, roots and
  sequences never contain `:`. The source is unchanged: `angzarr/{domain}`
  on main and `angzarr/{domain}/editions/{edition}` otherwise.
- The example `TrainingProjection.edition` follows the same convention.
- Why: no magic value. `""` as main relied on proto3's implicit default, so
  "forgot to set it" and "meant main" were the same bytes, and the empty
  string had to be special-cased in every refusal rule and in the CloudEvent
  id (the old `{domain}::{root}:{sequence}`). With explicit presence, main is
  simply the absence of an edition, which is also how annals models it
  (`Option<EditionName>`, `None` = main), and a malformed `""` is caught
  instead of silently meaning main.
- Cost: every generated client sees a presence-tracked field (`Option` in
  Rust, a pointer in Go, `HasField` in Python, and so on), and core's edition
  handling and its CloudEvent id change (backlog ED-2, ED-3, EA-1). The
  storage representation of main (for example NULL in the edition column) is
  each backend's choice and never reaches the wire.
- Aligns with: protobuf's own guidance to use explicit presence when unset
  and empty must differ.

## Pass 8: conflict units, minted ids and always-assigned request ids

Decided by the user. As before, only the protos, the `rust/angzarr-proto`
crate and these documents changed, and nothing is reserved (the 6.6 policy
now covers passes up to and including 8; nothing was removed).

> **Amended by 12.7 and 12.8 (pass 12):** `bool commutative_state` is replaced by `StateOptions state = 50106`; `ConflictUnit` gains `whole_state = 4`. The unit rules are unchanged.

**8.1 COMMUTATIVE compares declared conflict units (replaces 6.12's
"reflection diff").** `options.proto` gains
`extend google.protobuf.MessageOptions { bool commutative_state = 50106; }`,
`extend google.protobuf.FieldOptions { ConflictUnit conflict = 50107; }` and
`message ConflictUnit { bool descend = 1; string element_key = 2; bool
ordered = 3; }`. A generated `changed(before, after)` returns a set of unit
paths:

| Field kind | Unit | Example path |
|---|---|---|
| scalar / string / bytes / enum | the field | `title` |
| optional scalar | the field; set↔unset is a change | `deadline` |
| message, not `descend` | the whole message (deep equality) | `settings` |
| message with `descend` | each marked inner field, recursively | `settings.cooldown_days` |
| map | one unit per key (added, removed or changed) | `items[42]` |
| map of messages with `descend` | per key, then per inner field | `items[42].weight` |
| repeated message with `element_key` | per element by key; plus `field[#order]` if `ordered` and the order changed | `columns[due]` |
| repeated message without `element_key` | the whole list | `columns` |
| repeated scalar | the whole list | `tags` |
| oneof | the whole oneof (a case switch or a value change) | `payment` |

- **Unmarked fields conflict with everything** (fail-safe): a changed
  unmarked field reports a wildcard unit (`*` + its path) that overlaps any
  non-empty set. An unmarked field can only make COMMUTATIVE stricter.
- **Floats compare bitwise** (IEEE 754 bits: NaN = NaN with equal bits, +0
  ≠ −0), so every language agrees.
- **Overlap** is equality or a path prefix at a `.`/`[` boundary, so every
  coarser fallback (a non-unique element key falls back to the whole list)
  stays sound.
- **Recursive `descend`** is allowed to a depth of 32 descended messages; at
  the bound the field is one whole-message unit (coarser, still sound).
- **Path syntax** is fixed for parity: proto field names, `.` joins, keys in
  brackets (decimal integers, `true`/`false`, enum numbers, string and bytes
  keys with `\`, `]` and `#` escaped by `\`), so `[#order]` never collides
  with a key.
- **The resolver**: `window = changed(state@expected, state@head)`; decide
  runs on head; `mine = changed(head, head + events)`. Disjoint: the library
  acknowledges the nonce. Otherwise `ABORTED`. **Invariants are checked on
  head**, so the residual risk is only a caller's intent that depended on a
  disjoint unit the window changed (read A, write B).
- **The resolver uses the current markers** (the code running decide);
  markers are never stored with events.
- **COMMUTATIVE requires `commutative_state`**; otherwise the command is
  malformed (`INVALID_ARGUMENT`, refused by the client library, which alone
  knows the state type) and such a configuration is refused at registration.
- **Extension numbers**: 50106 and 50107, after the existing 50100, 50104
  and 50105. 50101–50103 are skipped because deleted options used them and
  stale descriptors in old branches still carry them.
- **One protoc plugin generates `changed()` for every language**, plus a
  shared golden fixture parity suite (backlog CR-1). annals generates the
  same function from the same markers.
- Worked example: hatpick's `ListState { option commutative_state; map<string,
  Item> items [conflict]; repeated Column columns [conflict]; Settings
  settings [conflict] }` gives per-item units, one unit for the column list
  and one for the settings, which is hatpick's "touched" rule. (The fixture
  `rust/angzarr-proto/tests/fixtures/list_state.proto` carries it.)
- Why: "reflection diff" left granularity undefined per language, so seven
  client libraries and annals would each have invented one. Declared units
  make the merge rule part of the schema, reviewable and identical
  everywhere.
- Cost: a protoc plugin and golden suite to build (CR-1); state authors
  annotate fields.
- Aligns with: nothing directly (6.12's divergence stands). The unit model
  resembles CRDT-style per-key maps and JSON Merge Patch granularity, but is
  only a conflict detector: the merge is always "decide on head".

**8.2 Every framework-minted id is a UUIDv7 (RFC 9562).** Request ids,
anything an SDK mints for its caller (request ids, new roots), and (through
8.3) derived correlations. Canonical lowercase 36-character text in string
fields, 16 bytes in `UUID`. Client-supplied ids stay opaque strings that are
never parsed. (Superseded by 9.1: every UUID is the 16-byte `UUID`
message, and client request and correlation ids must be UUIDs.) The conflict nonce and the DLQ's int64 row ids are not
identifiers and are not covered. Documented as the `minted_ids` region of
`types.proto`.
- Why: time-ordered ids index and sort well, and one rule in both runtimes
  keeps annals and angzarr records alike.
- Aligns with: RFC 9562's recommendation of v7 for new time-ordered keys,
  and the same idea as Marten's sequential (comb) Guid ids.

> **Superseded by 12.1 (pass 12):** request ids become command ids, still always assigned (client-supplied or a minted v7), but `minted` is deleted and minted ids deduplicate like any other.

**8.3 Request ids are always assigned; only client-supplied ones
deduplicate.** A request without a `request_id` gets a minted v7 recorded in
its origin, so every command and event has a request id for audit.
`RequestOrigin` gains `bool minted = 3`: set only by the coordinator (a
client that sets it is malformed), recorded with the origin in `EventMeta`.
A minted id is never claimed, never fingerprinted and never deduplicates;
`HandleAsync` and DLQ replay still require a client-supplied one (empty or
minted is refused). Supersedes "refuse keyless" for annals too.
- **Representation chosen**: a bool on `RequestOrigin`, not a separate
  `minted_request_id` field. Alternatives: (a) a separate field, which would
  leave `request_id` empty on keyless requests and make every audit reader
  check two fields; (b) a prefix or other magic in the id string, which would
  break opacity of client ids. The bool keeps one field holding "the request
  id", costs zero bytes for the common client-keyed case (proto3 default
  false), and keeps `IdempotencyClaim.key` as the origin verbatim.
- **Correlation when absent** = the request id verbatim (always present now);
  for a fact, `external_id` verbatim; a causation is stamped from its
  trigger. No hashing and no name-based UUID (this supersedes backlog PS-3's
  earlier "name-based UUID" wording); nothing mints a correlation itself,
  so pass 5's "keyless request gets a freshly minted correlation" is
  unreachable and removed.
  (The fact half is superseded by 9.2: a fact's correlation is
  UUIDv5 of its `external_id`; request ids are UUIDs, so the request half
  is still verbatim.)
- Why: audit wants a request id everywhere; dedup must only trust keys the
  client will reproduce on retry.
- Cost: core, the clients and annals mint and record the id (backlog MI-1,
  MI-2); a wire field.
- Aligns with: request-id middleware convention (an `X-Request-Id` is
  generated when absent and logged), while Stripe-style dedup honours only
  the client's `Idempotency-Key`.

## Pass 9: one UUID type, v5 derived ids, text at the boundary

Decided by the user. As before, only the protos, the `rust/angzarr-proto`
crate and these documents changed, and nothing is reserved (the 6.6 policy
now covers passes up to and including 9; no field number was removed, four
fields changed type in place).

**9.1 Every UUID on the wire is the `UUID` message (16 bytes).** Supersedes
8.2's "canonical lowercase 36-character text in string fields" and its
"client-supplied ids stay opaque strings that are never parsed", and the
string request and correlation ids of passes 1–8. Fields changed from
`string` to `UUID`:
- `RequestOrigin.request_id` (1)
- `Provenance.correlation_id` (2)
- `Query.correlation_id` (6)
- `CorrelationQuery.correlation_id` (1)
- `EventStreamFilter.correlation_id` (1)
- `io.angzarr.status.v1.StoredDeadLetter.correlation_id` (3)
- `io.angzarr.status.v1.ReplayDeadLetterOk.correlation_id` (1)

The REST routes that put a correlation in the path now name its bytes:
`/v1/stream/{correlation_id.value}` and
`/v1/query/correlations/{correlation_id.value}/events`.
`buf breaking` against pass 8 reports exactly these seven type changes
(string to message) and nothing else. Both encodings are length-delimited,
so old bytes would misdecode rather than fail: stored data is wiped, as
for every pre-production pass.

Client-supplied request and correlation ids must be UUIDs of any version: a
set `UUID` whose value is not exactly 16 bytes (empty included) is refused
`INVALID_ARGUMENT`; unset means "not supplied". Only the length is checked.
Minted ids stay UUIDv7, and `RequestOrigin.minted` stays.

Checked and left as they are:
- `FactOrigin.external_id` stays a string: it is the external system's id,
  in that system's format.
- The CloudEvent `id` stays a string: the CloudEvents spec makes it one (its
  default embeds the root as canonical text).
- Actors (`Provenance.actor`, `Edition.created_by`,
  `DeadLetterReplay.operator`) stay strings: they are pseudonymous ids from
  an identity system, not ids the framework mints or derives.
- Edition names and store names are names, not ids. The DLQ's int64 row
  ids and the conflict nonce are not identifiers (as 8.2 said).
- The example domain protos (`io.angzarr.examples`) are user payloads and
  keep their own id types.
- Why: every stored event carries a request id and a correlation id in its
  meta (and the claim store, the correlation index and the DLQ repeat
  them). 16 bytes against 36 characters of text, a fixed-width index key,
  and one representation in every language.
- Cost: clients can no longer use arbitrary strings (an order number, a
  trace id) as request or correlation ids; they must map them to a UUID
  (UUIDv5 of their own namespace is the obvious way). **Protobuf JSON
  renders the bytes as base64** (e.g. `{"value": "1HQbGlLNQ8+t0T27lhVRCw=="}`),
  and REST paths take URL-safe base64: accepted, storage cost over JSON
  readability. The display helpers (9.3) are for humans. Storage columns
  become uuid-typed (backlog UU-3).
- Aligns with: UUID event ids in Marten (`Guid`) and KurrentDB, MassTransit's
  `Guid` `CorrelationId`, and the 16-byte UUID columns of Postgres (`uuid`)
  and MySQL (`BINARY(16)`). Diverges from Marten's, NServiceBus's and
  KurrentDB's string correlation ids, which accept any text: deliberately,
  for storage.

> **Amended by 12.1 (pass 12):** a fact's command id is the same v5 value as its default correlation, and a third namespace (`ANGZARR_COMMAND_NAMESPACE`) derives reaction command ids. The fingerprint namespace of 10.3 is gone.

**9.2 Derived ids are UUIDv5 under fixed angzarr namespaces.** Supersedes
8.3's "for a fact, `external_id` verbatim" and its "no hashing and no
name-based UUID" (which in turn had superseded PS-3's name-based wording).
- **Correlation when absent**: a request's is its request id (now a UUID,
  so verbatim, unchanged); a fact's is
  **UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`, `external_id`)**; a
  causation's is stamped from its trigger, unchanged. Still nothing mints a
  correlation.
- **Derived roots**: `compute_root(domain, key)` =
  **UUIDv5(`ANGZARR_ROOT_NAMESPACE`, `"{domain}:{key}"`)**, RFC 9562, the
  name being UTF-8 with no normalisation. The domain never contains `:`, so
  the name splits unambiguously.
- **Roots**: caller-chosen roots are any 16 bytes; framework-derived roots
  are UUIDv5 as specified; minted roots are v7.
- **The namespaces**, each generated once as a random UUIDv4 (as RFC 9562
  suggests for a new namespace) and fixed forever:
  - `ANGZARR_ROOT_NAMESPACE` = `d4741b1a-52cd-43cf-add1-3dbb9615510b`
  - `ANGZARR_FACT_CORRELATION_NAMESPACE` =
    `e9ef0ae2-6fc6-4c14-b713-ef03971dd867`
- **Two namespaces, not one (recommended and applied).** `"{domain}:{key}"`
  is itself a valid `external_id`, so under one namespace a fact's
  correlation could equal a stream's root. Separate namespaces make the two
  id spaces unrelated by construction, at no cost. The alternative (one
  namespace, with a prefix such as `"fact:"` on the name) works too but puts
  a magic string in the derivation every runtime must reproduce.
- Documented in the `derived_ids` region of `types.proto`, with worked
  values (`compute_root("player", "alice@example.com")` =
  `cfe936c0-2912-5ca9-96e6-f37c0b441759`; fact `"pi_1234"` =
  `917f26ae-ea2e-58af-86de-77013a69617e`), which the crate's tests check.
- Why: the correlation is a UUID now, and an external id is not one; a
  name-based UUID is deterministic, so every redelivery of one fact still
  lands in one correlation. v5 roots give every runtime the same root for
  the same business key.
- Cost: changing a namespace would change every derived id, so they are
  frozen; core, every client and annals implement the derivation (backlog
  UU-2). Two sources whose external ids coincide still share a correlation
  (as before; a sender that must separate them supplies `correlation_id`).
- Aligns with: RFC 9562 name-based UUIDs (its standard namespaces do the
  same for DNS names and URLs), and the common practice of deriving
  deterministic ids from business keys.

**9.3 Text is a boundary concern.** Operations use UUID objects: compare,
store, hash and pass the 16 bytes. Conversion to and from canonical text
(36 lowercase hex characters, hyphenated 8-4-4-4-12, RFC 9562) happens only
at display and input boundaries (logs, consoles, CLI arguments, a DLQ filter
literal, CloudEvent attributes), through per-language helpers. Input
accepts the hyphenated form in either case; output is always lowercase.
- **Rust**: `angzarr-proto` implements them for the generated `v1::Uuid`
  in `angzarr_proto::ids`: `Display` and `FromStr`, `from_bytes`/`to_bytes`
  and `From<[u8; 16]>`/`TryFrom<&Uuid> for [u8; 16]`,
  `From<uuid::Uuid>`/`TryFrom<&Uuid> for uuid::Uuid`, `is_well_formed`,
  `compute_root`, `fact_correlation` and the two namespace constants. It
  depends on the `uuid` crate (re-exported) without default features and
  with only `v5` (which adds `sha1_smol`): no std requirement and no RNG,
  so it stays wasm32-safe and light. It does not mint v7 (that needs a clock
  and an RNG; backlog MI-2).
- **Every other client**: backlog UU-1.
- Why: one rendering everywhere, without paying for text in storage.
- Cost: seven helper sets to write and keep in parity.
- Aligns with: the usual split between a binary UUID value type and its
  string form (Java `UUID`, .NET `Guid`, Go `google/uuid`, Python `uuid`).

## Pass 10: no request index, fact mismatch refused, v5 fingerprint

Decided by the user. As before, only the protos, the `rust/angzarr-proto`
crate and these documents changed, and nothing is reserved (the 6.6 policy
now covers passes up to and including 10: `RequestOrigin.index` (2) is
deleted outright, and `IdempotencyClaim.fingerprint` (5) changes type in
place). `buf breaking` against pass 9 reports exactly those: the deleted
`index`, unreserved (name and number), and `fingerprint` from `bytes` to
a message. Both are length-delimited, so old claim bytes would misdecode:
stored data is wiped, as for every pre-production pass.

> **Carried into 12.1 (pass 12):** the per-command id is now `CommandPage.command_id`.

**10.1 `RequestOrigin.index` is deleted; a request id is per command.**
Supersedes 5.1's `request_id`+index key. Each command carries its own
idempotency key: a caller that sends several commands together (a batch,
one API call fanning out) mints one request id per command and groups them
by a shared `correlation_id`. The request claim key is `request_id` alone,
still scoped to the addressed aggregate ((`CommandBook.cover`, key) is
unique). `Causation.index` stays: one trigger and one reactor can emit
several commands, and the framework, not a caller, must tell them apart.
- Why: since pass 1 there is one command per book, and every command's
  request id is a UUID (9.1) that the caller is free to mint. An index only
  mattered when one id named a multi-command request; it made every
  client keep a counter in step across retries, and gave the key a second
  field with no meaning of its own. Grouping is what correlation is for.
- Cost: a batch caller mints N ids instead of one (and must keep each one
  stable across retries of that command); the wire loses a field (a
  pre-production break, data wiped as before).
- Aligns with: Stripe and the IETF draft, where an `Idempotency-Key` names
  one operation, and the messaging inboxes (NServiceBus, MassTransit,
  Wolverine), which key on one message id per message.

> **Superseded by 12.2 (pass 12):** with no fingerprint there is nothing to compare; a fact re-sent with a different payload is answered DUPLICATE, undetected.

**10.2 A fact re-sent with the same `external_id` and a different payload
is refused by default; configurable to DUPLICATE plus an alert.** Resolves
the fact half of backlog KS-10.
- **Default**: refused `FAILED_PRECONDITION`, like a reused request key.
  Never answered DUPLICATE and never claimed; through `HandleAsync` it is a
  terminal failure and is dead-lettered.
- **Configurable** per command type (the payload's type URL) or per
  component: DUPLICATE instead (answered from the claimed range, as an
  exact duplicate is), plus an alert and a metric. Precedence as for
  Handling's defaults: command type, then component, then the built-in
  default (refuse). This is **coordinator configuration, not wire**: no
  message carries it (backlog KS-11).
- **Causation mismatch**: left open by this decision; decided in 10.4.
- Why: a payload that changed under the same external id is either a bug in
  the source or a correction the domain never saw; silently answering
  DUPLICATE would lose it. Refusing makes it visible. Some sources (webhooks
  that re-render a timestamp or reorder JSON on redelivery) legitimately
  vary the bytes, and for those an operator opts into DUPLICATE without
  losing visibility, since the alert still fires.
- Cost: a source with unstable bytes is refused until configured; the
  coordinator gains a setting and an alert.
- Aligns with: Stripe and the IETF draft (an error on a reused key with a
  different payload) for the default; the inbox pattern's
  "same message id, drop it" for the opt-in.

> **Superseded by 12.2 (pass 12):** the fingerprint and `ANGZARR_FINGERPRINT_NAMESPACE` are deleted.

**10.3 The fingerprint is a UUIDv5.** `fingerprint = UUIDv5(
ANGZARR_FINGERPRINT_NAMESPACE, name)`, where name is the UTF-8 type URL's
byte length as a **4-byte unsigned big-endian integer**, then the type URL
bytes, then the `Any` value bytes, all as received.
`IdempotencyClaim.fingerprint` becomes `UUID` (16 bytes; was `bytes`).
- **The third namespace**, generated once as a random UUIDv4 and fixed:
  `ANGZARR_FINGERPRINT_NAMESPACE` = `a749bd8c-7bf0-47e6-a5c9-dc54ebde74aa`,
  documented in the `derived_ids` region with the root and fact-correlation
  namespaces.
- **Why a 4-byte big-endian length** rather than a varint: fixed width, so
  every language writes it with its standard integer encoder (no varint
  helper outside protobuf), and it cannot be mis-sized. A protobuf message
  is under 2 GiB, so the length always fits. The prefix is what makes the
  type URL / value boundary unambiguous.
- **Worked example** (in `types.proto` and the crate's tests): type URL
  `type.googleapis.com/examples.Deposit` (36 bytes) and value `08 2a` give
  the name `00000024` ++ the 36 type URL bytes ++ `082a` (42 bytes) and the
  fingerprint `6d42fa9e-0dca-5047-94b1-0ae371532630`. Computed independently
  with Python's `uuid.uuid5` over the same bytes.
- **Misuse detection, not security.** The fingerprint catches an honest
  client that reuses a key for a different payload. It makes no claim
  against an adversary, so SHA-1's chosen-collision weakness is irrelevant
  to it. It is **unrelated to the deferred event hash chain**, which will use
  its own strong hash with anchoring.
- Rust: `angzarr_proto::ids::fingerprint(type_url, payload)` and
  `FINGERPRINT_NAMESPACE`.
- Why: one fixed 16-byte value and one derivation that every runtime
  already has (the v5 code of 9.2), instead of an unspecified "hash" that
  each backend and language would choose for itself.
- Cost: core, the clients and annals compute it identically (backlog KS-4,
  UU-2's golden list); changing the namespace or encoding would make every
  stored claim mismatch its retries, so both are frozen.
- Aligns with: RFC 9562 name-based UUIDs, as in 9.2; the IETF draft
  recommends a fingerprint without fixing its algorithm.

> **Superseded by 12.2 (pass 12):** no fingerprint, so no causation mismatch to detect.

**10.4 A causation key re-sent with a different fingerprint is refused and
dead-lettered, with an alert.** Resolves the causation half left open by
10.2 (backlog KS-12). Documentation only: no field, message or number
changes.
- **Refused**: never applied and never answered DUPLICATE.
- **Dead-lettered with an alert**: the command goes to the DLQ as a
  `rejected_command`, and the alert names the stream, the (event,
  component, index) key and both fingerprints.
- **Not configurable**, unlike facts (10.2).
- Why: with the transient outbox (5.6, backlog OB-1, OB-2) a reaction's
  commands are stored once and re-sent verbatim, so a redelivery always
  matches its claim. A mismatch can only be a framework bug or a corrupted
  outbox. Answering DUPLICATE would hide the bug and silently drop a
  command; applying it would run a command the claim says already ran.
  Facts get an opt-in because external sources legitimately re-render
  bytes; nothing legitimate varies a reaction's output.
- Cost: none on the wire; the coordinator gains a dead-letter path and an
  alert on the causation branch.
- Aligns with: 3.4 (violations are refused loudly; a reaction command is
  dead-lettered and alerted), and the request-key refusal of 5.3.

## Pass 12: command ids, dedup on events, no actor, state options

Decided by the user in the illuminated review of fd61f93 (flow 1, the
client command; its findings are referenced below as T4, T5 and so on, and
tracked in [critical-review.md](critical-review.md)). The protos, the
`rust/angzarr-proto` crate and these documents changed. A developer guide
was added: [docs/guide/state-and-conflicts.md](../../guide/state-and-conflicts.md).
(Pass 11, at fd61f93, was the documentation-only decision 10.4, recorded
under pass 10.)

Nothing is reserved: the 6.6 policy now covers every pass up to and
including 12, so removed fields, messages and enum values are deleted
outright and stored data is wiped. `buf breaking` against fd61f93 reports
exactly the deliberate breaks:
- the deleted, unreserved fields `EventMeta.provenance` (1), `origin` (12)
  and `base_sequence` (6); `CommandPage.provenance` (2) and `origin` (7);
  `ComponentDescriptor.rules_version` (4); `Edition.created_by` (5);
  `DeadLetterReplay.operator` (1) and `retention_overridden` (4); and
  `ReplayDeadLetterRequest.override_retention` (3);
- `CommandHandlerService.Handle` returning `CommandHandlerResponse` instead
  of `EventBook`;
- extension 50106 renamed from `commutative_state` to `state` and retyped
  from `bool` to a message.
The deleted messages (`Provenance`, `Origin`, `RequestOrigin`, `Causation`,
`IdempotencyClaim`) are not wire breaks under `WIRE_JSON`, so they are not
listed. New fields take fresh numbers (`EventMeta` 13–16, `CommandPage`
8–11), so old bytes never misdecode into them.

**12.1 One `command_id` per command; `causation_id` is plain metadata.**
Every command carries `CommandPage.command_id` (`UUID`, field 8), assigned
before deduplication:
- **Client Command**: client-supplied (any UUID version, reused on every
  retry), or a UUIDv7 the coordinator mints when the caller supplies none.
- **Reaction command** (saga or PM): derived as UUIDv5 under the new
  `ANGZARR_COMMAND_NAMESPACE` `e2c9f744-9fe1-4b4b-bfee-ae514dde293b`, over
  six **netstrings**: the trigger's domain, its edition (`""` for main), its
  root (canonical text), its sequence, the reacting component's name, and
  the command's index. Worked example (in `types.proto` and the crate's
  tests, computed independently with Python's `uuid.uuid5`): trigger
  `list` / main / `01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f` / 7, component
  `reminders`, index 0 has the name
  `4:list,0:,36:01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f,1:7,9:reminders,1:0,`
  and the id `45764676-e6e4-56fe-8c80-d782423577ee`.
- **Fact**: derived as UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`,
  `external_id`). This is the same value as the fact's default correlation,
  just as a client command's absent correlation is its command id. The
  namespace keeps its name and value, so `pi_1234` is still
  `917f26ae-ea2e-58af-86de-77013a69617e`.

> **Amended by 13.3 (pass 13):** `causation_id` stays on the command but is no longer copied onto its events; the events' causation is the command (`EventMeta.causation.command_id`).

`causation_id` (an `EventRef`, `CommandPage` field 10) names the trigger
on reaction commands and is copied onto their events. It is metadata, not a
key. `FactOrigin` (`external_id`, `description`) stays for audit, as
`CommandPage.fact_origin` (11). `Origin`, `RequestOrigin` (with `minted`)
and `Causation` are deleted. `correlation_id` moves inline (`CommandPage`
9). Validation: a Fact needs `fact_origin` (with a non-empty
`external_id`), and a Command never has one.
- **Netstrings, not `:`-joined text**: a component or edition name may
  contain `:` or `,`. Netstrings (length, `:`, bytes, `,`) split
  unambiguously whatever the strings hold, need no escaping, and every
  language can write them with its standard integer formatting.
- **`minted` deleted** (a judgement call; the brief allowed keeping it "if
  still needed"). It existed because minted ids were never keys. Now every
  id deduplicates, and `EventMeta` has no slot for the flag, so nothing would
  read it.
- **The reacting component is no longer recorded on events** (it was
  `Causation.component`). It is encoded one way in the command id: an
  auditor can test a candidate component by recomputing the id. The
  coordinator's security log names the delivering component.
- Why: this is the established message-metadata convention. KurrentDB
  (`$correlationId`, `$causationId` and event ids), NServiceBus, MassTransit
  and Marten all give a message one id, a correlation id and a causation
  id. Three origin shapes with their own keys had no parallel anywhere.
- Cost: the reaction derivation must match exactly in core, every client
  that derives it, and annals (backlog CI-2). Its namespace and encoding are
  frozen.
- Supersedes: 6.1 (one `Origin`), 8.3 (`minted`), 5.7's actor stamping,
  and the keys of 5.1. Amends 9.2 (the third namespace replaces the
  fingerprint's).

**12.2 Deduplication is by `command_id`, on the events.** "Already
applied?" means "the addressed stream already holds events whose
`EventMeta.command_id` is this command's". Every backend keeps a
(non-unique) index on (stream, `command_id`). A hit is answered DUPLICATE
with those events, and business code does not run. A concurrent duplicate
loses the append's optimistic race, re-runs from the lookup, and is answered
DUPLICATE.
- **Deleted**: `IdempotencyClaim`; the fingerprint (its namespace,
  `ids::fingerprint` and the 9/10 design: 10.2, 10.3, 10.4); expiry, purge
  and retention (5.4); the DLQ retention refusal and
  `override_retention`/`retention_overridden`; the race-loser text (T7);
  the fact-mismatch refuse-or-configure rule (10.2, KS-10, KS-11); the
  "atomic claims" backend capability; and the client-key requirement on
  `HandleAsync` and DLQ replay (5.5).
- **Accepted costs** (the user's):
  - a decision that emitted **zero events** leaves nothing to find, so a
    redelivery decides again, against the then-current state
    (Equinox-style). That is correct against the current state, but not
    deduplicated;
  - a **reused id with a different payload goes undetected**: it is
    answered DUPLICATE with the first command's events;
  - **dedup is forever**: a command id that applied to a stream can never
    apply to it again.
- **Judgement call: `HandleAsync` no longer requires a client-supplied
  id.** The coordinator mints before enqueueing, so redelivery from the
  queue and DLQ replay are deduplicated. Only the caller's own retry needs
  a caller-supplied id, exactly as for `Handle`. This also resolves CH1:
  reaction commands through `HandleAsync` carry their derived id.
- Why: the key store existed to cover zero-event decisions and to detect
  payload reuse. The user judged both not worth a second store, its
  transaction coupling, its retention rules and its backend capability.
  The events are already the durable record, and the id written with them
  is atomic with the append on every backend.
- Aligns with: KurrentDB (idempotent appends keyed on event ids) and
  Equinox (processed ids kept in the stream, so zero-event decisions
  re-decide). It diverges from Stripe and the IETF draft, which store a
  response and detect payload reuse.
- Supersedes: 5.1, 5.3, 5.4, 5.5, 5.19, 10.2, 10.3, 10.4, the KS backlog
  workstream, and [idempotency.md](idempotency.md)'s key-store design (now
  rewritten).

**12.3 No actor anywhere; who did it goes to security logs.**
`Provenance.actor`, `Edition.created_by` and `DeadLetterReplay.operator`
are deleted. Every coordinator authenticates its caller and writes who
called what (with the `command_id`) to a separate security log owned by the
deployment. The principle is stated once, in the `security_logs` region of
`types.proto`, and referenced from `meta.proto` and `dlq_admin.proto`.
- Why: identity is personal data and a security concern, not domain
  history. Putting it in immutable events pollutes the data model and makes
  erasure a rewrite.
- Cost: an auditor joins the event store with the security log by
  `command_id` to answer "who".
- Supersedes: the pseudonymous actor (pass 1 and 5.7), W4 (the reaction
  actor stamping), T4 (actor authentication: there is no actor to
  authenticate), and the actor-in-proto question for the edition and DLQ
  records.

> **Superseded in part by 13.1 and 13.3 (pass 13):** `command_id` (13) and `causation_id` (15) are replaced by `oneof causation { command_id 17 | triggering_event 18 }`.

**12.4 `EventMeta` is `{command_id, causation_id, fact, correlation_id,
recorded_at, rules_version}`.** The fields are 13, 15, 16, 14, 5 and 7.
`Provenance` is deleted (correlation is inline), and so are `origin` and
`base_sequence`.
- `base_sequence` is deleted because it is derivable: the head a decision
  saw is the sequence of its write's first event. A write is exactly the
  events sharing one `command_id`, and nobody else persisted the value.
- Supersedes: 1.1's field list and 5.16's `base_sequence` rename.

**12.5 The pipeline order is normative.** In every runtime and mode the
order is: validate → assign ids (mint or derive) → load the stream, then the
dedup lookup → resolve and check Handling (against the loaded head) →
business code. The load precedes the lookup so that a retry racing its
original's commit is never applied twice under READ COMMITTED. A retry of an applied STRICT command
with a now-stale sequence is therefore DUPLICATE, never ABORTED (T6). The
order is written once, in the `handling` region of `types.proto`.

> **Superseded by 14.1 (pass 14):** `rules_version` is the business binary's full build version, also carried on `ComponentDescriptor.rules_version`; the coordinator, not the client library, decides snapshot validity, and `snapshot_refused` is removed.

**12.6 `rules_version` is reported per response.**
`CommandHandlerService.Handle` returns `CommandHandlerResponse { EventBook
events = 1; string rules_version = 2; bool snapshot_refused = 3; }`.
`ProcessManagerHandleResponse` gains `rules_version` (3) and
`snapshot_refused` (4). The coordinator stamps the reported version onto
events and snapshots. `ComponentDescriptor.rules_version` is deleted.
`rules_version` is a short label that the domain's author chooses (for
example `"v3"`), bumped when decide, ingest or apply semantics change.
- **Snapshot validity is checked where the state is decoded**, in the
  client library, by comparing the state type URL and the rules version.
  **Judgement call, the mechanism**: on a mismatch the library answers
  `snapshot_refused` without running business code, and the coordinator
  re-delivers with no snapshot and every page from 0, and stops offering
  that snapshot. Without a signal the library could not obtain the earlier
  pages.
- Why: a rolling deployment runs two rules versions at once. A per-response
  report stamps each event with the rules that actually decided it, with no
  separate registration handshake. It also resolves T13: the coordinator
  needed a "registered state type" it never had.
- Cost: a string per response. Snapshot refusal costs one extra round trip
  after each rules bump.
- Supersedes: 5.9 (declared at registration). Amends 6.8 (where validity is
  checked).

**12.7 COMMUTATIVE is the default where the state declares conflict units;
`StateOptions` replaces the bool.**
- The `(state)` message option (50106) is `StateOptions { repeated
  ConflictResolution conflict_resolutions = 1; }`. No option means STRICT +
  AGGREGATE_HANDLES (the implicit base), and the list adds to it (in
  practice, COMMUTATIVE).
- `ComponentDescriptor.state` (6) is `StateDescriptor { string type_url = 1;
  StateOptions options = 2; }`, carrying the full resolved list. The
  coordinator takes its built-in default from it (COMMUTATIVE if listed,
  otherwise STRICT) and refuses a command or configuration naming an
  unsupported resolution (`INVALID_ARGUMENT`). That makes T3's
  registration-time promise enforceable.
- `StateOptions` is defined in `types.proto`, beside `ConflictResolution`,
  because `options.proto` imports `types.proto`. A `StateDescriptor`
  pointing into `options.proto` would have been an import cycle.
- Coordinators stay domain-blind: a list of enum values is not the
  domain's schema.
- Why: a state whose author marked conflict units has said which edits are
  independent. Making STRICT the default would make that work opt-in a
  second time. The risk is documented, not hidden (12.8).
- Cost: a modelling mistake in the markers (a dependent value split across
  units) now merges by default. The guide treats this as a modelling
  failure and shows the fixes.
- Supersedes: 6.12's "opt-in only, never a default" and 8.1's
  `bool commutative_state`.

**12.8 `ConflictUnit.whole_state`, generator diagnostics, and the guide.**
`ConflictUnit` gains `bool whole_state = 4`: an explicit "this field
conflicts with everything", which silences the unmarked-field warning. The
generator emits one warning (`unmarked-field`) and nine errors
(`no-marked-fields`, `unspecified-resolution`, `marker-outside-state`,
`descend-non-message`, `bad-element-key`, `ordered-without-key`,
`whole-state-combined`, `oneof-member-refined` and
`oneof-partially-marked`). They are listed in `options.proto`, and their
exact texts and fixes are in the guide. Codegen is `angzarr_build::compile`
for Rust (prost-build plus the generator) and `protoc-gen-angzarr` for
everything else (CR-1, renamed from `protoc-gen-angzarr-conflict`).
- **The guide** (`docs/guide/state-and-conflicts.md`) covers: custom
  options, the `state` option, marking fields, the resolver, the
  COMMUTATIVE risk section with two worked failures on hatpick's ListState,
  the diagnostics, the build setup, registration, and versioning commands.
- **Judgement call: the guide lives in `docs/guide/`, not the site.** The
  generators it describes do not exist yet, and the site documents shipped
  behaviour. It moves to the site when CR-1 lands (backlog DOC-7).

**12.9 Smaller rules.**
- A Fact with **any** Handling field is malformed (it was only
  `expected_sequence`).
- An empty Handling is the same as an unset one, for every command (it was
  only stated for reaction commands).
- The `ContextualCommand` window boundary is named explicitly: pages
  `command.handling.expected_sequence .. events.next_sequence-1`.

**12.10 Framework-only fields and routes are authenticated by mTLS
identity, on the same RPCs.** `causation_id`, and the caller-supplied
trigger books of `SagaCoordinatorService.Execute` and
`ProcessManagerCoordinatorService.Handle`, are accepted only from callers
authenticated as framework components. A client that sends them is refused
**PERMISSION_DENIED** (a judgement call: the message is well formed, but the
caller is not allowed to send it, and INVALID_ARGUMENT would tell the caller
to fix the message). The rule is in the `entry_points` region of
`command_handler.proto`.
- Resolves T5 (forged causation), SG3 (forged triggers) and CH1: reaction
  delivery and DLQ replay are framework-authenticated, and carry derived or
  original ids.
- Cost: deployments issue framework components their own mTLS identities.

**12.11 Commands can be upcast, but it is discouraged.** The client library
applies the same upcaster chain to an incoming command payload, by type
URL, before dispatch. A command type URL with no handler and no upcaster
path is refused INVALID_ARGUMENT, naming the type URL. The docs
(`upcaster.proto` and the guide's "Versioning commands") steer authors
first to additive fields, then to domain handlers for both versions, and
only last to an upcaster, as a migration aid with a planned removal.
Command upcasting hides stale clients and adds machinery for data that is
never stored.
- Supersedes: "commands are never upcast", the review's first answer to
  the same question (plan, review question 4), revised by the user before
  this pass landed.
- Wire: none. The chain runs inside `CommandHandlerService.Handle`, so
  `UpcastRequest` is unchanged.

**12.12 The crate.** `rust/angzarr-proto`:
- maps every proto `bytes` field to `bytes::Bytes` (`prost_build`
  `.bytes(["."])`; wasm32-safe);
- relies on prost 0.14 deriving `Eq` and `Hash` on every float-free
  message (`Uuid`, `Cover`, `EventRef`, `FactOrigin`, `StateOptions`,
  `StateDescriptor`, `ConflictUnit`, ...). An explicit `type_attribute`
  would conflict with that derive, so a compile-time test pins it instead;
- replaces `ids::fingerprint` and `FINGERPRINT_NAMESPACE` with
  `COMMAND_NAMESPACE`, `reaction_command_id(trigger, component, index)` and
  `fact_command_id(external_id)`, keeping `fact_correlation` (now the same
  value) and the display helpers. Its tests check values computed
  independently with Python's `uuid.uuid5`.

## Pass 13: causation is the direct cause; PM process events; reactor re-runs

Decided by the user after pass 12 (eec6676), closing the two questions pass
12 left open: the meta of a PM's own process events (review PM2, backlog
PR-3) and reactor re-runs (review T8). The protos, the `rust/angzarr-proto`
crate's tests and these documents changed; the crate's API did not.

Nothing is reserved: the 6.6 policy now covers every pass up to and
including 13 (`proto/buf.yaml`). `buf breaking` against eec6676 reports
exactly the deliberate breaks: `EventMeta` field 13 (`command_id`) and field
15 (`causation_id`) deleted without reserving their numbers or names (four
lines, a number and a name each). The new fields take fresh numbers (17,
18), so pass-12 bytes never misdecode into them; the crate's tests decode
pass-12 bytes for 13 and 15 to an empty `EventMeta`. Because `command_id`
keeps its name, its JSON (`commandId`) is unchanged.

**13.1 `EventMeta.causation` is a oneof of the event's direct cause.**
`oneof causation { UUID command_id = 17; EventRef triggering_event = 18; }`.
`command_id` is set on every event a command produced (client, reaction or
fact) and is still the deduplication key (12.2). `triggering_event` is set
only on a process manager's own process events (13.2). Exactly one is set
on every persisted event. Field 13 is deleted, unreserved.
- Why: the standard's causation (KurrentDB's `$causationId`, NServiceBus,
  Marten, Wolverine) is a message's DIRECT cause. An event's direct cause is
  the command that produced it; a process event has no command, and its
  direct cause is the trigger the PM reacted to. A oneof states that the two
  never coexist.
- Cost: readers switch on the arm; the dedup index reads one arm.
- Supersedes: 12.4's field list (with 13.3).

**13.2 PM process events name their trigger, carry its correlation, and
deduplicate on it.** The PM's coordinator stamps each process event with
`causation.triggering_event` (the trigger's `EventRef`, the same event its
commands' `causation_id` names), the trigger's `correlation_id`,
`recorded_at` and the response's `rules_version`; never a `command_id` or a
fact. "Already applied?" for a trigger is "the PM's stream holds events whose
`triggering_event` is this trigger", on a (stream, `triggering_event`)
index; on a hit nothing is appended. A PM writes at most one process write
per trigger, so the trigger alone is the key. Business output stays
payloads only. Resolves PM2; closes PR-3 (implementation: PR-4).
- Why: the PM's stream is an aggregate's stream, and its events need the
  same "already applied?" answer as a command's, for a checkpoint reset or a
  redelivery that bypasses the outbox. The trigger is the identity the
  coordinator already has; deriving a synthetic command id for events no
  command produced would invent a message that never existed.
- Cost: a second, non-unique index on PM streams; the zero-output cost of
  12.2 applies (a reaction that wrote no process events leaves nothing to
  find).
- Rejected: a `command_id` derived from the trigger and PM name at a
  reserved index (backlog PR-3's suggestion), for the reason above.

**13.3 No command-causation on events.** `EventMeta.causation_id` (15) is
deleted. The triggering event of a reaction command (the events' "grand
cause") is not stored on events; that edge goes to OpenTelemetry traces and
logs, as in Marten and Wolverine, by the same principle that sent the actor
to security logs (12.3). `CommandPage.causation_id` (10) **stays**: it is
the command message's own causation per the standard (a command's
causation is its trigger), the input its derived `command_id` hashes, and
transport and trace metadata, not persisted on its events.
- **Forward causation** (`CorrelationQuery`): process events are linked to
  their trigger exactly (`triggering_event`); events of reaction commands
  are linked only by correlation (coarse), grouped per command by
  `command_id`; exact trigger edges come from traces.
- Why: each event records its own direct cause, as the standard does; the
  trigger is one hop further back, and the convention keeps hops in the
  trace. The event store records why (direct cause, correlation, rules),
  not the whole call graph.
- Cost (accepted): the store alone cannot answer "which events did this
  saga's reaction to E produce"; that needs the traces, and their retention
  is the deployment's. Backlog PS-6 (record the edge in spans) and CQ-2
  (the helper) carry it.
- Supersedes: 12.1's "copied onto their events" and 12.4's field list; 6.4's
  "forward causation is derivable from the result" (now exact for process
  events only).

**13.4 Reactor re-runs: no switch; repairs are new commands.** A reaction
`command_id` depends only on (trigger, component, index), never on the
reactor's `rules_version` or code. A re-run over a handled trigger (a
checkpoint reset) re-derives the same ids, which every destination answers
DUPLICATE, and a PM's process events dedupe on `triggering_event`.
Checkpoint resets are for recovery only. Repairing what a buggy reactor did
is done with NEW commands (new ids), which append new, correct events after
the buggy-era ones. **History is never lost**: nothing is overwritten,
either way. The framework will ship standard re-drive commands that trigger
reprocessing (backlog RD-1). Resolves T8. The guide's "Re-running reactors"
(`docs/guide/state-and-conflicts.md`) and [idempotency.md](idempotency.md)
document it.
- Considered and dropped: a per-reactor configuration switch putting the
  reactor's `rules_version` into the derivation, so a re-run after a
  version bump would yield new ids and apply. It made toggling the switch,
  or bumping the version, silently change every id derived afterwards, and
  made a reset a repair mechanism with no record of intent. With it gone,
  the question of where a saga reports its `rules_version` is moot.
- Why: deduplication stays one simple rule (an id applies once, forever),
  and every repair is an explicit command with its own id and audit trail,
  as in the event-sourcing practice of compensating rather than rewriting.
- Cost: a re-run never repairs anything; the developer issues (until RD-1,
  hand-builds) re-drive commands.

**13.5 No reacting-component field.** Events and commands carry no field
naming the reacting saga or PM: source control says what makes what.
Confirms 12.1's "the reacting component is no longer recorded on events".

**13.6 No command-causation on events** (the principle of 13.3, recorded on
its own): an event never carries its producing command's causation. Events
record their direct cause only.

## Pass 14: the coordinator selects snapshots by build version

Decided by the owner on 2026-10-19, superseding 12.6 and backlog RV-3 as
pass 12 wrote it. The protos, the `rust/angzarr-proto` crate's tests, the
contract features and these documents changed; the crate's API gained one
field.

> **Amended by 14.3–14.9 (pass 14):** one leading `v`/`V` is stripped before parsing; queries use the same rule; a response reporting a version other than the registered one is refused; a registration without a version is refused; `snapshot_refused` is NOT reserved (policy 6.6 holds); the upcast type travels in `ErrorInfo` metadata `upcast_type_url`.

**14.1 `rules_version` is the build version, and the coordinator decides
snapshot validity.** Supersedes 12.6; amends 6.8; partly restores 5.9.
- **The business logic declares no snapshot compatibility.** It implements
  the gRPC protocol and reports its version, nothing more.
- **The version is the business binary's full version**, baked in at build
  time (e.g. by versionator), never a label chosen by hand. It is still
  reported on every `CommandHandlerResponse` and
  `ProcessManagerHandleResponse` (`rules_version`), and the coordinator
  stamps it **in full** on `EventMeta.rules_version` and
  `Snapshot.rules_version`, per response, so a rolling deployment stamps
  each event with the build that decided it.
- **`ComponentDescriptor.rules_version` (4) is back**: the registration
  hello a component sends its coordinator on startup carries the same full
  version.
- **The coordinator offers a snapshot only if** its state type URL equals
  the registered `StateDescriptor.type_url` and its `rules_version` passes
  the domain's compatibility rule against the registered version.
  - Default rule: both versions parse as SemVer 2.0.0 and their major and
    minor numbers are equal. If either does not parse, exact string
    equality.
  - Coordinator configuration may replace the rule per domain with an
    accept pattern and an optional reject pattern, matched against the
    snapshot's version. A reject match wins. Patterns use RE2 syntax
    (linear time, no lookaround, no backreferences) with full-match
    semantics; a pattern outside it is refused when configuration loads.
  - A snapshot that fails is simply not offered: the delivery carries every
    page from sequence 0.
- **`snapshot_refused` is removed** from `CommandHandlerResponse` (3) and
  `ProcessManagerHandleResponse` (4), with the re-deliver-without-snapshot
  path. Both numbers and names are **reserved**, by the owner's ruling,
  ahead of the 6.6 policy (`proto/buf.yaml`).
- The client library's steps in `Handle` are now upcast, dispatch,
  conflicts. It folds whatever snapshot it is given.
- Why: compatibility is an operational policy, not business logic. A
  build version needs no author discipline to bump, and the coordinator
  already holds the registration, so it can refuse a snapshot before
  delivery instead of paying a refused round trip. The registered state
  type also settles T13 at its source.
- Cost: every build changes the stamped version, so the default rule must
  tolerate patch and build-metadata changes (it compares major.minor); a
  semantic change shipped as a patch release reuses old snapshots unless
  the domain's rule says otherwise. Operators own the per-domain override.
- Aligns with: snapshots as caches invalidated by a version check (Marten,
  Axon, Eventuous), here checked where the snapshot is loaded.

**14.2 An unknown type after upcasting names both type URLs; facts are
upcast too.** The client library upcasts Command and Fact payloads alike.
A payload whose type URL, after upcasting, reaches no handler is refused
`INVALID_ARGUMENT`; the status message names the type URL as sent, and the
status details carry the type URL the chain ended at. Clarifies 12.11 for
the router work (backlog VC-1).

**14.3 One leading `v` is ignored by the default rule.** Before parsing
SemVer 2.0.0, the default rule strips one leading `v` or `V` from each
version, so `"v1.4.2"` and `"1.4.7"` compare by major.minor. Anything else
that does not parse still falls back to exact equality of the versions as
recorded (`"vv1.4.2"` is not stripped twice). Owner ruling, 2026-10-19.
- Why: git tags and many build tools write versions with a `v` prefix.

**14.4 Queries choose snapshots by the same rule.** While a component
owning the queried domain is registered, `EventQueryService` (a
`TemporalQuery` included) returns a snapshot only if it passes the state
type check and the domain's compatibility rule against that registration.
While none is registered, a query returns no snapshot and every page from
sequence 0. Owner ruling, 2026-10-19.
- Why: a query's caller folds the returned book exactly as business code
  does, so an incompatible snapshot is as wrong there.
- Cost: a query for an unregistered domain replays from 0.

**14.5 Version skew is a handler bug.** A `CommandHandlerResponse` or
`ProcessManagerHandleResponse` whose `rules_version` differs from the
version in the component's registration (an empty one included) is
refused: nothing is persisted or sent; a caller of `Handle` or
`HandleSync` is answered `INTERNAL`; an asynchronous or reaction delivery
(a PM's trigger included) is dead-lettered and alerted, as for any other
handler bug (5.8). Owner ruling, 2026-10-19.
- Why: the registered version is what snapshot selection trusts; a binary
  answering under another version would stamp events and snapshots that
  selection never vetted.

**14.6 A registration must carry a version.** A `ComponentDescriptor` with
an empty `rules_version` is refused `INVALID_ARGUMENT`, so a binary built
without a baked version cannot register. With 14.5, an empty version on a
response is refused too. Owner ruling, 2026-10-19.

**14.7 `snapshot_refused` is not reserved.** Correcting 14.1: policy 6.6
holds, so `CommandHandlerResponse` field 3 and
`ProcessManagerHandleResponse` field 4 are deleted outright, numbers and
names unreserved, and `proto/buf.yaml` keeps no exception. Owner ruling,
2026-10-19.

**14.8 The upcast type travels in `ErrorInfo`.** Making 14.2 concrete: the
`INVALID_ARGUMENT` status for an unknown type after upcasting carries a
`google.rpc.ErrorInfo` whose metadata key `upcast_type_url` holds the type
URL the chain ended at (the sent one when no upcaster applies), as the
router already does (ADR 0001: errors cross as `google.rpc.Status` with an
`ErrorInfo`). Owner ruling, 2026-10-19.

**14.9 With several versions registered, a query's snapshot must pass
them all.** While several instances of a domain's component are registered
with different versions (a rolling deployment), a query (`EventQueryService`,
a `TemporalQuery` included) returns a snapshot only if it passes the
compatibility rule against every registered version; otherwise it returns
no snapshot and every page from sequence 0. Settles the open question in
14.4. Owner ruling, 2026-10-19.
- Why: a query has no instance of its own, so the only safe snapshot is
  one every running build would accept.
- Cost: during a rolling deployment across a major.minor change, queries
  replay from 0 until the old instances deregister.

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
