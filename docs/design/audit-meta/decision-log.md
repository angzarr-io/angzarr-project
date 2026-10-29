# Audit-meta decision log (passes 1–14)

> **Renamed by 14.33 (2026-10-28):** where an entry below says "saga" for
> the stateless event-to-command mapper (`SagaService`, `SagaResponse`,
> `COMPONENT_KIND_SAGA`, `reaction_command_id`), read "policy"
> (`PolicyService`, `PolicyResponse`, `COMPONENT_KIND_POLICY`,
> `policy_command_id`). The entries keep their text.

> **Renamed in the example by 14.38 (2026-10-28):** where an entry below
> names the blackjack example's "player" aggregate (`PlayerState`,
> `player.proto`, `HoldFunds`'s domain, `BuyInPlayerPolicy`,
> `PlayerBuyInPolicy`, the settlement `TablePlayerPolicy`), read the
> wallet (`WalletState`, `wallet.proto`, `BuyInWalletPolicy`,
> `WalletBuyInPolicy`, `TableWalletPolicy`). "player" is now the bot that
> decides a seat's moves.

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

> **Reaffirmed by 14.28 (pass 14):** the owner kept the structure and had the protos say so firmly.

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

> **Amended by 14.31 (pass 14):** the side channel stays deleted, but a refusal is no longer a domain event of the refusing side. A saga's target (an aggregate or a process manager) refuses the saga's command with a business rejection, optionally carrying a typed refusal object of its own domain (one of the command's `refuses` types), and records nothing. The refusal goes back to the saga, which builds one unrefusable refusal fact for the exact stream of its triggering event: by default its generated code passes through the standard `CommandRefused { command, refusal, trigger }`, the typed object packed as an `Any`, which the source handles in its `on_refused_<Command>(refusal, state)`; or, where angzarr-cli selects translate at code generation, the saga's callback reads `Refusal { event, command, response }` and returns a domestic fact, which is why translate exists: a source that does not want to unpack a foreign object, or import foreign protos, gets a domestic fact instead. Either way the fact's id is the refused command's id, the source decides what the refusal means and records its own events, and both calls go through the outbox (the fact written in the transaction that clears the command's entry), retried and deduplicated by that one id. Process managers take the replies to their steps as commands from sagas, and the refusals of their own steps as these facts.

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

> **Amended by 14.31 (pass 14):** the outbox is one component-kind-agnostic capability: any component whose output leaves its own stream uses it, and today that is the saga, for its commands and its refusal facts. A process manager needs none: it is a domain, its only output is its own events, and it consumes no stream, so it has no checkpoint.

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

> **Amended by 14.37 (pass 14):** `ProjectorFailure.message` (3) is deleted, unreserved; the failure is `code` and `diagnostic` (4), a key and its args, never text.

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

> **Superseded by 14.32 (pass 14):** editions are per-stream forks: creating one appends a fork event to an origin stream (`ForkStream`), and the fork travels with the data, each saga command in the edition forking the stream it reaches; there is no registry, no `CreateEdition` and no `Edition` record. An unknown edition is one with no stream forked and not yet deleted. `DeleteEdition` stays: sequenced after the edition's in-flight work, it removes every row tagged with the edition; main knows nothing of any of it.

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

> **Amended by 14.31 (pass 14):** `ProcessManagerCoordinatorService` is deleted (a process manager is a domain, with no trigger entry point); a saga's refusal facts also carry the framework-only `causation_id`.

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

> **Amended by 14.31 (pass 14):** a process manager is a domain with no triggers, so every event, a PM's included, carries `command_id`. `triggering_event` (18) is deleted, unreserved; `causation` keeps one arm.

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

> **Superseded by 14.31 (pass 14):** a process manager is a domain with no triggers; its inputs are commands (which sagas send it) and facts. Its events carry `causation.command_id` and their input's correlation, and deduplicate on `command_id` before the handler runs. No PM event is trigger-caused, so `triggering_event`, its index and the trigger lookup are deleted.

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

> **Amended by 14.3–14.29 (pass 14):** the coordinator pulls the descriptors (`ComponentService.Describe`); a versionless descriptor fails registration visibly in the coordinator's readiness, not with a status. One leading `v`/`V` is stripped before parsing; queries use the same rule; a response reporting a version other than the registered one is refused; a registration without a version is refused; `snapshot_refused` is NOT reserved (policy 6.6 holds); the upcast type travels in `ErrorInfo` metadata `upcast_type_url`.

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

> **Amended by 14.37 (pass 14):** the status message is the reason key, never text: an unknown command type is `UNKNOWN_COMMAND_TYPE` (a fact `NO_FACT_HANDLER`), with the sent type URL as `ErrorInfo` metadata `type_url` beside `upcast_type_url`.

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

> **Amended by 14.10 (pass 14):** the coordinator pulls the descriptor, so a versionless one is refused in the coordinator's readiness (NOT_SERVING, error log, alert), not with `INVALID_ARGUMENT`.

**14.6 A registration must carry a version.** A `ComponentDescriptor` with
an empty `rules_version` is refused `INVALID_ARGUMENT`, so a binary built
without a baked version cannot register. With 14.5, an empty version on a
response is refused too. Owner ruling, 2026-10-19.

**14.7 `snapshot_refused` is not reserved.** Correcting 14.1: policy 6.6
holds, so `CommandHandlerResponse` field 3 and
`ProcessManagerHandleResponse` field 4 are deleted outright, numbers and
names unreserved, and `proto/buf.yaml` keeps no exception. Owner ruling,
2026-10-19.

> **Amended by 14.37 (pass 14):** the sent type URL travels in `ErrorInfo` too, as `type_url`; the status message is the reason key.

**14.8 The upcast type travels in `ErrorInfo`.** Making 14.2 concrete: the
`INVALID_ARGUMENT` status for an unknown type after upcasting carries a
`google.rpc.ErrorInfo` whose metadata key `upcast_type_url` holds the type
URL the chain ended at (the sent one when no upcaster applies), as the
router already does (ADR 0001: errors cross as `google.rpc.Status` with an
`ErrorInfo`). Owner ruling, 2026-10-19.

> **Replaced by 14.21 (pass 14):** a query is judged against the answering coordinator's own registration; with one business process per coordinator there are never several.

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

> **Amended by 14.19 (pass 14):** `Describe` returns one `ComponentDescriptor` and `ComponentDescriptors` is deleted; the "one process may host several components" rationale below no longer holds. The pull direction stands.

**14.10 The coordinator pulls the descriptors.** Every business process
serves `ComponentService.Describe(DescribeRequest) returns
(ComponentDescriptors)` (new `component.proto`; `ComponentDescriptors {
repeated ComponentDescriptor components = 1; }` in `types.proto`),
answered by the client library from its components' generated descriptors,
one per hosted component. The coordinator calls it when it first connects
to the business process and again every time its channel comes back up;
each successful answer replaces the held descriptors, and holding one is
what "registered" means. Nothing (command, fact, trigger, event) is
delivered to a component without a held descriptor: a waiting caller is
answered `UNAVAILABLE`, and queued and reaction deliveries stay queued. An
answer with an empty `rules_version` is refused as a whole: the
coordinator holds nothing from it, logs an error naming the process and
the component, raises an alert and stays `NOT_SERVING`. The coordinator
reports `SERVING` (grpc.health.v1 and its readiness probe) only after a
successful Describe. Version skew on responses stays refused (14.5).
Amends 14.6 (the refusal surfaces in readiness, not as `INVALID_ARGUMENT`,
because the coordinator is the caller). Owner ruling, 2026-10-19.
- Direction: pull, keeping the existing dial direction (coordinator to
  business), as Dapr's sidecar does when it calls the app's configuration
  endpoint on startup.
- Rejected: push, the business process calling its coordinator to
  register (as Envoy's xDS clients, Temporal workers and Axon's
  connector do). The coordinator already dials the business process, and
  push would give every business process a coordinator address and client
  code of its own.
- One shared service, not a Describe RPC on each kind service: one process
  may host several components of different kinds (the router's
  `component_descriptors` already returns a list), so one call per process
  describes them all, and a process serves it once whatever it hosts.
- Cost: a coordinator whose business process is up but answered badly
  stays not ready until the channel is re-established; it is visibly broken
  rather than silently delivering.

**14.11 A failing Describe is alerted only after a grace period.** Amends
14.10. Every failed `ComponentService.Describe` call (unreachable, or an
error status) is logged. An alert is raised only once Describe has kept
failing for longer than the coordinator's `describe_alert_grace_period`
(configuration; default 2 minutes). Until a later Describe succeeds the
coordinator holds nothing from that process, delivers nothing and stays
`NOT_SERVING`. A versionless answer still alerts at once (14.10). Owner
ruling, 2026-10-19.
- Why: a business process that is restarting fails Describe briefly and
  routinely; paging on that is noise, while one that stays down is not.

> **Amended by 14.14 (pass 14):** the PM's state has its own field, `ProcessManagerHandleResponse.process_state` (5); it no longer rides on the last `process_events` book.

**14.12 The client library returns the state on every response.** The
router returns the post-command state in
`CommandHandlerResponse.events.snapshot.state` on EVERY response, and a
process manager's post-reaction state as `snapshot.state` on the last
`process_events` book (a book with no pages when the reaction wrote no
process events). Business code never decides when, and there is no
request flag or ask. The coordinator persists it per the domain's storage
policy (default: newest only), stamping `sequence` and `rules_version`,
and offers the stored bytes unchanged with the next delivery, subject to
14.1's checks and the window bound. Owner ruling, 2026-10-19 (the PM
placement is the spec's: the response has no other state slot).
- Why: snapshot cadence is storage policy, not business logic (2.x, SN-2);
  the library already holds the folded state after deciding.
- Cost: a state message on every response, whether or not the policy
  stores it.

**14.13 Client delivery-mode names follow the RPCs.** Client methods are
`handle_async`, `handle` and `handle_sync`; the command builder's are
`execute_async`, `execute` and `execute_sync`, named after `HandleAsync`,
`Handle` and `HandleSync`. The client parity scenarios follow the protos:
a command built without an expected sequence leaves it unset (the
coordinator stamps the head), the builder method is
`with_expected_sequence`, the default conflict resolution is
`UNSPECIFIED`, a cover has no correlation id, and an `EventPage` payload
is never a `PayloadReference`. Owner ruling, 2026-10-19.

> **Superseded by 14.31 (pass 14):** a process manager is a domain served by `CommandHandlerService`; its state is `CommandHandlerResponse.events.snapshot.state`, as an aggregate's, and `ProcessManagerHandleResponse` is deleted.

**14.14 A process manager's state has its own response field.** Amends
14.12. `ProcessManagerHandleResponse` gains `Snapshot process_state = 5`,
the counterpart of the request's `process_state`: the client library sets
`process_state.state` to the post-reaction state on every response, and
the coordinator stamps `sequence` and `rules_version` and persists it per
the PM domain's storage policy. The `process_events` books carry payloads
only; a snapshot on them is refused like any other non-payload output.
Field 5, not 4, so bytes from the deleted `snapshot_refused` (4, a bool)
can never decode into a message. Owner ruling, 2026-10-19.
- Why: a dedicated field says what it is; riding on the last book (or a
  page-less one) was a convention every implementation would have to know.

**14.15 Builders never invent a correlation id.** A client's command
builder sends no `correlation_id` unless the sender sets one; the
coordinator applies the proto's rule (an absent correlation is the
command id, itself minted as a UUIDv7 when absent; a fact's is its derived
id). Parity C-0305 says so. Owner ruling, 2026-10-19.
- Why: one rule, applied in one place; a client-minted correlation would
  differ from the command id the coordinator mints and split the trail.

> **Superseded by 14.20 (pass 14):** each PM has its own coordinator; `ProcessManagerHandleRequest.component` and its refusals are deleted.

**14.16 One process manager per request.** The coordinator delivers a
trigger to each subscribed PM component separately.
`ProcessManagerHandleRequest` gains `string component = 3`, the PM's name
as `ComponentService.Describe` reported it, and the response is that one
PM's process events (covers: its own stream), commands and
`process_state`. There is no fan-out to co-resident PMs and no merging of
answers. An empty `component` is refused `INVALID_ARGUMENT` (malformed); a
PM the process does not host is refused `NOT_FOUND`; both terminal in the
existing status set. Owner ruling, 2026-10-19.
- Why: each PM is its own aggregate with its own stream and state; a
  merged answer had no single stream to append to or state to store.

> **Parked by 14.27 (pass 14):** there is no batch helper; this rule waits until a caller needs batching.

**14.17 A batch shares one correlation unless it opts out.** By default
the command builder's batch helper sends ONE `correlation_id` across the
batch's commands: the caller's if given, otherwise one it mints (UUIDv7).
An explicit opt-out sends none, so each command defaults coordinator-side
to its own command id. A single, unbatched builder still sends none unless
the caller sets one (14.15). SDK helpers still mint a command id per
command for retries (CI-7). Owner ruling, 2026-10-19.
- Why: a batch is usually one piece of work, and sharing its correlation
  is what lets `GetCorrelatedEvents` find all of it.

**14.18 Correlation ids in the scenarios are UUIDs.** The client and
parity scenarios used strings ("trace-123", "workflow-123") for
correlation ids; they are 16-byte `UUID`s since 9.1, so the scenarios now
use UUID text. Owner ruling, 2026-10-19.

**14.19 One coordinator, one component, one business process.** A
component is one aggregate, one saga, one process manager or one
projector, and nothing hosts several. A saga or process manager emitting
commands to several aggregates or domains, and a process manager or
projector with several input domains, are still one component.
`ComponentService.Describe` returns one `ComponentDescriptor`;
`ComponentDescriptors` is deleted (it was never in a release). Amends
14.10, whose "one process may host several components" rationale is
withdrawn; the pull direction stands. Parity C-0498 (a host serving
several components) is deleted. Owner ruling, 2026-10-20.
- Evidence (owner's session log): the multi-component support came from
  an agent plan nobody asked for, and its only production use was reverted
  the same day.
- Why: in event-sourcing terms, co-hosting couples independent
  subscribers (one's failure, deploy or backlog stalls the others), and it
  forces one `rules_version` on components that change independently. One
  component per process keeps each subscriber's position, version and
  readiness its own.
- Cost: more processes and coordinators to deploy; a small example runs
  several binaries.

> **Amended by 14.31 (pass 14):** a process manager's coordinator is a command handler coordinator for its domain; several PMs told of one event are several sagas, each sending its own PM a command.

**14.20 Each process manager has its own coordinator.** Supersedes 14.16.
`ProcessManagerHandleRequest.component` (3) and its `INVALID_ARGUMENT` /
`NOT_FOUND` refusals are deleted, as are the "never fans out / never
merged" rules: with one PM per process and per coordinator there is
nothing to fan out to or merge. Several PMs reacting to one domain are
several coordinators, each delivering to its own PM with its own process
state. Scenarios C-0576 and C-0577 are deleted; C-0578 is rewritten.
Owner ruling, 2026-10-20.

> **Amended by 14.26 (pass 14):** a standalone query server holds no registration and returns no snapshot.

**14.21 A query is judged by the answering coordinator's registration.**
Replaces 14.9. A query returns a snapshot only if it passes the state type
check and the domain's compatibility rule against the registration of
the coordinator answering it; while that coordinator holds none, it
returns no snapshot. During a rolling deployment each instance's
coordinator judges by its own instance's version. C-0560 is rewritten.
Owner ruling, 2026-10-20.

> **Amended by 14.25 (pass 14):** the open question is settled: the owning coordinator upcasts on every read and publish path through its own business process.

**14.22 An upcaster is part of its component.** An upcaster belongs to
the component whose streams it upcasts. It has no `ComponentKind`, no
descriptor and no coordinator of its own, and `UpcasterService` is served
only by that component's own business process. The sentence allowing an
upcaster to be "deployed as a separate binary" is deleted from
`upcaster.proto`; no service or enum value needed removing (there is no
upcaster kind). How a saga, process manager or projector reading another
component's stream gets that component's upcasting stays open (backlog
GAP-1). Owner ruling, 2026-10-20.

> **Amended by 14.24 (pass 14):** a saga has exactly one source and one destination domain; `output_domains` is PROCESS_MANAGER only.

**14.23 One saga per (source domain, destination domain) pair.** Every
reaction that turns one domain's events into another domain's commands
belongs to that pair's single saga, recorded on `ComponentOptions`
(`options.proto`) and `SagaService` (`saga.proto`). In the blackjack
example, the round-history and loyalty sagas (both table -> player) are
merged into `TablePlayerSaga` (saga-table-player): per outcome in seat
order, `RecordRoundResult` then `AwardLoyaltyPoints`. Owner ruling, 2026-10-20.
- Why: one subscriber per pair, so one position, one deployment and one
  version per translation, and no two sagas racing over the same event
  for the same destination.

> **Amended by 14.31 (pass 14):** a process manager sends no commands; `output_domains` (6) is deleted and `output_domain` is SAGA only.

**14.24 A saga has exactly one source and one destination domain.**
Amends 14.23. A saga is a translator between two domains:
`ComponentOptions.input_domain` is its one source and `output_domain` its
one destination (required); `output_domains` is PROCESS_MANAGER only.
Anything needing several destinations is a process manager. Refusals
follow the existing style: angzarr-cli lint fails generation for a saga
with `output_domains` or no `output_domain`; at run time the client library
refuses a saga answer holding a command for any other domain
(`SagaService.Handle` fails `INTERNAL` with no commands, and the
coordinator dead-letters the trigger and alerts). The coordinator does not
check it itself, because `ComponentDescriptor` carries no output domains.
The blackjack example's one saga, `TablePlayerSaga` (table -> player),
already has one destination; no example saga changed. Owner ruling,
2026-10-20.
- Why: a translator between two domains is the saga's whole job; fan-out
  to several destinations is coordination, which is what a process
  manager is for.

> **Amended by 14.29 (pass 14):** "publishing to the bus" means wherever stored events reach a subscriber, live publishing and reads of stored history alike.

**14.25 The owning coordinator upcasts on every way out of its stream.**
Amends 14.22 and settles backlog GAP-1's open question. The coordinator of
the component that owns a stream upcasts that stream's events on every
read and publish path by calling its own business process's
`UpcasterService`: loading for `Handle` (and a PM's `process_state`),
answering queries, and publishing to the bus. Consumers (sagas, process
managers, projectors) only ever see current event shapes and have no
upcasters of their own. The store is never rewritten. Owner ruling,
2026-10-20.
- Why: the owner of a stream is the only party that knows its old shapes;
  upcasting once on the way out keeps every reader on one shape.
- Cost: publishing and queries call the business process; a business
  process that is down stalls its stream's publishing and queries as well
  as its commands.

**14.26 Event-store queries may run standalone.** `EventQueryService`
(`query.proto`) is a read-only interface independent of
`CommandHandlerCoordinatorService`. An aggregate (or process manager)
coordinator serves it for its own component's domain; a standalone query
server may serve it for downstream readers with no component behind it,
and serves no command RPCs. Snapshots: through a coordinator, judged
against that coordinator's registration (14.21); a standalone server holds
no registration, so it returns no snapshot and every page from sequence 0
(C-0556, C-0589). Owner ruling, 2026-10-20.
- **Open (owner question): upcasting on a standalone server.** 14.25
  assumes a component behind the server. Proposed options:
  (a) the standalone server is configured with the stream owner's
  `UpcasterService` address and upcasts through it, as the owner's
  coordinator would (consistent results, but a runtime dependency on the
  owner's business process);
  (b) it serves events as stored, and its readers must accept old shapes
  (no dependency, but contradicts "readers only ever see current shapes");
  (c) it is not allowed for a domain whose component declares upcasters.
  Recommended: (a). Not specified in the protos until ruled.

**14.27 No batch helper; the batch-correlation rule is parked.** The
command builder's batch helper is dropped, with parity C-0572 to C-0574.
14.17's rule (a batch shares one correlation by default, the caller's or
one the helper mints as a UUIDv7, with an explicit opt-out) is parked
until a caller needs batching. Decision 1.4 already permits a client
library to batch separate calls on its side; each is still its own
CommandBook. C-0575 stands: a single command never gets a minted
correlation. Owner ruling, 2026-10-20.

**14.28 One command per CommandBook, reaffirmed.** The owner reaffirmed
1.4 and kept the structure: `CommandBook { cover, page, handling }`, with
`CommandPage` as the one command, never a list. The `command_book` and
`command_page` comments now say so, citing 1.4: deduplication, the
expected-sequence check and the outcome are per command, and there is no
wire batching. Site pages that showed `repeated CommandPage pages` or
several pages per book (the CommandBook glossary entry, `pitch.mdx`,
`architecture.md`, and code samples in `patterns.mdx`, `saga.mdx` and
`commands-vs-facts.md`) now show one page. Owner ruling, 2026-10-20.
- Why the page structure is kept: several command pages per book may come
  later as an enhancement, and the structure gives such a design somewhere
  to land. It would need new per-page error, outcome and deduplication
  semantics, and it is not planned. The protos describe only what holds
  now: exactly one command.

**14.29 Upcasting covers stored history, not only live publishing.**
Amends 14.25. The coordinator publishes only what it appends, and business
code writes current shapes, so live publishing never carries an old
shape. Old shapes reach a subscriber when it reads stored history
(catching up, filling a gap, rebuilding). The owning coordinator upcasts
wherever stored events reach a consumer, live publishing and history reads
alike. C-0586 now exercises a subscriber reading stored history. Owner
ruling, 2026-10-20 (from core's report).

> **Amended by 14.31 (pass 14):** a process manager has no trigger; its root is the correlation of the commands and facts addressed to it (their cover root, which a set `correlation_id` must equal), and its edition theirs. A saga's command takes its trigger's correlation, so the rule reaches the same instance.

> **Amended by 14.36 (pass 14, as amended):** the root is no longer the correlation by rule. A policy always names its command's root, for a PM as for an aggregate; "root = correlation" is a convention it may follow. The command still carries its trigger's correlation, and a `correlation_id` that differs from the cover's root is no longer malformed.

**14.30 A process manager's root is its trigger's correlation id.** A
PM instance's stream is (the PM's domain, the trigger's edition, the
trigger's `correlation_id`), and its root IS that correlation id,
unchanged: no derivation (no hash, no UUIDv5) and no text fallback. The
`ProcessManagerService` comment (`process_manager.proto`, Stream) and
`Cover.root` say so, and `buy_in.proto` no longer says the root is
"derived from it by core". Carries over prior angzarr core's decision D-11
(`CorrelationRootExt::correlation_root`), whose UUID branch passed a
correlation through unchanged; its other branch, UUIDv5 of a non-UUID
("friendly") correlation, has nothing to apply to, because every
correlation is a 16-byte `UUID` since 9.1. Owner ruling, 2026-10-27.
- Why: the correlation already names the one cross-domain process the PM
  tracks, and replies route to the instance by it; using it as the root
  makes "this correlation's PM stream" a lookup, with no formula for core,
  the clients and annals to keep identical.
- Cost: a PM has one instance per correlation (per edition); a workflow
  needing two instances of the same PM under one correlation cannot have
  them.
- Aligns with: MassTransit's saga state machines, whose instance key is
  the `Guid` `CorrelationId` ("Saga instances are identified by a unique
  identifier (`Guid`), represented by the `CorrelationId` on the saga
  instance";
  <https://masstransit.massient.com/documentation/patterns/saga>, where
  masstransit.io's saga documentation now redirects).

> **Amended by 14.36 (pass 14, as amended):** "The root is the correlation" below is a convention only: a policy always names a PM command's root, keeping its trigger's correlation; a set `correlation_id` other than the cover's root is no longer malformed, so the start rule is the only rule a PM's coordinator adds to an aggregate's.

> **Amended by 14.37 (pass 14):** `RefusalResponse` is `oneof reason { refusal (1) | diagnostic (3) }`; its `message` (2) is deleted, unreserved: no text crosses. A pass-through refusal with no path is answered `NO_REFUSAL_HANDLER`, not `NO_FACT_HANDLER`.

**14.31 A process manager is a domain.** Owner rulings of 2026-10-27
(ruling 7 of the angzarr/annals common plan) and 2026-10-28 (rulings 7 and
9 as settled after the pm-inputs survey; two earlier drafts of this entry,
"facts in, facts out" and "facts only", are withdrawn). It also writes into
the spec the owner's ruling **P1** of 2026-10-26 ("a pm would calculate
the data needed for cross-domain commands, emit events with that data,
then sagas for those domains would fire the events"), which the protos
had never carried. Amends 2.2, 5.6, 12.10, 13.1, 13.2, 14.14, 14.20, 14.24
and 14.30.
- **A PM is just a domain.** Its inputs are COMMANDS, which it may refuse,
  and FACTS (timeouts, webhooks, refusal facts), which it never refuses.
  It has NO triggers: it subscribes to no domain, and the saga for
  (another domain, the PM's domain) turns that domain's events into
  commands to the PM. Its only output is its own events (P1): it sends no
  commands. It is served exactly as an aggregate is: its business process
  implements `CommandHandlerService` and its coordinator serves
  `CommandHandlerCoordinatorService` for its domain. So
  `ProcessManagerService`, `ProcessManagerCoordinatorService`,
  `ProcessManagerHandleRequest` and `ProcessManagerHandleResponse` are
  deleted, unreserved (6.6); `process_manager.proto` keeps only the
  comment that says what sets a PM apart: its root and its start rule.
  Its `(command)` entries are declared like an aggregate's, and `Handling`
  applies to its commands as to any domain's.
- **The root is the correlation (14.30 amended; a convention only, 14.36
  as amended).**
  A PM instance's root is its correlation id, unchanged. A command or fact addressed to a PM names
  the instance in its cover; a `correlation_id` left unset is given the
  root, and one set to anything else is malformed. A saga addressing a PM
  therefore names the instance its trigger's correlation names. This is
  the one pipeline rule a PM's coordinator adds to an aggregate's.
- **Refusals (2.2 amended; owner's rulings, 2026-10-28; plan ruling 7,
  "REFUSAL WIRING").** In the owner's words: "saga calls foreign command
  handler, which refuses. saga then calls its domain command handler and
  passes it a fact (that the foreign CH refused)". A saga's target, an
  aggregate or a PM alike, refuses a saga's command as it refuses any
  command (a business rejection, `FAILED_PRECONDITION`) and records
  NOTHING. The refusal goes back to the SAGA, which builds ONE unrefusable
  refusal fact for its OWN source domain; that domain's fact handler
  decides what the refusal means and records its own events.
  - **A typed refusal object.** "The base CommandRefused fact is created
    by the saga. It will have an Any type to pack the foreign refusal
    object into. The foreign refusal object is business-specific code. The
    refusal object is passed back to the saga by the command-refused
    return type." Which refusal objects a command's handler may return is
    named by an ANNOTATION, like `emits` (the owner's ruling, for
    consistency): `CommandOptions.refuses` (4), `repeated string`, the
    fully-qualified refusal types, messages of the command's own domain,
    in exactly `emits`' form (it names the types directly, as `emits` does,
    not a wrapper message). When set, the generated handler returns its
    events or one of those typed refusals; when empty, a raw refusal
    payload (`Any`) or a message only. The client library packs the chosen
    refusal object, the concrete message, into the status details as an
    `Any`; and the refused saga receives `RefusalResponse { refusal,
    message }` (`types.proto`: `refusal` the packed object; `message` the
    status message, which the transport always carries, kept for the
    translating callback and for a dead letter but never forwarded).
    Generation fails, mirroring `emits`' references, on a `refuses` type
    that does not resolve or is not a message of the command's own domain.
    (The draft's `<Command>Refusal` naming convention and its orphan-name
    lint are withdrawn.)
  - **The saga builds the fact, so the coordinator calls it in both
    modes.** `SagaService.OnRefused(Refusal { event, command, response })
    returns (OnRefusedResponse)`. Pass-through (the default): the saga's
    generated code, with no user code, answers the standard
    `CommandRefused { command, refusal, trigger }` and nothing else
    (`refusal` the typed object still packed; `trigger` the triggering
    event's `EventRef`), and the source domain's command handler has a
    generated dispatch by the foreign command's type,
    `on_refused_<Command>(refusal, state) -> events`, where its author
    writes the reaction and unpacks the refusal object; the source imports
    the foreign protos (accepted). Translate: the saga's callback
    `on_refused_<Command>(Refusal)` reads the typed refusal object and
    returns a DOMESTIC fact, so the source never refers to the foreign
    protos. **This is why translate exists** (owner's ruling): since
    `CommandRefused` carries only the foreign object, with no reason or
    message, a domain that does not want to unpack a foreign object, or
    import foreign protos, has the saga unpack it there and hand over a
    domestic fact.
  - **The switch is the CLI's only.** "cli may have to have that switch,
    as it's compile time." angzarr-cli selects pass-through or translate
    per saga or per saga command, as a flag and as a build-config entry;
    pass-through is its default, and selecting translate makes the saga's
    callback for that command required, so a missing one fails generation
    (or the build). No proto option carries the mode, and nothing about it
    is visible at run time beyond which fact type arrives.
  - **No declaration of what a saga sends.** "Declaring commands it may
    send is a mistake, period." So there is no `sends`; and the source's
    `on_refused_<Command>` dispatch is inferred from the handlers it
    defines (the handler registration is the declaration, as for facts),
    so there is no `refusals` either (the owner's ruling, accepting the
    drafter's choice). Consequence,
    stated plainly: the generator can no longer check refusal coverage
    against what a saga sends. A refusal with no path, a pass-through
    `CommandRefused` whose command type the source defines no handler for,
    is caught only at RUN time: answered `NO_FACT_HANDLER`, dead-lettered
    and alerted. What the generator can still check: the `refuses`
    diagnostics above, and that a command selected for translate has its
    callback.
  - **Identity: the refused command's id.** The refusal fact's
    `command_id` IS the refused command's `command_id`, in both modes, with
    no prefix and no derivation; its `fact_origin.external_id` is that id's
    canonical text (accepted). One id therefore appears in two streams by
    design: never applied in the foreign (target) stream, which recorded
    nothing, and recorded as the refusal fact in the domestic (source)
    stream. Both ends deduplicate on it.
  - **The exact stream (owner's ruling).** A refusal fact is accepted only
    by the exact stream its trigger `EventRef` names: domain, root and
    edition. The coordinator addresses it there; a fact for any other
    stream is a saga bug, and every coordinator refuses it.
  - **Mechanics.** The coordinator stamps the fact's `causation_id` (the
    triggering event) and the trigger's correlation, and writes
    it as a new outbox entry in the transaction that clears the command's
    entry; a crash retries the step. annals makes the same calls directly,
    in the chain. Only a business rejection reaches `OnRefused`;
    retryable failures are retried and any other terminal failure is a
    bug, dead-lettered and alerted. The fact is unrefusable, so
    compensation cannot loop.
  - **Owner's rulings (2026-10-28, accepted):** the `refuses` annotation
    (above); `RefusalResponse { Any refusal; string message }`; the
    source's `on_refused_<Command>` dispatch inferred from the handlers it
    defines, with no `refusals` declaration. A refusal with no path is
    dead-lettered for a human and alerted; a failing translating callback
    is dead-lettered and alerted like any handler failure; a fact its
    source cannot ingest is dead-lettered and alerted at the source.
  - **A context object was considered and deferred.** The owner first
    asked for an opaque context the saga could attach to a command and get
    back in the callback, then judged it unnecessary complexity: a
    stateless saga's event, command and response already carry everything
    it used, except data it used but left out of the command, and the fix
    for that is to put the data in the command. Taking one struct,
    `Refusal`, keeps a `context` field addable later without breaking saga
    code. Nothing extra rides in the outbox entry.
- **The one exception to "a saga never delivers a fact".** A saga's
  business code still emits Commands only (`SagaResponse.commands`). The
  rule that a coordinator refuses a Fact carrying `causation_id` gets
  exactly one exception: a refusal fact, addressed to the exact stream
  its `causation_id` names (domain, root and edition: the stream of the
  saga's triggering event), whose
  `command_id` is the refused command's rather than a derivation.
- **Start rule (B1, adapted; owner's ruling of 2026-10-28, accepted).** Only input types
  (command or fact) the PM declares as starting (`CommandOptions.starts`,
  3; advertised as `ComponentDescriptor.starting_types`, 7) may start an
  instance. Any other input for a correlation with no instance is not
  delivered, decided by the coordinator before the handler by the type URL
  after upcasting: a FACT is skipped silently (answered `APPLIED`, no
  events, nothing dead-lettered or alerted). A COMMAND is refused:
  `FAILED_PRECONDITION` with an `ErrorInfo` reason `PM_NO_INSTANCE`,
  recording nothing (the drafter's proposal, accepted by the owner).
  Reasons: a
  command is refusable, and a silent `APPLIED` would tell the sender a
  command took effect that did not; a saga's refused command yields its
  refusal fact for the saga's source, which decides what an unstarted
  process means for it, by the same mechanism as every other refusal (or,
  with no handler there, it is dead-lettered for a human). The alternative, a silent skip as for a fact, was not taken. A
  PM should declare as starting every input that can arrive first.
  `starts` on an aggregate's entry fails generation; a PM with no starting
  input draws a generator warning (the owner's ruling); a non-PM descriptor listing
  `starting_types` is refused like one with an empty `rules_version`.
- **Deduplication and the handler context.** By `command_id` and by fact
  id (a fact's `command_id`, derived from its `fact_origin`), on the PM's
  stream, before the handler runs, as for any domain. One handler context
  carries the input's identity (its `command_id`, its `fact_origin` for a
  fact, its correlation, the instance's root). There is no trigger:
  `EventMeta.triggering_event` (18) is deleted, unreserved, with its index
  and the `find_triggered` lookup, and `EventMeta.causation` keeps one arm,
  `command_id` (13.1 and 13.2 amended; 13.2's "trigger-caused events carry
  no command" has no referent left). `EventConsumer.applies` (3), which
  told a PM's own fold from a trigger, is deleted, unreserved; an `(event)`
  entry naming a PM with a source domain fails generation.
- **Failures.** A failing PM fact handler is a bug: the fact is
  dead-lettered and alerted, a waiting sender answered `PARKED`. A command
  handler failing with anything but a business rejection is a bug too,
  handled as for an aggregate (a saga's command dead-lettered and alerted).
- **Outputs are the PM's own events.** `ProcessManagerHandleResponse.commands`
  (2) is deleted with the message. To act on another domain a PM records
  an event carrying that command's data, and the saga for (the PM's
  domain, that domain) builds the command (14.23, 14.24).
  `ComponentOptions.output_domains` (6) is deleted, unreserved, and
  `output_domain` is SAGA only (ruled).
- **The outbox is polymorphic.** Owner's ruling, 2026-10-28: "leave it; if
  we need an outbox it should be polymorphic". 5.6's transient outbox is
  one transactional outbox naming no component kind: any component whose
  output leaves its own stream stores that output atomically with its
  source checkpoint, dispatches it, then clears it, and redelivery re-sends
  it verbatim. Today the saga is the only user, for its commands and its
  rejection facts (written as a new entry in the transaction that clears
  the refused command's). A PM needs none:
  its only output is its own events, and it consumes no stream, so it has
  no checkpoint.
- **What sagas now do:** carry every event a PM must hear of into the PM,
  as commands, and every PM decision out of it, as commands; and deliver
  any refusal of their commands to their own source domain as a fact,
  passed through or translated. In the
  blackjack example, `TableBuyInSaga` (table -> buy-in: `StartBuyIn`, the
  starting input, and `RecordPlayerSeated`) and `PlayerBuyInSaga` (player
  -> buy-in: `RecordFundsHeld`, `RecordFundsCaptured`) feed the PM;
  `BuyInPlayerSaga` (buy-in -> player: `HoldFunds`, `CaptureFunds`) and
  `BuyInTableSaga` (buy-in -> table: `ConfirmSeat`, `ReleaseSeat`) carry
  its decisions. Two refusals run end to end, one per mode. Pass-through:
  the wallet refuses `HoldFunds` and records nothing, `BuyInPlayerSaga`
  forwards `CommandRefused` packing the wallet's `InsufficientFunds`, the
  buy-in's `on_refused_HoldFunds` unpacks it and records `BuyInFailed`,
  and `BuyInTableSaga` releases the seat. Translate (selected for
  `ConfirmSeat` by the build config): the table refuses `ConfirmSeat` with
  `SeatNotConfirmable`, `BuyInTableSaga`'s callback reads it and returns
  the buy-in fact `SeatConfirmationRefused`, the PM records `BuyInSeatLost`, and
  `BuyInPlayerSaga` releases the hold.
- **Withdrawn with the earlier drafts:** triggers as a PM input and their
  dedup by `find_triggered`; the `cause` oneof; the facts-only PM; sagas
  forwarding facts to a PM, and the saga contract change that allowed it;
  the reaction-origin fact id; the trigger-page proposal (which page of a
  saga's trigger book is the trigger stays open, backlog OB-6).
- **Drafter's choices.**
  - Accepted by the owner on 2026-10-28 (owner's rulings):
    - the correlation names the instance; a failing PM handler is
      dead-lettered and alerted; for B1, the `starts` / `starting_types`
      naming, the upcast type-URL match and the silent skip of a fact;
    - the start rule for a non-starting COMMAND: refused
      (`FAILED_PRECONDITION`, `PM_NO_INSTANCE`), recording nothing;
    - the callback failure rules: only `FAILED_PRECONDITION` reaches the
      callback; a refused command with no callback is dead-lettered and
      alerted; a failing callback is dead-lettered and alerted;
    - the deletions and shapes: `ProcessManagerService`,
      `ProcessManagerCoordinatorService` and their messages (a PM is
      served by `CommandHandlerService`; `process_manager.proto` is
      comment only); `EventMeta.triggering_event`; `EventConsumer.applies`;
      `causation` as a one-arm oneof; `Handling` on commands to a PM, as
      on an aggregate's;
    - the names `on_refused` (the handler prefix), `Refusal { event,
      command, response }`, `RefusalResponse` and `OnRefused`, kept;
      `RefusalCallback`, `RefusalFact`, `refusal_types` and the
      `(on_refused)` option were confirmed too, then replaced by the
      refusal-wiring ruling (below);
    - the refusal wiring (plan ruling 7 and the rulings that refined
      it): the saga builds the fact (so `OnRefused` serves both modes);
      the typed refusal object, packed as an `Any`; pass-through by
      default and translate as the CLI selects, with no proto option; no
      declaration of what a saga sends; the refused command's id as the
      fact's id, and its canonical text as the `external_id`;
    - the names `CommandRefused`, `RefusalResponse` and
      `OnRefusedResponse`;
    - (2026-10-28, later) `CommandRefused` is only `{ command, refusal,
      trigger }`, the reason translate exists; and a refusal fact is
      accepted only by the exact trigger stream, root included;
    - (2026-10-28, final) typed refusal objects named by the `refuses`
      annotation, in `emits`' form, with `emits`-style generation errors
      (an unresolved type, or one from another domain); `RefusalResponse
      { Any refusal; string message }`; the source's `on_refused_<Command>`
      dispatch inferred from its handlers, with no `refusals` declaration;
      and PMs declaring their starting inputs (B1), with a lint warning
      when a PM declares none.
  - Removed by the refusal-wiring rulings: the `(on_refused)` option and
    `RefusalCallback` on fact messages, `RefusalFact`,
    `ComponentDescriptor.refusal_types`, the `"angzarr-refusal:"` prefix
    and its derivation; then `ComponentOptions.sends`, `SagaSend`,
    `refusal_fact` and the exactly-one-path rule and lint; and
    `ComponentOptions.refusals` (inferred instead); then
    `CommandOptions.refused_with`, and `CommandRefused`'s `reason` and
    `message`; then the `<Command>Refusal` naming convention and its
    orphan-name lint (replaced by `refuses`).
  - Still for the owner to confirm:
    - in the example, the refusal objects `InsufficientFunds` and
      `SeatNotConfirmable`, the build config selecting translate for
      `ConfirmSeat`, the command names (`StartBuyIn`, `RecordFundsHeld`,
      `RecordPlayerSeated`, `RecordFundsCaptured`), the saga names
      (`TableBuyInSaga`, `PlayerBuyInSaga`, `BuyInPlayerSaga`,
      `BuyInTableSaga`), `BuyInFailed`, `PHASE_FAILED` and
      `failure_reason`, and stale steps accepted as no-ops rather than
      refused.
- **What PMs were for, and where each warrant now lives.** The
  2026-10-19 `process_manager.proto` warranted a PM by five things; each
  is still served:
  - its own workflow state, not derivable from aggregates: the PM is a
    domain, whose stream and state are its own;
  - status queries ("show all pending fulfillments"): the PM's own
    events, read and projected like any domain's;
  - timeouts and scheduling: facts addressed to the PM (a timer or a
    webhook), never refused;
  - reacting to several domains: sagas from those domains, sending the PM
    commands;
  - tracking the replies to the steps it starts: sagas into its domain for
    the replies, and the refusal facts of its outbound sagas (passed
    through, or translated) for the refusals.
  The cost, in the owner's terms: the workflow's "what to send next"
  moves out of the PM into its outbound sagas, so a PM's events must carry
  enough data for those sagas to build each next command (a saga takes
  everything from the event and never looks anything up). And, in the
  owner's words, "if we want all that in a single process again, we can
  use an annals domain for that": where a workflow's logic should live
  together, the PM and its outbound sagas can be deployed as ONE local
  (annals) domain, a single process in which the saga hops are chained
  calls in one unit of work. That recovers the old single-handler cohesion
  without a special PM shape, because components are deployment-agnostic:
  they assume nothing about distribution (plan ruling 13).
- Why: one input shape for every domain (commands and facts) and one
  output shape for every stateful component (its own events); sagas are
  the one place where one domain's events cross into another; a refusal
  reaches the one domain that asked for the refused step, durably and
  unrefusably, with no side channel and no stateful sender.
- Cost: every cross-domain step is a saga hop each way, and one saga per
  (source domain, PM) pair to deploy; every domain whose events feed a
  domain whose sagas' commands can be refused handles their refusals,
  importing the foreign protos in pass-through mode, and a missing handler
  is found only at run time (a dead letter), since nothing declares what a
  saga sends; a refusal is recorded
  only by the
  source, not by the refusing domain, so the target's stream never shows
  what it turned away.
- Aligns with: the PM-as-domain shape of IDDD (process state in an
  aggregate fed commands by listeners), Akka (an entity with command
  handlers) and EventFlow (sagas as event-sourced aggregates), per the
  pm-inputs survey; and the event-carried-state idiom the owner adopted in
  P1. Diverges knowingly from the frameworks whose sagas (their process
  managers) consume events and send commands themselves. Verified against
  each framework's documentation on 2026-10-28:
  - Axon Framework 4.10: the saga example's event handler calls
    `commandGateway.send(new PrepareShippingCommand(...))` and
    `commandGateway.send(new CreateInvoiceCommand(...))`
    (<https://docs.axoniq.io/axon-framework-reference/4.10/sagas/associations/>).
    Axon Framework 5 has no saga yet ("Sagas do not have a replacement yet
    in Axon Framework 5",
    <https://docs.axoniq.io/axon-framework-reference/5.0/sagas/implementation/>).
  - NServiceBus: a saga "should only interact with its own internal state
    and send or publish messages", and for external work it should "Send
    (command) messages to dedicated message handlers"
    (<https://docs.particular.net/nservicebus/sagas/>).
  - MassTransit: a saga "drives the next steps in the process by
    publishing events or sending commands"
    (<https://masstransit.massient.com/documentation/patterns/saga>).
  The IDDD, Akka and EventFlow alignment is the survey's reading, not
  re-verified for this entry.

> **Amended by 14.36 (pass 14):** a fork is at the sequence its `EditionCreated.parent_sequence` states, at or below main's head for that stream (above it is a conflict), with no implicit "head at write time" rule. On arrival the system layer records the head it read; an origin `ForkStream` states its sequence. The fork point is per stream; no cross-stream snapshot is promised.

**14.32 Editions are per-stream forks.** Owner rulings, 2026-10-28 (plan
ruling 14, and the rulings on its first draft). Supersedes 6.5's
administrative create and edition record, and EA-3's whole-system
divergence default. Every fork is per stream: there is no global position
and no fork at one (14.35).
- **An edition is a set of per-stream forks.** Creating edition X forks an
  origin stream S = (D, main, R): an `EditionForked { edition,
  parent_sequence, propagated_from, forked_by }` event
  (`types.proto`, the `editions` region) is appended to (D, X, R) at the
  sequence it states, by default S's NEXT sequence (main's head), and at
  most that (14.36). It is the first event of X's version of S, and its
  sequence (the fork sequence) marks main's end and X's start for that
  stream. It is a framework event: no business code ever sees it, and its
  own `command_id` is framework-derived, never that of the command whose
  arrival made it.
- **Read rule, per stream.** (D, X, R) reads main's events below its own
  fork sequence, then X's own events. Main's later events never reach it.
- **The fork travels with the data (ruled).** The owner: "it's not lazy,
  but it is eventually consistent. Edition creation events propagate on
  the same system as data flows". When a SAGA's command in X reaches a
  stream with no fork in X, that arrival is the propagation: the
  coordinator appends the stream's `EditionForked` at the stream's main
  head as it read it (a race with main leaves the fork where it says;
  14.36), with
  `propagated_from` = the fork event of the stream the saga reacted to and
  `forked_by` = the arriving command's id, then handles the command.
  Streams X's activity never touches are never forked; the data flow is
  the only bound. A process manager is a domain: saga commands into it
  carry the fork like any other, and nothing is PM-specific.
- **From outside, refuse until propagated (ruled).** A command or fact that
  is not a saga's, addressed in X to a stream with no fork in X, is refused
  `FAILED_PRECONDITION` with `ErrorInfo` reason `EDITION_NOT_FORKED` (the
  owner accepted the code), writing nothing; `ForkStream` forks such a
  stream explicitly. A query or subscription of an unforked stream reads
  main's version and forks nothing (ruled).
- **No metadata store.** The edition registry is deleted: `Edition`,
  `CreateEditionRequest` and `CreateEdition`. `EditionAdminService`
  (`meta.proto`) is `ForkStream` (append an origin fork; the first creates
  the edition; an already-forked stream is `ALREADY_EXISTS`),
  `ListEditions` (a query over X's own fork events, answered as derived
  `EditionSummary` rows) and `DeleteEdition` (below). An edition is known
  while any fork event of it exists, which is a query over the edition
  stores, cacheable; one never created,
  or deleted, is refused `NOT_FOUND`. Where an edition's rows live is
  configuration. (Store placement, `EditionSummary`, `ALREADY_EXISTS` and
  existence as a cacheable query were accepted by the owner.)
- **Main knows nothing of an edition (the owner's invariant).** "All
  data/messages for the edition should exist in the EDITION's
  stream/data store. The main timeline should have no knowledge of
  edition create or delete." `EditionForked` lives only in the edition's
  streams (D, X, R), in the edition's configured store, and every row of
  X carries X in its key. Nothing is appended to, recorded in, indexed against or read
  from main's streams for an edition's lifecycle, except that a fork reads
  main's head (its fork sequence) and a stream in X reads main's events
  below it. `propagated_from` names a stream in X, never in main;
  `ListEditions` and the existence check query X's own events; X's outbox
  entries, positions and deliveries are X's processing, apart from
  main's. Main's coordinators, projectors and readers behave as if no
  edition existed: creating and deleting an edition leaves main's
  streams, outbox and positions byte-for-byte unchanged.
- **Deletion: sequenced, then every row tagged X removed (the owner's
  rulings).** In the owner's words: "deletion will have a seq number that
  needs to be after the work in flight", "the retries on the timer will
  already be handled by sequencing", "don't create new stuff for it", and
  finally: every row of X carries X in its key, so `DeleteEdition(X)` is
  sequenced after X's in-flight work, then removes every row tagged X
  from X's store(s), its own sequencing included. Nothing remains: no
  tombstone, no per-stream deleted state, no `NOT_FOUND`-after-delete
  state beyond X being unknown again, nothing travelling to forked
  streams, no coordinator querying fork events.
  - **The sequence point needs no marker (the owner's ruling; superseded
    by the amendment below, and there is no commit position, 14.35).**
    `DeleteEdition` takes X's commit position at the call; the removal runs once all of X's work below it has completed (X's outbox
    holds no entry below it, and X's deliveries and subscriptions have
    passed it). That is ordering, not polling; nothing retries. So no
    `EditionDeleted` event is written (and the message is deleted): the
    position the call takes is the sequence. The removal takes every row
    tagged X, including any written after the point.
  - A later saga command in X re-forks its target like any arrival, so X
    reappears in `ListEditions` for the user to delete again.
  - A delete that genuinely fails (rows that cannot be removed) is
    dead-lettered and alerted, like any failed delivery.
  - **Known limitation:** X's work that never completes (for example
    commands of X held in an undeployed saga's outbox) holds the delete
    back; the edition stays visible in `ListEditions` while it waits, and
    the user can act on it there.
- **Withdrawn with the earlier drafts:** eager propagation of a fork from
  the origin along recorded reaction edges, the saga coordinators' edge
  table, the hop limit (8) and fan-out alert (1,000), the 13.3 amendment
  for the edge rows (13.3 stands as it was), on-demand forks for any input,
  `EditionForked.on_demand` (replaced by `forked_by`), the arrival fork's
  re-check of a delete with its `NOT_FOUND`, any retry timer for a
  delete, and the `EditionDeleted` tombstone that travelled the saga
  flows (with its per-stream deleted state and its `propagated_from`).
- **Accepted by the owner:** the shapes, `EditionForked` with `forked_by`,
  and the fork event's own framework-derived command id.
- **Owner's rulings, 2026-10-28 (all the drafter's choices settled):**
  the spec as drafted is approved; `EditionDeleted` is dropped, and the
  delete's sequence point is X's commit position at the call, with no
  marker event (superseded by the amendment below; 14.35); `EditionForked`
  with `forked_by`, the fork event's own framework-derived command id, `EDITION_NOT_FORKED`, store placement by
  configuration, `EditionSummary`, `ALREADY_EXISTS` on an already-forked
  stream, and existence as a cacheable query over fork events are all
  accepted.
- Why: an edition forks only what its activity touches, when the data
  reaches it, at that stream's own point, with no second source of truth
  beside the events, and nothing to bound but the data flow itself.
- Cost: an edition's streams diverge at slightly different moments
  (eventually consistent); a caller
  that wants to address a stream the edition has not reached must fork it
  first; existence checks query the edition stores; a deletion completes
  eventually, in order, and waits on any of X's work that never
  completes.
- Aligns with: copy-on-write branching of event streams (a fork is the
  stream's first event in the branch), and with angzarr's own rule that a
  reaction stays in its trigger's edition.

> **Amended (the owner's later rulings, 2026-10-28): meta-events, and
> deletion as an event.** Where 14.32 above says `EditionForked`, read
> `io.angzarr.v1.meta.EditionCreated`; where it says deletion removes every
> row tagged X in one sequenced operation, read the sequence below. It
> supersedes "Deletion: sequenced, then every row tagged X removed" and its
> "no `EditionDeleted`" sub-ruling.
> - **Framework meta-events have a reserved namespace,**
>   `io.angzarr.v1.meta` (`meta/events.proto`). A meta-event is a real
>   event, appended and stamped like any other with a framework-derived
>   `command_id` of its own; stores and coordinators may recognise one by
>   its type URL and act on it; business handlers never see one. Only the
>   meta-events something needs are defined: `EditionCreated` (the fork
>   event, renamed; the owner: "the fork event is renamed EDITION
>   CREATION") and `EditionDeleted`.
> - **Deletion is an event that exists in its domains** (the owner:
>   "delete edition / EditionDeleted needs to be an EVENT, to propagate via
>   sagas to other domains"; "it needs to exist in its domains"). Per
>   stream of X, in this order: (1) RECORDED: `DeleteEdition` appends
>   `EditionDeleted` to X's origin streams, and each stream the deletion
>   reaches records its own, in its own domain, in sequence after its
>   earlier work; (2) PROPAGATED: the recorded event travels onward through
>   that domain's saga flows to the next domains, like any event
>   (angzarr automates it; annals does it in its in-process chain of
>   committed steps); (3) REMOVED: only after it has propagated onward (its
>   outgoing saga steps and outbox entries for it have completed) are the
>   stream's rows tagged X removed, the `EditionDeleted` event included.
>   Nothing remains. A removal before propagation is a bug.
> - `EditionDeleted { edition, propagated_from, deleted_by }`: the stream's
>   own sequence orders the deletion after its earlier work; the last two
>   mirror `EditionCreated`'s propagation fields.
> - **Known limitation, with no new mechanism:** a stream of X that the
>   deletion cannot reach through the saga flows keeps its rows and stays
>   visible in `ListEditions`, for the user to act on.
> - **After deletion, a later arrival is refused** (the owner, revising
>   the draft's D6): once an edition is deleted, a later arrival in it (a
>   saga command, or a step's position on a removed stream) is refused
>   `NOT_FOUND`, because the edition does not exist; it re-creates neither
>   the stream nor the edition. Only an explicit create (`ForkStream`)
>   brings the name back. This replaces 14.32's "a later saga command in X
>   re-forks its target like any arrival, so X reappears in
>   `ListEditions`". A store knows it from its rows alone (flagged): an
>   edition is DELETED, or being deleted, while any stream of it holds an
>   `EditionDeleted`, and does not exist once no `EditionCreated` of it
>   remains anywhere; an arrival's creation (one with `propagated_from`)
>   and a position on a stream with no rows of the edition are refused in
>   either case.
> - Main is still never written: all of this lives in X.

> **Amended again (the owner's rulings, 2026-10-28): who owns the edition
> lifecycle.** The ROUTER never sees a meta-event; the ANGZARR SYSTEM
> LAYER owns the edition lifecycle (the owner: "edition is the angzarr
> SYSTEM").
> - **The router** is pure business dispatch: domain, process manager and
>   policy handlers; typed refusals and the refusal path; the dedup
>   DECISION; the process manager start rule; and one edition rule, that
>   a policy's commands stay in their trigger's edition.
> - **The angzarr system layer** is ONE shared piece of system code, a
>   transport-free crate in angzarr-core (`angzarr-io/angzarr`; working
>   name `angzarr-system`; placed there by 14.36), which BOTH runtimes
>   (the angzarr-embedded kernel, locally; core's coordinator,
>   distributed) call around the router's
>   business dispatch. It is neither the router nor reimplemented per
>   runtime. It owns everything else of an edition:
>   - **Creation on arrival:** when a policy's command in X arrives at a
>     stream with no rows in X, the system layer writes that stream's
>     `meta.EditionCreated`, then hands the command to the router as an
>     ordinary command in X.
>   - **Refusals, before the router is called** (the system layer's): outside input to an
>     unforked stream, `FAILED_PRECONDITION` reason `EDITION_NOT_FORKED`;
>     an arrival in an edition that is deleted, or being deleted,
>     `NOT_FOUND` reason `EDITION_NOT_FOUND`; a meta-event payload
>     arriving from outside the system layer, `INVALID_ARGUMENT` reason
>     `META_EVENT_FROM_OUTSIDE` (flagged: the name and status). Nothing
>     is written in any of them.
>   - **Deletion's transit:** the system layer writes `meta.EditionDeleted` in
>     X's origin stream(s), then propagates it along the streams its
>     policies reached in X, as its own write in each (recorded
>     in each, propagated onward, then removed); a stream with nothing of X
>     left is skipped, and nothing is created or forked there. It is not
>     carried as a policy command.
>   - **Filtering:** the system layer filters meta-events out of everything
>     policies and handlers see; no business code runs for one.

**14.33 The stateless event-to-command mapper is a POLICY, not a saga.**
Owner ruling, 2026-10-28. Canon calls a saga stateful: what angzarr has
called a saga (it reacts to one domain's events and builds commands for
another, keeping no state of its own) is a POLICY, and the stateful
coordinator canon calls a saga is angzarr's process manager, a domain
(14.31). A mechanical rename, with no behaviour change:
- `saga.proto` is `policy.proto`; `SagaService` is `PolicyService`,
  `SagaCoordinatorService` `PolicyCoordinatorService`, `SagaResponse`
  `PolicyResponse` (its HTTP binding `/v1/policy/execute`); `Refusal`,
  `OnRefused` and `OnRefusedResponse` keep their names.
- `ComponentKind.COMPONENT_KIND_SAGA` (2) is `COMPONENT_KIND_POLICY`, the
  same number.
- The examples' `sagas.proto` is `policies.proto`, and its `*Saga` state
  messages are `*Policy` (`TablePlayerPolicy`, `BuyInPlayerPolicy`,
  `BuyInTablePolicy`, `TableBuyInPolicy`, `PlayerBuyInPolicy`).
- angzarr-proto's `ids::reaction_command_id` is `ids::policy_command_id`
  ("reaction" stays out of code; the derivation and its namespace are
  unchanged, so every derived id is the same).
- Every comment, field note, region, feature (`policy_refusal.feature`,
  the blackjack framework tier's `policy.feature`, the steps' "a policy")
  and the ports' wording follows. `#[process_manager]` and the PM naming
  stay as they are.
- Earlier entries keep their text: where they say "saga" for the
  stateless mapper, read "policy".
- Why: one word per concept, matching the literature: a saga keeps state
  across steps; this component never does.

**14.34 The proto says whether an input is a command or a fact.** Owner
ruling, 2026-10-28. `CommandOptions.fact` (`options.proto`, field 5, a
bool): unset, the `(command)` message is a COMMAND, which its handler
decides and may refuse; set, it is a FACT, something that already
happened, which its handler records and cannot refuse.
- Why: angzarr-cli's scaffold writes `#[handles_cmd]` or `#[handles_fact]`
  from it, and the generator checks a component's markup against the
  proto (a `#[handles_cmd]` on a fact, or a `#[handles_fact]` on a
  command, fails generation), so the proto is the one statement of it.
- `refuses` on a fact fails generation: a fact cannot be refused.
  `starts` applies to both: a process manager may start from a command or
  from a fact. `emits` applies to both.
- Flagged: a bool rather than an enum (`InputKind { COMMAND, FACT }`): two
  values, with command the default, need no third; an enum would leave
  room for a kind not yet known.
- The examples mark the buy-in's `SeatConfirmationRefused` (its translated
  refusal fact) as a fact. The buy-in example declares no timeout or
  expiry input yet.

**14.35 No global position, ever: ordering is per stream.** Owner ruling,
2026-10-28, hard. angzarr has no global or store-wide position, now or
later: events are ordered within their stream only, and no store keeps an
order across streams.
- **The commit position is removed.** `EventStore::commit_position`,
  `Editions::fork_point`, their dyn twins, `MemoryStore`'s bookkeeping for
  them and the suite's checks of them are deleted from angzarr-ports.
  `ForkStreamRequest.commit_position` (2), `EditionSummary.commit_position`
  (4), `meta.EditionCreated.commit_position` (3) and
  `meta.EditionDeleted.commit_position` (2) are deleted, unreserved (6.6), and `ForkStream` loses its `FAILED_PRECONDITION` for a
  time-based fork.
- **The time-based edition fork is dropped entirely.** An edition is
  per-stream forks only (14.32): the origin at its own head, each stream
  a policy command reaches at its own head on arrival. Scenario C-0638 is
  retired.
- **Set-based validation uses the existing primitives.** A rule that spans
  streams ("usernames are unique") is a process manager's: a domain that
  keeps the state the rule needs and refuses or compensates a breaking
  claim. Reservation domains are a possible future option, seen as added
  complexity that process managers already cover. Dynamic Consistency
  Boundaries are not pursued at this time: DCB needs a globally ordered
  log, which angzarr does not have (`FUTURE.md`, Set-based validation).
- **The 2026-10-27 "commit-order ruling" was never the owner's.** The
  store-wide commit position came in with annals 074f7ff, whose commit
  message asserted an owner ruling the owner did not make; 14.32 took it
  in as its time-based option. Where earlier entries cite that ruling,
  read this one.
- Why: per-stream ordering is what the stores can keep cheaply and
  everywhere, in memory, in SQLite and distributed alike; a store-wide
  order is a single point of contention that nothing in angzarr needs.
- Cost: an edition's streams cannot be forked at one store-wide moment;
  a consistent cross-stream snapshot is not offered.

**14.36 A policy may name a process manager's root; a fork is where it
says.** Owner rulings, 2026-10-28. Amends 14.30, 14.31 and 14.32.
- **Correlation traces the causal chain.** A policy sends commands to
  foreign aggregates directly, and to process managers; its refusal facts
  go to its own source (14.31). Every command or fact a policy sends, to
  any target, carries its trigger's `correlation_id` unchanged.
- **An aggregate target:** the policy names the aggregate's root, as
  before.
- **A process manager target: naming the root was optional (superseded
  by the amendment below).** As first ruled, a policy could leave a PM
  command's root for the framework to fill with the trigger's
  correlation, or name another by an opt-in callback. The amendment below
  withdraws the optional root, the callback and the default: a policy
  always names the root, for every target.
- **What changes in 14.30 and 14.31.** A PM instance's root is no longer
  always its correlation: one instance may take inputs of several
  correlations, and its events carry each input's correlation, as any
  domain's do. The rule that a `correlation_id` set to anything other than
  the cover's root is malformed is withdrawn for every PM input, a
  client's included: such an input is delivered to the root its cover
  names, keeping its correlation. A `correlation_id` left unset on an
  input to a PM is still given its cover's root (14.31's rule, kept). So
  14.31's "the one
  pipeline rule a PM's coordinator adds to an aggregate's" is gone; the
  start rule (B1) is now the only thing a PM's coordinator adds. 14.30's
  cost, one instance per correlation, no longer holds. Scenario C-0598 is
  retired.
- **Where the shared framework code lives (14.32's second amendment
  amended; owner ruling).** The angzarr system layer (`angzarr-system`,
  the edition lifecycle) and the other shared coordinator crates live in
  angzarr-core (`angzarr-io/angzarr`) as transport-free crates, called by
  both core's coordinator and the angzarr-embedded kernel; they are not in
  angzarr-project. angzarr-project keeps only the contract: the protos,
  angzarr-proto and angzarr-ports.
- **A fork is at the sequence it states (14.32 amended).**
  `meta.EditionCreated.parent_sequence` is the fork point: the creation's
  own sequence, below which (D, X, R) reads main's events. Main's head is
  main's next sequence for that stream (its length). The store accepts a
  creation at any stated sequence at or below main's head, and refuses one
  above it as a conflict (`StoreError::Conflict`), writing nothing. There
  is no implicit "the head at write time" rule: a store never moves a fork
  to the head. A creation whose `parent_sequence` differs from its own
  page's sequence is malformed (`StoreError::MalformedCreation`,
  INVALID_ARGUMENT), writing nothing.
- **On arrival, the system layer records the head it read.** When a
  policy's command arriving in X creates its target's fork, the angzarr
  system layer reads that one stream's main head and writes the
  `EditionCreated` at it, with that `parent_sequence`. Policies never
  handle sequences. A race with main is harmless: if main appends between
  the read and the write, the fork still lands where it says, and the
  edition reads main's events below it only.
- **An origin states its sequence.** `ForkStream` names the sequence to
  fork its stream at: `ForkStreamRequest.parent_sequence` (3), a plain
  `uint64` the caller always states, 0 being a valid fork at the start;
  there is no "head when unset". One above main's head is the store's
  conflict, answered `ABORTED`, the spec's status for a failed
  test-and-set, writing nothing.
- **Per aggregate.** The fork point is per stream (one domain and root, in
  X). Each stream's fork is read and stated on its own, and nothing
  relates two streams' fork points: no cross-stream snapshot is promised
  (14.35).
- Text changed with it: `process_manager.proto` (Stream), `Cover.root`,
  `Cover.edition` and the command identity region and malformed list in
  `types.proto`, `PolicyResponse.commands` (`policy.proto`),
  `EditionCreated.parent_sequence` (`meta/events.proto`),
  `ForkStreamRequest` and the system layer's home (`meta.proto`,
  `meta/events.proto`), angzarr-ports' `EventStore` docs,
  14.32 above, and the site's process manager, editions and edition
  glossary pages. Scenarios C-0656 to C-0665, and C-0628's ForkStream
  now states its sequence; angzarr-ports' checks
  `a_fork_below_mains_head_lands_at_its_stated_sequence`,
  `a_fork_above_mains_head_is_a_conflict` and
  `a_creation_stating_another_parent_sequence_is_malformed`, with the
  new `StoreError::MalformedCreation`.
- Why: a set-based rule ("usernames are unique", 14.35) needs a PM
  instance keyed by what the rule is about, not by whichever workflow
  happened to trigger it, and the causal chain must still be traceable
  through it. A fork's point must be a fact the event states, not a
  property of when the write happened to run, so a race cannot move it.
- Cost: a policy naming a PM root must derive it from its event alone
  (a policy looks nothing up); a PM instance shared across correlations
  is a point of contention for those workflows. A fork below main's head
  is accepted silently, so a stated point that is wrong (too low) is not
  caught by the store.
- Aligns with: MassTransit's saga state machines, whose events may be
  correlated to an instance by a property other than the `CorrelationId`
  (`CorrelateBy`; knowledge, not re-verified); and with copy-on-write
  branching at a stated parent version.

> **Amended (the owner's rulings, 2026-10-28, after reviewing the
> router's tests): a policy always names the root.** In the owner's words:
> "don't differentiate process managers"; "do we need the root callback
> period, or is it unnecessary complexity? the policy is going to always
> have access to set the root"; and, of the default, "Drop it: a policy
> always sets the root". It supersedes 14.36's optional PM root, its
> `root_<Command>` callback and its framework-filled default. The fork
> rules above are unchanged.
> - **A policy names its command's root (`cover.root`) for EVERY target,**
>   aggregate or process manager alike. There is no kind-specific rule:
>   the router never knows the target's kind. A policy command with no
>   root is a policy bug for every target: refused `INTERNAL` with
>   `ErrorInfo` reason `POLICY_COMMAND_NO_ROOT` (extras `domain` and
>   `command_type`), dead-lettered and alerted, never delivered.
> - **No root callback and no default root.** Nothing fills in a root: the
>   trigger's correlation is no longer given to a PM command as its root.
>   14.30's "the root is the correlation" is a convention a policy may
>   follow by writing it (setting the root to its trigger's correlation).
>   C-0657 becomes the one any-target scenario (C-0665 is merged into it
>   and retired); C-0664 is retired. C-0658, C-0659 and C-0660 have the
>   policy set the root directly; C-0601 has its policy set the root to its
>   trigger's correlation. C-0666 pins `POLICY_COMMAND_OTHER_CORRELATION`.
> - **Kept:** every command or fact a policy sends carries its trigger's
>   correlation unchanged, and one carrying another correlation is a
>   policy bug, refused `INTERNAL` with reason
>   `POLICY_COMMAND_OTHER_CORRELATION`, dead-lettered and alerted. A PM
>   input whose correlation differs from its root is admitted (the
>   correlation-equals-root rule stays withdrawn). An unset correlation on
>   a PM input is still given its cover's root (14.31).
> - Why: one rule for every target, and none the router must tell apart
>   by kind; the policy already builds the command from its event, so
>   naming the root is no extra burden, and a callback and a default were
>   two ways to say what the policy can write directly.

**14.37 Errors carry a key and an argument map, never rendered English;
the input's acceptance time is delivered.** Owner rulings, 2026-10-28.
Amends 5.11, 14.2, 14.8 and 14.31. In the owner's words: "we should *not*
carry the full english text, but the key and the map".
- **The rule.** Every error angzarr sends is a KEY and an ARGUMENT MAP.
  Text is rendered only where it is displayed (a console, a UI, a client's
  `message()`), from a Fluent catalog keyed by the code. A diagnostic's
  display, in logs, is its code plus its args. No free text crosses any
  boundary: not a gRPC status message, not a dead letter, not a response
  field.
- **It covers handlers too.** A typed rejection is its refusal message
  (the `Any` of one of the command's `refuses` types): its type is the
  key, its fields the map. Any other rejection carries a diagnostic code
  plus args, its code being the reason. A handler bug carries a diagnostic
  code plus args too: the router answers it `UNHANDLED_HANDLER_ERROR`, with
  the handler's own code and args as its cause, and what escaped (an
  error's text, a panic's message) stays in the handler's own log. A
  panic's cause is `HANDLER_PANICKED`.
- **On the wire.** The gRPC status message IS the reason key, and the
  `google.rpc.ErrorInfo` (domain `angzarr.io`) carries the same key as its
  reason and the args as its metadata. Every distinct condition gets its
  own reason key: no two conditions share one and differ only by text. In
  a message, the key and map are `Diagnostic { code (1), args (2) }`
  (`types.proto`, the `diagnostic` region; `args` a `map<string,
  string>`). A wrapped cause is flattened into the args: the cause's code
  under the arg's name, each of its args under `<name>.<arg>` (`cause` =
  `annals-store-sql-io`, `cause.errno` = `10`), in `Diagnostic.args` and
  `ErrorInfo` metadata alike.
- **The router's reason inventory.** Built from angzarr-router's
  `crates/router/src/error.rs` and its call sites (branch `poc/dispatch`),
  reconciled with the router agent's proposal. Conditions that shared a
  reason and differed by English text get their own keys (details in the
  `ErrorInfo` metadata):

  | Old reason | Condition | New key (metadata) |
  |---|---|---|
  | `UNHANDLED_HANDLER_ERROR` | a fold fails on persisted events (`FOLD_FAILED` text) | `FOLD_FAILED` (`sequence` and `type_url`, or `first_sequence` and `last_sequence`; `state_type_url`; the fold's own failure as `cause`) |
  | `UNHANDLED_HANDLER_ERROR` | a fold fails on an event the command emitted (`FOLD_FAILED_EMITTED` text) | `FOLD_FAILED_EMITTED` (as `FOLD_FAILED`) |
  | `UNHANDLED_HANDLER_ERROR` | an error escaped a handler, or it panicked | `UNHANDLED_HANDLER_ERROR` (the handler's code and args as `cause`; `HANDLER_PANICKED` for a panic) |
  | `NO_HANDLER_REGISTERED` | a command type no handler claims, after upcasting | `UNKNOWN_COMMAND_TYPE` (`type_url`, `upcast_type_url`) |
  | `NO_HANDLER_REGISTERED` | a dispatch to a kind the business process does not host | `NO_COMPONENT_OF_KIND` |
  | `NO_HANDLER_REGISTERED` | a policy given a book of a domain it does not consume | `POLICY_SOURCE_OUTSIDE_INPUT_DOMAIN` (`domain`, `expected_domain`) |
  | `NO_FACT_HANDLER` | a fact type no handler claims | `NO_FACT_HANDLER` (`type_url`, `upcast_type_url`) |
  | `NO_FACT_HANDLER` | a pass-through `CommandRefused` the source has no `on_refused_<Command>` for | `NO_REFUSAL_HANDLER` (`command_type`) |
  | `DUPLICATE_REGISTRATION` | "a router hosts one component", and "this business process already hosts its one component" (the C ABI's one-at-a-time path): one condition | `DUPLICATE_COMPONENT` (`component`, `component_kind`) |
  | `DUPLICATE_REGISTRATION` | "a component has one upcaster chain" | `DUPLICATE_UPCASTER_CHAIN` |
  | `MISSING_COMMAND_BOOK` | a `Refusal` with no command | `REFUSAL_WITHOUT_COMMAND` |
  | `MISSING_COMMAND_BOOK` | a `Refusal` with no event | `REFUSAL_WITHOUT_EVENT` |
  | `MALFORMED_REFUSAL_FACT` (`reason` "no fact") | `OnRefusedResponse` holds no fact | `REFUSAL_FACT_MISSING` |
  | `MALFORMED_REFUSAL_FACT` ("set the fact's cover or handling") | the policy set the fact's cover or handling | `REFUSAL_FACT_ADDRESSED` |
  | `MALFORMED_REFUSAL_FACT` ("no page") | the fact has no page | `REFUSAL_FACT_NO_PAGE` |
  | `MALFORMED_REFUSAL_FACT` ("the page is not a Fact") | the page is a Command | `REFUSAL_FACT_NOT_A_FACT` |
  | `MALFORMED_REFUSAL_FACT` ("set the fact's identity") | the policy set the fact's identity | `REFUSAL_FACT_IDENTIFIED` |
  | `MALFORMED_REFUSAL_FACT` ("no refused command") | the refusal carries no refused command | `REFUSAL_WITHOUT_REFUSED_COMMAND` |
  | `MALFORMED_REFUSAL_FACT` ("no command_id") | the refused command carries no `command_id` | `REFUSED_COMMAND_WITHOUT_ID` |
  | `MALFORMED_REFUSAL_FACT` ("no triggering stream") | the refusal carries no triggering stream | `REFUSAL_WITHOUT_TRIGGER_STREAM` |
  | `ANY_DECODE_FAILED` ("failed to decode X", one text per message) | bytes that do not decode as the message expected: one condition | `ANY_DECODE_FAILED` (`message_type`) |
  | none (empty code; router-ffi) | a host callback's status bytes do not decode | `HOST_STATUS_UNDECODABLE` |
  | none (router-ffi) | a null pointer crosses the C ABI | `NULL_ABI_POINTER` (`argument`) |

  `MALFORMED_REFUSAL_FACT` and `DUPLICATE_REGISTRATION` are retired, and
  `NO_HANDLER_REGISTERED` no longer names an unknown type. The codes that
  were already one per condition keep their key and lose their English
  constant: `MISSING_RULES_VERSION`, `MISSING_STATE_TYPE`,
  `STARTING_TYPES_ON_NON_PM`, `DUPLICATE_COMMAND_HANDLER`,
  `NO_HANDLERS_REGISTERED`, `MISSING_COMMAND_BOOK`, `MISSING_COMMAND_PAGE`,
  `MISSING_COMMAND_PAYLOAD`, `MISSING_EVENT_BOOK_COVER`,
  `EMPTY_POLICY_SOURCE`, `PERSISTED_EVENT_CORRUPT`, `CONFLICT_UNRESOLVED`,
  `CONFLICT_OVERLAP`, `CONFLICT_RESOLUTION_UNSUPPORTED`,
  `POLICY_COMMAND_OUTSIDE_DESTINATION`, `POLICY_COMMAND_OUTSIDE_EDITION`,
  `POLICY_COMMAND_NO_ROOT`, `POLICY_COMMAND_OTHER_CORRELATION`,
  `PM_NO_INSTANCE` and `REFUSAL_FACT_WRONG_STREAM`. The `fold_message`
  metadata entry becomes the fold's `cause`.
- **Proto text fields become key + map.** Removed fields stay unreserved
  (6.6):
  - `RefusalResponse.message` (2) is deleted; `RefusalResponse` is
    `oneof reason { Any refusal = 1; Diagnostic diagnostic = 3; }`, a typed
    refusal or an untyped rejection's diagnostic;
  - `ProjectorFailure.message` (3) is deleted; `ProjectorFailure.diagnostic`
    (4) is added beside `code` (2);
  - `AngzarrDeadLetter.rejection_reason` (3), "Human-readable reason", is
    deleted; `AngzarrDeadLetter.reason` (16, a `Diagnostic`) is added;
  - `EventProcessingFailedDetails.error` (1) is deleted;
    `EventProcessingFailedDetails.failure` (5) is added;
  - `PayloadRetrievalFailedDetails.error` (5) is deleted;
    `PayloadRetrievalFailedDetails.failure` (6) is added;
  - in `dlq_admin.proto`, `StoredDeadLetter.rejection_reason` (5) and
    `details` (7, "free-form debug detail") are deleted and
    `StoredDeadLetter.reason` (15) added; `DeadLetterReplay.detail` (7,
    "Human-readable detail") is deleted and `DeadLetterReplay.reason` (8)
    added.
  - angzarr-ports' `Cause { code, message }` becomes `Cause { code, args }`,
    and `StoreError`'s `Display` is the code then its args, never English.
- **Text fields found and left for the owner** (not errors angzarr
  sends, or a standard's shape): `ProblemDetails.title` and `detail`
  (`dlq_admin.proto`, RFC 7807, human-readable by that standard);
  `sererr.v1.CapturedError.message` and `ExceptionMechanism.description`
  (a captured foreign exception's text, Sentry's shape, for DLQ triage);
  `FactOrigin.description` (an audit label, "Stripe webhook", not an
  error).
- **The input's acceptance time.** `ContextualCommand.recorded_at` (4, a
  `Timestamp`) is stamped by core's coordinator or the angzarr-embedded
  kernel when the input is accepted, so command and fact handlers can read
  it.
- Text changed with it: the `diagnostic` region, `RefusalResponse`,
  `ProjectorFailure`, `ContextualCommand`, the DLQ details and
  `AngzarrDeadLetter` in `types.proto`; the unknown-type refusal in
  `types.proto`, `command_handler.proto` and `upcaster.proto`; the refusal
  wiring in `policy.proto`, the no-path refusal in `options.proto`;
  `StoredDeadLetter` and `DeadLetterReplay` in `dlq_admin.proto`.
  Scenarios C-0539, C-0540, C-0580, C-0165, C-0459, C-0551, C-0293,
  C-0294, C-0444 to C-0446, C-0448, C-0618 and C-0624, and the parity scenarios C-0131, C-0341, C-0344, C-0345,
  C-0349, C-0352, C-0355 and C-0363 assert keys and args instead of text;
  new scenarios C-0667 to C-0677; step rule 18; angzarr-ports'
  `Cause`, its error tests and docs; angzarr-proto's `tests/diagnostics.rs`;
  the site's error recovery, observability, error handling and language
  notes pages, and the snippets that raised English.
- **Owner's rulings, 2026-10-28 (all the drafter's choices settled):**
  the decision as drafted is approved, with these:
  - A typed refusal's wire reason, and so its status message, is
    `COMMAND_REFUSED`, with `ErrorInfo` metadata `refusal_type` naming the
    object's fully-qualified type and the object in the status details:
    an `ErrorInfo` reason is SCREAMING_SNAKE (AIP-193, knowledge), which a
    type name is not. A catalog keys a typed refusal by its full type name
    with each `.` replaced by `-` (a Fluent id has no dots).
  - `Diagnostic` is one shared message; `args` are strings, as
    `ErrorInfo` metadata is.
  - `RefusalResponse` is a oneof; `StoredDeadLetter.details` is deleted
    outright (the structured detail is the payload's `rejection_details`,
    which `payload_view` renders).
  - A wrapped cause is flattened as `<name>` and `<name>.<arg>`.
  - The events of the write carry `ContextualCommand.recorded_at` as their
    `EventMeta.recorded_at`, which persistence still holds to
    `max(previous, now)` (5.15).
- **Owner's clarifications, 2026-10-29:**
  - In process too, an error's `Display` is its code then its args
    (` name=value` each, a wrapped cause flattened as on the wire), never
    English: English comes only from a catalog keyed by the code, where
    the error is shown.
  - A store driver's message text stays in the adapter's local log. Only
    the driver's numeric code travels, as an arg of the adapter's `cause`
    (`cause.errno` = `10`).
- Why: one representation of an error everywhere, that code can branch on
  and any language can render; English on the wire was both a parsing
  temptation and the only thing telling several conditions apart.
- Cost: every client library and the router ship or read a catalog to show
  text; logs show codes, not sentences; a handler can no longer explain a
  rejection in prose to its caller.
- Aligns with: Google's AIP-193 (a machine-readable `ErrorInfo.reason`
  and metadata, with the message for humans; here the message too is the
  key) and Project Fluent's message ids with named arguments (knowledge,
  not re-verified).

**14.38 The blackjack example: a wallet, and a player that decides.**
Owner rulings, 2026-10-28, for the example protos
(`proto/io/angzarr/examples/v1/`), so angzarr-embedded can run blackjack
with a Rust table and a Python player.
- **The wallet.** The aggregate that was "player" is the WALLET (domain
  `wallet`, Rust): identity, funds, holds and captures, loyalty.
  `player.proto` is `wallet.proto`; `PlayerState` is `WalletState`
  (`WalletAggregate`); `RegisterPlayer`, `ImportPlayer`, `PlayerRegistered`
  and `PlayerImported` are `RegisterWallet`, `ImportWallet`,
  `WalletRegistered` and `WalletImported`; `PLAYER_ALREADY_EXISTS` and
  `PLAYER_NOT_FOUND` are `WALLET_ALREADY_EXISTS` and `WALLET_NOT_FOUND`.
  Everything that named it follows: `BuyInPlayerPolicy` and
  `PlayerBuyInPolicy` are `BuyInWalletPolicy` and `WalletBuyInPolicy`; the
  settlement policy `TablePlayerPolicy` (table -> wallet: round results and
  loyalty) is `TableWalletPolicy`; the ledger subscribes to `wallet`, with
  `WalletLedgerRow`, `wallets`, `GetWalletBalance`, `WalletBalanceView`;
  `player.feature` is `wallet.feature`, and the buy-in, refusal and codegen
  scenarios that used the wallet say `wallet`.
- **The player.** A new aggregate, PLAYER (domain `player`, Python), is the
  bot. It has state (it is not a policy) and makes decisions:
  `DecideMove { table_root, round, seat, cards, total, soft, dealer_up,
  can_double, stack, wager }` produces `MoveDecided { table_root, round,
  seat, action }`, `action` a `MoveAction` (`MOVE_ACTION_HIT`, `_STAND`,
  `_DOUBLE_DOWN`). Its state is minimal (`decisions`, `hands_seen`), with
  room for a model's inputs; PyTorch lives here later. It needs no
  registration command: its stream starts at its first `DecideMove`.
- **Two policies (Rust).** `TablePlayerPolicy` (table -> player):
  `TurnStarted` -> `DecideMove`, root `TurnStarted.player_root`.
  `PlayerTablePolicy` (player -> table): `MoveDecided` -> `Hit`, `Stand` or
  `DoubleDown { seat }`, root `MoveDecided.table_root`. Each names its
  target root (14.36).
- **One table event added (drafter's choice, for the owner to confirm):**
  `TurnStarted { round, seat, player_root, hand, dealer_up, can_double,
  stack, wager }`, recorded right after the event that makes a decision
  point (`RoundDealt`, `CardDealt`, `HandStood` or `HandDoubled` whose turn
  names a seat), never once the round settles. Why: the policy takes
  everything from one event, and none carries a decision point whole.
  `RoundDealt` names only the first seat; `CardDealt`, `HandStood` and
  `HandDoubled` give `next_turn` but not that seat's cards (dealt earlier)
  or the up-card; and no turn event carries the seat's `player_root`. It
  carries only what a player may see, never the hole card or the shoe
  (R8's "no peeking").
- **Markers.** `emits` on every command of the wallet, the table, the
  buy-in and the player; `refuses` stays on `HoldFunds` and `ConfirmSeat`;
  `fact` stays on `SeatConfirmationRefused`. `Hit`, `Stand` and
  `DoubleDown` name no `refuses`: the table asks only the seat on turn and
  `can_double` says when doubling is allowed, so a refused move is a bug,
  dead-lettered and alerted (the player defines no `on_refused` handler).
- **Drafter's choices, for the owner to confirm.** A person's wallet and
  player share one root (the table's `player_root`); `TurnStarted` and its
  name; `can_double`, `stack` and `wager` on the turn (so the bot never
  asks for an illegal double); the bot's hand as flat fields rather than
  importing the table's `SeatHand`; `MoveAction` values prefixed; no
  typed refusal for a move; `emits` on every command.
- **Tonight's driver** seats a player with `RequestSeat` then
  `ConfirmSeat` sent directly, with no buy-in deployed, so no wallet funds
  are held or spent and ledger rule L3 does not hold for that table.
- Text changed with it: the example protos, `options.proto`'s refusal
  example, the example and framework feature READMEs, `RULES.md`; new
  scenarios EU-1505 to EU-1510 (`round.feature`) and EU-1600 to EU-1609
  (`bot_play.feature`).
- Why: the demo needs a player that decides, in another language, without
  breaking the money model the wallet owns; a stateless translator on each
  side keeps the table and the bot unaware of each other.
- Cost: one extra table event per decision; a person is two streams (wallet
  and player) under one root; the rename touches every consumer of the old
  `player` types.

> **Amended (the owner's ruling, 2026-10-29):** `MoveDecided` copies from
> `DecideMove` everything the decision used: it is `MoveDecided {
> table_root, round, seat, action, cards (5), total (6), soft (7),
> dealer_up (8) }`, the existing numbers unchanged. Why: the player's state
> is rebuilt from its events only, and `hands_seen` (decisions taken on a
> two-card hand) cannot be counted from an event that does not carry the
> hand; with the inputs on it, each event is a self-describing (state,
> action) row for the model to learn from. Cost: the hand is recorded
> twice, on the table's `TurnStarted` and on the player's `MoveDecided`.

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
