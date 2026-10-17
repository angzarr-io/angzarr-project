# Audit-meta decision log (passes 1–8)

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

**5.1 Idempotency key store (claims).** Keys are `request_id`+index, the
causation tuple, and the fact's `external_id`. They are scoped per addressed
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
  same causation keys (W3). The user was wary of purity contracts: only
  workflow engines require determinism.
- Cost: an outbox write per reaction.
- Aligns with: the NServiceBus outbox, MassTransit's transactional outbox and
  Wolverine's durable outbox. Diverges from Temporal-style deterministic
  replay, deliberately.

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

## Pass 6 (650d774): the debatable items decided

The user decided the review's D1–D11 (see
[critical-review.md](critical-review.md)) before this pass, and added the
restoration of `COMMUTATIVE` during it. As before, only the protos, the
`rust/angzarr-proto` crate and these documents changed. Wire breaks are
accepted, and this round's deletions stay unreserved (6.6).

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
never parsed. The conflict nonce and the DLQ's int64 row ids are not
identifiers and are not covered. Documented as the `minted_ids` region of
`types.proto`.
- Why: time-ordered ids index and sort well, and one rule in both runtimes
  keeps annals and angzarr records alike.
- Aligns with: RFC 9562's recommendation of v7 for new time-ordered keys,
  and the same idea as Marten's sequential (comb) Guid ids.

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
- Why: audit wants a request id everywhere; dedup must only trust keys the
  client will reproduce on retry.
- Cost: core, the clients and annals mint and record the id (backlog MI-1,
  MI-2); a wire field.
- Aligns with: request-id middleware convention (an `X-Request-Id` is
  generated when absent and logged), while Stripe-style dedup honours only
  the client's `Idempotency-Key`.

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
