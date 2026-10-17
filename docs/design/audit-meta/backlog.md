# Code follow-up backlog (passes 1–10)

Part of the [audit-meta design record](../audit-meta-followups.md).

The ten `feat/audit-meta` passes changed only the protos and the
`rust/angzarr-proto` crate. **Nothing in this backlog is done.** It is the
durable record of the code work the new contract implies: the user is not
taking on heavy angzarr refactoring now, and this list must not be lost.

Items are grouped by **workstream**. Each item is tagged with its repos and
its pass or finding, and gives three things:
- **What**: the change.
- **Why**: the contract text or finding that requires it.
- **Settled when**: the check that closes it.

A [by-repo index](#by-repo-index) follows the workstreams.

Repos:
- **core**: the coordinator, storage, bus, DLQ and status console.
- **router**: angzarr-router.
- **clients**: client-go, -rust, -python, -java, -csharp, -cpp and
  -typescript, with their codegen.
- **examples**: examples-* and the poker protos.
- **site**: angzarr-project `site/`.
- **project**: angzarr-project features, parity, CI and branches.

Code is located by signature or file, never by line number. Core paths are
relative to the core repository root.

---

## KS: idempotency key store (pass 5, W1)

**KS-1** [core] **The claim store in every backend.**
- What: implement the `IdempotencyClaim` schema in each storage backend,
  with uniqueness on (stream, key). Write the claim in the same transaction
  as the event append. Add a capability flag on the storage trait for
  "atomic claims".
- Why: a claim must exist if and only if its events do (`types.proto`, origin
  region).
- Settled when: on every backend that sets the flag, two concurrent
  deliveries of one key yield exactly one APPLIED and one DUPLICATE, with
  identical events.

**KS-2** [core] **Check before business code, and answer duplicates from the
range.**
- What: look the key up before decide or ingest. On a hit, re-read
  `first_sequence .. +event_count` and answer `DELIVERY_OUTCOME_DUPLICATE`.
  Claim zero-event outcomes too. This replaces today's causation and fact
  dedup and adds request keys.
- Why: the claim model. W1: request-origin commands were not deduplicated.
- Settled when: dedup tests pass for each key kind (request, causation,
  fact), including a zero-event command that is answered DUPLICATE with no
  events.

**KS-3** [core] **Release rejections, and never claim parked facts.**
- What: claims are written only on commit of an applied outcome.
- Why: rejections are released (Wolverine-style).
- Settled when: a command rejected, then retried with the same key after the
  state changes, applies.

**KS-4** [core] **The fingerprint.**
- What: fingerprint the body payload's `Any` exactly as received, never
  re-serialised: UUIDv5(`ANGZARR_FINGERPRINT_NAMESPACE`
  `a749bd8c-7bf0-47e6-a5c9-dc54ebde74aa`, the UTF-8 type URL's length as 4
  bytes big-endian ++ the type URL ++ the value bytes), stored as a 16-byte
  UUID. A request key that arrives with a different fingerprint is refused
  `FAILED_PRECONDITION`; a fact key too, by default (KS-10). The request key
  is `request_id` alone (pass 10 deleted `RequestOrigin.index`).
- Why: the claim model's fingerprint rule; decisions 10.1 and 10.3.
- Settled when: the same key with a changed payload is refused, the same
  key with identical bytes is answered DUPLICATE, and core reproduces the
  documented worked example (`6d42fa9e-0dca-5047-94b1-0ae371532630`) from a
  golden list shared with the clients (UU-2).

**KS-5** [core] **Retention and expiry.**
- What: set `expires_at` to 24 hours for request keys and 7 days for
  causation and fact keys. Garbage-collect expired claims, and treat an
  expired claim as absent.
- Why: retention. These windows also gate DLQ replay (DQ-3).
- Settled when: an expiry test shows a key running again after its window,
  and a GC job is wired into each backend.

**KS-6** [core] **`HandleAsync` key requirement and backend capability.**
- What: refuse a command without a client-supplied key (no `request_id`,
  or `RequestOrigin.minted` set) with `INVALID_ARGUMENT`, before minting or
  enqueueing, and answer
  `UNIMPLEMENTED` on backends without atomic claims (as replay does, DQ-3).
- Why: `command_handler.proto`, the HandleAsync and backend-capability text.
- Settled when: both refusals are tested.

**KS-7** [clients] **Deterministic serialisation and request keys.**
- What: every SDK serialises payloads deterministically. Examples: Go
  `proto.MarshalOptions{Deterministic: true}`, sorted map entries in the
  others, and prost's field order in Rust. Every SDK's command helpers set
  `RequestOrigin.request_id`, one per command (pass 10: no `index`; a batch
  helper mints one id per command and shares the correlation), and reuse it
  verbatim on retry.
  An SDK that generates the id for its caller mints a UUIDv7 (MI-2) and
  never sets `minted` (it is a client key).
- Why: the fingerprint is taken over the bytes as received, so an honest
  retry must reproduce them.
- Settled when: a cross-language golden test produces identical bytes for a
  payload with map fields, and retry helpers keep the key.

**KS-8** [core] **Reactions on backends without atomic claims.**
- What: decide, then implement, what sagas and PMs do on such a backend:
  refuse to run, or run with a loud warning.
- Why: an open question in [idempotency.md](idempotency.md). Reaction
  delivery is at least once.
- Settled when: the user decides, and the decision is recorded in the protos.

**KS-9** [core] **Dead-letter entries for parked facts.**
- What: deduplicate DLQ entries per (stream, `external_id`), so a source that
  keeps redelivering a fact whose ingest fails updates one entry rather than
  adding entries.
- Why: parked facts are not claimed.
- Settled when: N redeliveries of a failing fact leave one DLQ entry, with an
  attempt count.

**KS-10** [core] **Refuse a fact re-sent with a different payload.**
- What: a fact whose `external_id` is already claimed on the stream, with a
  different fingerprint, is refused `FAILED_PRECONDITION` (never answered
  DUPLICATE, never claimed); through `HandleAsync` it is a terminal failure
  and is dead-lettered. Unless KS-11's setting says DUPLICATE.
- Why: decision 10.2 (the user), recorded in `types.proto` (the claim
  model's fingerprint) and on `FactOrigin.external_id`.
- Settled when: a test re-sends a fact with a changed payload and it is
  refused, while identical bytes are answered DUPLICATE.

**KS-11** [core] **The fact-mismatch setting.**
- What: a coordinator configuration knob, per command type (the payload's
  type URL) and per component, choosing REFUSE (the default) or DUPLICATE
  for a fact whose fingerprint mismatches its claim. DUPLICATE answers
  from the claimed range, as an exact duplicate does, and raises an alert
  and increments a metric naming the stream, the `external_id` and both
  fingerprints. Precedence as for Handling's defaults: command type, then
  component, then the built-in REFUSE. Configuration only: nothing on the
  wire carries it. annals offers the same setting (per command type or
  domain; tracked in the session plan).
- Why: decision 10.2.
- Settled when: with the setting on, the mismatched fact is answered
  DUPLICATE and the alert and metric fire; with it off or absent, KS-10's
  refusal holds; the precedence is tested.

**KS-12** [core] **Refuse and dead-letter a causation key re-sent with a
different payload.**
- What: a reaction command whose (event, component, index) key is already
  claimed on the stream, with a different fingerprint, is never applied and
  never answered DUPLICATE. It is dead-lettered (`AngzarrDeadLetter`,
  `rejected_command`), and an alert is raised naming the stream, the key
  and both fingerprints. No setting changes this (unlike KS-11 for facts).
- Why: decision 10.4 (the user), recorded in `types.proto` (the claim
  model's fingerprint, `Causation`, `IdempotencyClaim.fingerprint`). With
  the transient outbox (OB-1, OB-2) a reaction's commands are re-sent
  verbatim, so a mismatch can only be a framework bug or a corrupted
  outbox; DUPLICATE would hide it and lose the command.
- Settled when: a test delivers a causation key twice with different
  payload bytes and the second is dead-lettered with the alert fired,
  nothing is appended and no DUPLICATE is answered, while identical bytes
  are still answered DUPLICATE.

## OB: transient reactor outbox (pass 5, W3)

**OB-1** [core] **The saga transient outbox.**
- What: store a `SagaResponse`'s commands atomically with the saga's source
  checkpoint (position store), dispatch them, then clear the outbox, keeping
  only the keys. Today saga commands are sent directly, with
  `SyncMode::Async` hardcoded in `handlers/core/saga.rs`.
- Why: `saga.proto`, the transient outbox text.
- Settled when: in a crash-injection test (crash after store, before
  dispatch), the restart re-sends byte-identical commands with the same keys,
  and the saga is not re-run for that trigger.

**OB-2** [core] **The PM transient outbox.**
- What: store a PM's `process_events` append, its commands and its checkpoint
  in one transaction, then dispatch and clear. Remove any notion of reactor
  determinism or nondeterminism dead-lettering.
- Why: `process_manager.proto`, the transient outbox text.
- Settled when: the OB-1 test passes for PMs, including process events.

**OB-3** [core] **Co-locate checkpoints and outboxes.**
- What: the position store and the outbox must share a transaction, so the
  backend matrix gains a "transient outbox" capability.
- Why: "stored atomically with the source checkpoint".
- Settled when: every backend either supports it or refuses to host
  reactors (see KS-8).

**OB-4** [router] **Reactor output returns to the coordinator.**
- What: router dispatch functions (for example
  `angzarr_router_dispatch_saga`) return the reactor's output for the
  coordinator to store, and never send it themselves.
- Why: the outbox owns dispatch.
- Settled when: the router API has no send path for reaction commands.

**OB-5** [core] **Outbox documentation.**
- What: rewrite `src/bus/README.md` and the patterns docs, which describe a
  PM-only outbox.
- Why: the outbox now covers all reactors.
- Settled when: the docs match the protos.

**OB-6** [core, router] **Per-event causation for saga output (W3a).**
- What: a saga receives a whole `EventBook`, and core stamps causation with
  the book's maximum sequence (`source_max_sequence` in
  `orchestration/saga/mod.rs`). That is imprecise for audit, and the key
  changes if catch-up delivers the events in different chunks. Either
  deliver one triggering event per saga call, or have the router report which
  event produced each command, so the coordinator stamps the exact
  `Causation.event`.
- Why: W3(a), the one part of W3 that pass 5 left open. `Causation.event` is
  "always the triggering event" in the contract.
- Settled when: re-chunked catch-up re-sends commands with identical keys,
  and each command's `Causation.event` names the event it answers.

## PS: provenance stamping and correlation (passes 1 and 5, W4/W5)

**PS-1** [core] **Persist provenance.**
- What: stamp `EventMeta` on every page the coordinator writes: provenance,
  origin, `base_sequence`, `recorded_at` and `rules_version`.
- Why: pass 1. Until this lands, angzarr-run streams lose causation. (The plan
  once listed this as "not adopted" for that pass's scope. It is still
  required code.)
- Settled when: a round-trip test reads back full meta for each origin kind.

**PS-2** [core, router] **Stamp reaction provenance from the trigger.**
- What: copy actor and `correlation_id` from the triggering event's
  `EventMeta.provenance`, and stamp `Causation.component` and `index`. A
  reaction command whose provenance differs from the trigger's is
  dead-lettered and alerted.
- Why: W4 and W5 (the `Provenance` region).
- Settled when: tests show a reactor setting a foreign actor is refused, and
  an empty one is stamped.

**PS-3** [core] **Correlation is never empty.**
- What: use the caller's value (a UUID). Otherwise set it, before business
  code, from the origin: the `request_id` verbatim for a request (always
  present after MI-3, client-supplied or minted), and
  UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`, `external_id`) for a fact
  (UU-2). No correlation minting of its own. Causation commands keep the
  trigger's (PS-2). (Pass 9, decision 9.2, supersedes pass 8's
  "`external_id` verbatim, no name-based UUID".)
- Why: W5; decisions 8.3 and 9.2.
- Settled when: retries of one client-keyed request without a correlation
  land in one correlation equal to its `request_id`; a request without a
  client key gets its minted request id as correlation; redeliveries of one
  fact land in the documented v5 correlation; and no persisted event has an
  unset correlation.

**PS-4** [core] **Correlation is per page only.**
- What: stop reading correlation from `Cover`, and implement
  `Query.correlation_id` (one correlation per write).
- Why: pass 1.
- Settled when: query-by-correlation works across a domain's streams.

**PS-5** [core] **Fix the filed core bugs.**
- What: the correlation query ignores the domain (uncurious-president), and
  cached replays relabel correlation (unpaved-ultimate). Both are in
  angzarr's task log.
- Why: they corrupt the provenance this contract relies on.
- Settled when: both tasks are closed.

## BO: business output is payloads only (pass 5, W7)

**BO-1** [core] **Validate handler output.**
- What: validate `CommandHandlerService.Handle` output and PM
  `process_events`. Page `meta` and `sequence` must be unset, and the cover
  empty or equal to the command's. On a violation, persist nothing: answer
  `INTERNAL` to `Handle`/`HandleSync` callers, and dead-letter and alert on
  asynchronous and reaction paths.
- Why: `command_handler.proto`, `CommandHandlerService.Handle`.
- Settled when: each violation kind is refused in a test.

**BO-2** [clients] **Codegen returns payloads, not raw books.**
- What: when `CommandOptions.emits` is empty, generated handlers return raw
  payloads (`Any`, plus an optional snapshot state), not a raw `EventBook`.
  Remove every SDK path that lets a handler set a cover, sequence or meta.
- Why: the "custom covers" escape hatch is gone (`options.proto`).
- Settled when: no generated handler signature mentions `EventBook` as
  output.

**BO-3** [examples] **Fix handlers that set covers, sequences or meta.**
- What: update the examples that do this.
- Why: BO-1 would refuse them.
- Settled when: the example suites pass against BO-1.

## RV: rules_version declaration (pass 5, W8)

**RV-1** [core] **Stamp the declared rules version.**
- What: accept `ComponentDescriptor.rules_version` at registration, and stamp
  it into `EventMeta.rules_version` on every event an aggregate's or PM's
  decision produces. Business code never sets it.
- Why: W8.
- Settled when: a re-registration with a new value changes the stamp on
  subsequent events only.

**RV-2** [clients] **Declare a rules version.**
- What: SDK component registration takes a rules version, defaulting to a
  build id or release tag from the environment.
- Why: W8.
- Settled when: every SDK sends it in its `ComponentDescriptor`.

## MD: the three RPC modes and the Outcome (passes 4 and 5, W11)

**MD-1** [core] **Three coordinator RPCs replace `HandleCommand`.**
- What: `Handle` (DECISION), `HandleAsync` (ASYNC, returns `Empty`) and
  `HandleSync` (SIMPLE) replace `HandleCommand` and every `sync_mode` read
  (`sync_policy.rs`, `with_sync_mode`, the aggregate service's
  `Handling.sync` resolution). The mode never reaches business code.
- Why: pass 4.
- Settled when: the coordinator-contract features pass for each RPC.

**MD-2** [core] **HandleSync reports projector failures.**
- What: HandleSync answers OK once the decision commits. Each synchronous
  projector failure goes into `Outcome.projector_failures` (name, code,
  message), and the failed projection continues on the asynchronous path.
- Why: W11.
- Settled when: with a failing projector, the call is OK, the events are
  present, and one failure entry is reported.

**MD-3** [core] **"Accepted, parked" for failed facts.**
- What: a failed fact ingest is answered OK with `DELIVERY_OUTCOME_PARKED`
  and no events, then dead-lettered and alerted.
- Why: W11.
- Settled when: a test covers it on all three RPCs.

**MD-4** [core] **The projector coordinator takes `EventBook`.**
- What: `HandleSync(EventBook)`. Delete `EventRequest`,
  `EVENT_REQUEST_MISSING_EVENTS` and the fact path's `EventRequest` wrapper.
- Why: pass 4.
- Settled when: no `EventRequest` remains.

**MD-5** [core] **Reaction delivery mode comes from configuration.**
- What: the PM outbox and saga delivery choose `Handle` or `HandleAsync`
  from component configuration. Today `SyncMode::Async` is hardcoded in
  `handlers/core/saga.rs` and `handlers/core/process_manager.rs`. Reactions
  never use `HandleSync`.
- Why: pass 4.
- Settled when: a config switch changes the RPC used.

**MD-6** [clients] **Clients call the three RPCs.**
- What: call `Handle`, `HandleAsync` or `HandleSync`. Optional sugar:
  `handle(book, mode)`, where the mode selects the RPC and is never sent.
  Surface `projector_failures` and `PARKED`.
- Why: passes 4 and 5.
- Settled when: no SDK references `SyncMode` or `HandleCommand`.

## ST: status codes (pass 5, W11)

**ST-1** [core] **One retryable set.**
- What: in `src/utils/retry.rs` (`is_retryable_status`),
  `src/dlq/trigger.rs` (`CodeDlqExt::classify_for_dlq`) and
  `src/client_traits.rs`, make exactly `UNAVAILABLE`, `DEADLINE_EXCEEDED`,
  `RESOURCE_EXHAUSTED` and `ABORTED` retryable.
  - A stale sequence becomes `ABORTED`: `single_sequence_check` and
    `storage::error::SEQUENCE_CONFLICT`. Message-prefix parsing of
    `FAILED_PRECONDITION` goes.
  - `INTERNAL`, `UNKNOWN`, `DATA_LOSS` and `CANCELLED` stop being retried, so
    backends must map transient storage faults to `UNAVAILABLE`.
  - A queued command whose caller-provided `expected_sequence` is `ABORTED`
    is dead-lettered with `SequenceMismatchDetails`.
- Why: the status-codes text in `command_handler.proto`. Core's R2-15 set
  differs from it.
- Settled when: one table-driven test is shared by every retry loop (command,
  saga, PM, projector, DLQ trigger).

**ST-2** [clients] **Client retry helpers.**
- What: use the same set, and drop any `FAILED_PRECONDITION` message parsing.
- Why: one contract across languages.
- Settled when: the parity tests agree.

## ED: editions, external sinks and the CloudEvent id (passes 1, 2, 5 and 7, W10)

**ED-1** [core] **Suppress non-main editions at external sinks.**
- What: CloudEvents HTTP and Kafka sinks, and any other external automation,
  drop output projected from non-main editions, counted by a metric.
- Why: W10 (`cloudevents.proto`, `projector.proto`).
- Settled when: a what-if command produces no sink delivery.

**ED-2** [core] **The default CloudEvent id and source include the edition.**
- What: id `{domain}:{root}:{sequence}` on main (edition unset, no edition
  segment) and `{domain}:{edition}:{root}:{sequence}` on a named edition;
  source `angzarr/{domain}` on main and `angzarr/{domain}/editions/{edition}`
  otherwise.
- Why: W10; the main shape is pass 7 (decision 7.1).
- Settled when: the ids of the same (domain, root, sequence) differ across
  editions.

**ED-3** [core, clients] **Main is the unset edition.**
- What: model the edition as an option (`None` = main) through core's
  coordinators, queries, subscriptions and storage, and drop the `"angzarr"`
  alias and any `""`-means-main handling. Refuse a **set** empty edition
  (`Cover.edition`, `CorrelationQuery.edition`) with `INVALID_ARGUMENT`.
  Client helpers build main covers with the edition unset. How a backend
  stores main (for example NULL) is its own choice.
- Why: pass 7 (decision 7.1), superseding pass 1's "main is `""`".
- Settled when: no alias or `""`-as-main path remains, an unset edition
  reads and writes main, and a test covers the set-`""` refusal.

**ED-4** [core] **Edition storage.**
- What: per-edition storage routing and sharding, a configured default
  edition store (memory, redis, a persistent store or the existing database),
  the edition column kept in every schema, and projector output following the
  edition's storage. Divergence points live in the edition record (EA-1).
- Why: passes 1, 2 and 6.
- Settled when: a created edition with no store runs on the default store,
  and an edition created with a store runs on that store.

## SN: snapshots (passes 2 and 5, W12)

**SN-1** [core] **The AGGREGATE_HANDLES snapshot bound.**
- What: under AGGREGATE_HANDLES, load a snapshot with sequence at or below
  `expected_sequence-1`, or none when `expected_sequence` is 0, so that the
  window arrives as pages.
- Why: W12.
- Settled when: with a snapshot inside the window, decide still receives
  every window page.

**SN-2** [core] **Snapshot policy configuration.**
- What: delete `SnapshotRetention`. Snapshot frequency and keep-count become
  per-domain storage configuration that follows the edition's storage, and
  the default keeps the newest only. The config shape needs designing.
- Why: pass 2.
- Settled when: the config is documented, and the default is tested.

**SN-3** [core] **Snapshot version-discard (pass 6, D8).**
- What: stamp `Snapshot.rules_version` from the component's
  `ComponentDescriptor.rules_version` when a snapshot is written. On every
  load that would start from a snapshot, compare its state type URL with the
  registered state type and its `rules_version` with the current one; on a
  mismatch, skip it (falling back to an older matching snapshot, or sequence
  0) and replay. Count discards in a metric. Business code never sets the
  field.
- Why: `types.proto`, Snapshot "Validity".
- Settled when: changing the state type or the rules version makes the next
  load replay from events, never decode the old state, and the replayed
  state equals a full replay.

## RT: recorded_at and temporal queries (passes 2 and 5, W13)

**RT-1** [core] **A monotonic `recorded_at`.**
- What: stamp `recorded_at` = max(the previous event's `recorded_at`, now)
  per stream, one value per write, and index it. `EventPage.created_at` and
  `Snapshot.created_at` are gone.
- Why: W13.
- Settled when: with an injected backwards clock step, a test still yields
  non-decreasing values.

**RT-2** [core] **`as_of_time` is a prefix.**
- What: `TemporalQuery.as_of_time` returns the prefix up to the last event
  with `recorded_at <= T`. Snapshot selection uses the `recorded_at` of the
  event at `snapshot.sequence`. Queries start from the nearest kept snapshot
  in the prefix, or from 0.
- Why: W13.
- Settled when: as-of results equal a full replay to the same point.

## DQ: DLQ replay (passes 3, 4 and 5, W9)

**DQ-1** [core] **Replay keeps the original identity.**
- What: keep the original provenance, origin and keys. Delete
  `new_correlation_id` minting (`src/status/handlers/dlq.rs`,
  `src/dlq/audit.rs`), and set `ReplayDeadLetterOk.correlation_id` to the
  original.
- Why: W9.
- Settled when: replaying an entry whose original did apply is answered
  DUPLICATE.

**DQ-2** [core] **The replay audit record.**
- What: extend `dlq_replay_audit` (`migrations/status/{postgres,sqlite}`).
  Add the operator (from the call's credentials, pseudonymous),
  `retention_overridden`, an outcome of PENDING/APPLIED/DUPLICATE/FAILED,
  `outcome_at` and `detail`. Drop `new_correlation_id` and
  `original_correlation_id`. Surface the records as
  `StoredDeadLetter.replays`, and move the outcome on from PENDING when the
  replayed delivery is decided, correlating by key. (The H-31
  `idempotency_key` column guards the replay *request* and stays.)
- Why: W9 (`dlq_admin.proto`).
- Settled when: `GetDeadLetter` shows a replay going PENDING, then APPLIED.

**DQ-3** [core] **Replay refusals.**
- What: a command entry without a client-supplied key (empty or minted
  `request_id`) is refused `FAILED_PRECONDITION`. An entry
  past its key's retention is refused `FAILED_PRECONDITION` unless
  `override_retention` is set. A backend without atomic claims answers
  `UNIMPLEMENTED`.
- Why: W9 and the claim model.
- Settled when: each refusal is tested.

**DQ-4** [core] **Event-book replay targets the failed component.**
- What: replay `rejected_events` to `source_component` only.
  `FRESH_SEQUENCE` on an event entry is `INVALID_ARGUMENT`.
- Why: W9.
- Settled when: other subscribers do not see the replay.

**DQ-5** [core] **Command replay rides the bus.**
- What: store `rejected_command` as received (with Handling as sent).
  `AS_IS` keeps it, and `FRESH_SEQUENCE` clears
  `handling.expected_sequence`. Publish to the bus to be processed as
  `HandleAsync` processes commands: no hardcoded `SyncMode::Simple`, and no
  re-stamping of page headers from a query.
- Why: passes 3 and 4.
- Settled when: replay has no mode parameter internally.

**DQ-6** [core] **The status console shows replays.**
- What: the DLQ panel lists each entry's replays and their outcomes.
- Why: operators need the audit trail.
- Settled when: the UI shows the replay history.

## RN: renames (pass 5, W14)

**RN-1** [core, router, clients] **`decided_at` becomes `base_sequence`.**
- What: rename `EventMeta.decided_at` to `base_sequence` everywhere, and
  record it on every event.
- Why: W14. The field is a sequence, not a time.
- Settled when: no `decided_at` remains outside history.

**RN-2** [core, clients, site] **The projector coordinator's `HandleAsync`.**
- What: rename the projector coordinator's `Handle` to `HandleAsync`, at HTTP
  `POST /v1/projector/async` (gateway and Envoy routes too). Update the site's
  architecture diagrams, and the stale `service ProjectorCoordinator` block in
  `pitch.mdx`.
- Why: W14.
- Settled when: the gateway serves the new path, and the old one is gone.

## PR: process-manager replies (passes 2 and 5, W6)

**PR-1** [core] **Route replies by correlation.**
- What: route replies to the PM instance by `correlation_id`. A PM command's
  `Causation.event` is its trigger, never a PM process event.
- Why: W6. This **corrects** the pass-2 backlog item, which said a reply's
  causation "names the PM's event".
- Settled when: a PM receives a target's refusal event under its correlation
  and acts on it.

**PR-2** [core] **Hard rejections of PM commands.**
- What: retry when retryable, otherwise dead-letter. Whether the PM should
  also learn of the rejection is open (an open question in the index; it is
  not one of the review's D items).
- Why: pass 2.
- Settled when: the question is decided and implemented.

## FA: the fact pipeline (pass 2)

**FA-1** [core] **Reflective dispatch.**
- What: the body arm picks the pipeline (Command goes to decide, Fact to
  ingest), and the type URL picks the handler.
- Why: pass 2.
- Settled when: a fact never reaches decide.

**FA-2** [core] **Refuse and park.**
- What: refuse a `Fact` that sets `expected_sequence` (`INVALID_ARGUMENT`).
  A failing ingest is dead-lettered, alerted and answered PARKED (MD-3).
- Why: passes 2, 4 and 5.
- Settled when: both are tested.

**FA-3** [clients, router] **Infallible fact handlers.**
- What: fact handlers are an infallible interface with no error arm (annals:
  `Domain::ingest(&state, fact) -> Vec<Event>`). The handler registration
  (`#[handles_fact]` / ingest) is the codegen declaration, with no proto flag,
  and the router guards the arm against the handler kind.
- Why: pass 2. The codegen marker question is resolved.
- Settled when: a fact handler cannot return an error in any SDK.

## HD: Handling resolution (passes 1 and 3)

**HD-1** [core] **Resolve Handling in place.**
- What: stamp `expected_sequence` when absent, and fill
  `conflict_resolution` from configuration. `ContextualCommand` sees only resolved handling, which is
  never persisted.
- Why: pass 3.
- Settled when: decide never sees an unspecified field.

**HD-2** [core] **Conflict-resolution configuration.**
- What: configure the conflict resolution per command type and per
  component (including the opt-in COMMUTATIVE, CR-1).
  Precedence: Handling, then command type, then component, then STRICT. Add
  forbid-override, which is refused `INVALID_ARGUMENT`. The config shape
  needs designing.
- Why: pass 3.
- Settled when: the config is documented, and the precedence is tested.

**HD-3** [core, router] **Reaction commands carry no Handling.**
- What: a reaction command with any `Handling` field set is dead-lettered.
  Delete `reaction_sync_mode` and the `PageHeader.sync_mode` preservation.
  Resolve the core/router disagreement on explicit sequences: core's
  `Some(SequenceType::Sequence(_)) => continue` in
  `orchestration/saga/mod.rs` and `orchestration/process_manager/mod.rs`
  must refuse instead.
- Why: passes 3 and 4.
- Settled when: core and the router behave identically.

**HD-4** [core] **The default conflict resolution is STRICT.**
- What: `CommandPageExt::effective_merge_strategy` calls
  `MergeStrategy::or_default_commutative`. Make it default to STRICT, and
  rename to `ConflictResolution` (pass 6, D10).
- Why: COMMUTATIVE is opt-in only (pass 6); it is never the default.
- Settled when: an unconfigured stale command is `ABORTED`.

**HD-5** [core, clients] **Three resolutions, checked before business
code.**
- What: keep only `STRICT`, `AGGREGATE_HANDLES` and the client-side
  `COMMUTATIVE` (no `MANUAL`, no coordinator-side commutative diff, no
  `Replay` RPC), and deliver the conflict window with the command. Check or
  stamp the expected sequence before business code. Clients get
  conflict-resolution helpers for `AGGREGATE_HANDLES`, computed locally over
  the delivered window (no framework RPC).
- Why: passes 1 and 6.
- Settled when: no other resolution remains in code, and core's commutative
  diff is gone (CR-1 replaces it in the clients).

## WS: wire-shape migration (passes 1–3)

**WS-1** [core, clients] **u64 sequences end to end.**
- What: the `EventStore` trait, Postgres `INTEGER`/`i32` casts, Bigtable's
  `{:010}` key padding, and every SDK.
- Why: pass 1.
- Settled when: a stream past 2^32 round-trips.

**WS-2** [core, router, clients, examples] **Remove `Cover.ext`.**
- What: storage `ext` columns, router stamping, about 60 core sites, Python's
  `unpack_parent_cover`, and the poker protos. Parent references move into
  payloads.
- Why: pass 1.
- Settled when: no `ext` remains.

**WS-3** [core] **Delete obsolete types and RPCs.**
- What: `PageHeader`, the deferred-sequence types,
  `HandleFact`/`HandleEvent`/`Replay`, `EventRequest.skip_handler`, saga/PM
  facts, `CommandMeta`, and the request wrappers. `SagaService.Handle`,
  `SagaCoordinatorService.Execute` and `ProcessManagerCoordinatorService.Handle`
  take `EventBook`.
- Why: passes 1–3.
- Settled when: core builds against the new protos.

**WS-4** [core] **One page per `CommandBook`.**
- What: execute exactly one page. Today extra pages are silently ignored.
- Why: pass 1.
- Settled when: the code matches the wire.

**WS-5** [core] **`PayloadReference` moves to the transport.**
- What: claim-checking moves into a transport-owned bus envelope, resolved
  before anything else sees the message.
- Why: pass 2.
- Settled when: no persisted page carries a reference.

## RM: removed features (pass 2)

**RM-1** [core] **Delete cascades.**
- What: delete `CASCADE`, `ISOLATED`, the cascade error modes and
  `CommandResponse.reaction_errors`.
- Why: decision 2.1.
- Settled when: none of them remain.

**RM-2** [core] **Delete the compensation and notification path.**
- What: delete `Notification`, `RejectionNotification`, `Compensate`,
  `HandleCompensation`, `RevocationResponse`, `BusinessResponse`,
  `SagaCompensationFailed`, `CompensationDeliveryFailedDetails` and escalation
  forwarding.
- Why: decision 2.2.
- Settled when: none of them remain.

**RM-3** [core] **Delete speculative execution.**
- What: delete every speculative RPC. What-ifs become commands in an edition
  (ED-4).
- Why: decision 2.4.
- Settled when: none remain.

**RM-4** [clients] **Delete removed features from the SDKs.**
- What: delete the compensation handlers, `undoes`/`compensates` codegen,
  rejection fan-out and the speculative APIs. Regenerate for `CommandPage`
  (`provenance`, `body`), `CommandBook.handling` and
  `CommandResponse.outcome`.
- Why: pass 2.
- Settled when: the SDKs build against the protos.

**RM-5** [examples] **Rework the poker compensation.**
- What: rework the `compensates: DealCards` behaviour (`TableHandSaga`,
  `TableState`) as a refusal event plus a saga.
- Why: the annotations were removed.
- Settled when: the poker examples pass.

**RM-6** [clients, core] **Clear leftover 2PC.**
- What: leftover 2PC in generated Python, stale 2PC tasks in core's
  `tasks.md`, and stale branches.
- Why: the pass-1 audit.
- Settled when: none remain.

## TG: type generation and the router (gap 9)

**TG-1** [core, router, clients] **One set of Rust types.**
- What: remap core, angzarr-router and client-rust onto `angzarr-proto`
  through `extern_path`.
- Why: the same types are generated three times (four with the crate).
- Settled when: one generation remains.

**TG-2** [router] **Mirror the new dispatch.**
- What: dispatch on the body arm, then the type URL. Delete the compensation,
  undo and speculative dispatch and the notification envelopes.
  `angzarr_router_dispatch_saga` takes `EventBook` bytes.
- Why: pass 2.
- Settled when: the router builds on `angzarr-proto`.

## OR: one Origin (pass 6, D1)

**OR-1** [core] **Validate arm against origin.**
- What: read the origin from `CommandPage.origin` (no longer from the
  `Command`/`Fact` arms), and refuse a mismatch before deduplication: a Fact
  without a fact origin or with an empty `external_id`, a Command with a fact
  origin. `INVALID_ARGUMENT` for a client; dead-letter and alert for a
  reactor (including a reactor that emits a Fact). A Command with no origin
  is a request without a client key, recorded as a `RequestOrigin` with a
  minted `request_id` (MI-3).
- Why: `types.proto`, origin region. The rule was structural before pass 6
  and is now a check.
- Settled when: each mismatch is refused in every mode, and none reaches
  business code.

**OR-2** [core, router, clients] **Use the shared `Origin` everywhere.**
- What: `EventMeta.origin` is the page's `Origin`, copied unchanged;
  `IdempotencyClaim.key` is an `Origin`; the claim store's key columns follow.
  Delete the per-arm origin mapping code in every language.
- Why: D1: one shape, no mapping.
- Settled when: no code maps one origin shape onto another.

## CQ: cross-domain correlation query (pass 6, D4)

**CQ-1** [core] **A correlation index in every backend.**
- What: an index on `EventMeta.provenance.correlation_id` across all
  domains (and per edition) in each storage backend, so
  `GetCorrelatedEvents` does not scan. Postgres and SQLite: an index on a
  correlation column. Bigtable and other key-value stores: a secondary
  index table keyed by (edition, correlation, stream, sequence), written in
  the append. KurrentDB-backed: the `$by_correlation_id` system projection.
- Why: D4; the indexes were deferred to the backlog by decision.
- Settled when: every backend answers a correlation query in time
  proportional to the result, not to the store.

**CQ-2** [core, clients] **Serve `GetCorrelatedEvents`, and a forward-causation helper.**
- What: implement the RPC (validation, editions, one book per stream, the
  HTTP route). Client libraries offer a helper that indexes the result on
  `origin.causation.event` to answer "what did this event cause".
- Why: `query.proto`, `CorrelationQuery` in `types.proto`.
- Settled when: a saga chain across three domains comes back in one call,
  and the helper rebuilds its causation tree.

## EA: edition administration (pass 6, D5)

**EA-1** [core] **The edition registry and its admin RPCs.**
- What: store `Edition` records (name, `diverged_at`, store, created_at,
  created_by) and serve `EditionAdminService.CreateEdition` and
  `DeleteEdition` with the documented codes. `DeleteEdition` removes the
  record and the edition's events, snapshots, projector output and claims in
  every domain. Administrative only: nothing is written to any stream.
  Retire core's `DeleteEditionEvents` storage method.
- Why: `meta.proto`.
- Settled when: create, delete, the empty-name refusal (`INVALID_ARGUMENT`:
  a name is required, and main has none) and the unknown-name refusal are
  tested.

**EA-2** [core] **Refuse never-created editions everywhere.**
- What: every command, query and subscription naming a non-main edition
  checks the registry and answers `NOT_FOUND` for an unknown name. Remove the
  "unknown edition falls back to the default store" path.
- Why: D5: a misspelt edition must never get storage.
- Settled when: a command to a misspelt edition writes nothing and is
  refused.

**EA-3** [core] **Divergence records drive the main fall-through.**
- What: an edition read falls through to main's events with `recorded_at`
  at or before the edition's `diverged_at`, in every stream. Make the
  default point exact: a time stamped at create can tie with a main event
  appended concurrently (equal `recorded_at`), and clocks differ across
  coordinator instances. Settle on one rule (for example, stamp
  `diverged_at` through the same non-decreasing clock as appends, or record
  per-stream heads lazily on the edition's first access to a stream) and
  document it.
- Why: the divergence point is now recorded, so it must be exact.
- Settled when: a what-if created at main's head never sees a main event
  appended after the create returned.

**EA-4** [clients, site, project] **What-if callers create editions first.**
- What: client helpers for `CreateEdition`/`DeleteEdition`, the what-if
  examples and feature specs updated to create the edition, and the site's
  edition pages rewritten.
- Why: D5.
- Settled when: no example or spec uses an edition it did not create.

## NC: the conflict nonce (pass 6, D7)

**NC-1** [clients, router] **The nonce helper in each client library.**
- What: in each language (go, rust, python, java, csharp, cpp, typescript
  and the router), pass `ContextualCommand.conflict_nonce` to the handler as
  a parameter under AGGREGATE_HANDLES and COMMUTATIVE, provide
  `resolve_conflicts(window, nonce)`, and on handler return check that it was
  called with exactly the delivered value. Otherwise discard the output,
  answer `ABORTED`, and log the handler bug. Local only: no gRPC call.
- Why: `types.proto`, `ContextualCommand.conflict_nonce` and the
  conflict_resolution region.
- Settled when: in every language, a handler that ignores the window fails
  stale, one that resolves it succeeds, and one that passes a made-up value
  fails.

**NC-2** [core] **Mint the nonce.**
- What: the coordinator mints a fresh opaque value per delivery under
  AGGREGATE_HANDLES and COMMUTATIVE (empty window included) and leaves it
  empty under STRICT. Never persisted, never returned.
- Why: as NC-1.
- Settled when: two deliveries of one command carry different nonces.

## CR: COMMUTATIVE in the client libraries (passes 6 and 8)

**CR-1** [clients, router, project] **`protoc-gen-angzarr-conflict`: one
plugin generates `changed()` for every language, held to a golden suite.**
- What: a protoc plugin, `protoc-gen-angzarr-conflict`, that reads
  `(commutative_state)` and `(conflict)` from the descriptors and emits, for
  each marked state message and in every client language (go, rust, python,
  java, csharp, cpp, typescript), a pure `changed(before, after)` returning
  unit paths exactly as the `conflict_units` region of `options.proto`
  specifies (units per field kind, the wildcard for unmarked fields and
  unknown fields, bitwise floats, path syntax and escaping, `[#order]`, the
  non-unique-key fallback, the descend depth bound of 32, and the overlap
  rule with path prefixes). It fails generation on the listed marker
  errors. Plus a shared golden fixture parity suite in angzarr-project
  `parity/`: fixture protos (hatpick's `ListState` worked example among them)
  and before/after state pairs with their expected unit sets, run against
  every language's generated code (and annals'). Each client library's
  COMMUTATIVE resolver then folds to `expected_sequence` and to the head,
  computes `window = changed(expected, head)`, runs decide on the head,
  computes `mine = changed(head, head + events)`, acknowledges the nonce
  (NC-1) when they do not overlap and otherwise fails `ABORTED`; it refuses
  COMMUTATIVE for a state without `commutative_state` (`INVALID_ARGUMENT`)
  and at registration. Delete core's coordinator-side commutative diff.
- Why: decisions 6.12 and 8.1; `ConflictResolution` in `types.proto`; the
  `conflict_units` region of `options.proto`.
- Settled when: the golden suite passes in every language and in annals
  (identical unit sets for every fixture pair); disjoint edits succeed,
  overlapping edits and unmarked-field edits fail stale, and the handler
  writes no conflict code.

**CR-2** [core] **Configuration names COMMUTATIVE as opt-in.**
- What: the conflict-resolution config (HD-2) accepts COMMUTATIVE per
  command type or component, and as a `Handling` override where allowed. It
  is never a default.
- Why: decision 6.12.
- Settled when: COMMUTATIVE applies only where configured or overridden.

## MI: minted ids and always-assigned request ids (pass 8)

**MI-1** [core] **Mint UUIDv7 in core.**
- What: every identifier core mints is a UUIDv7 (RFC 9562), as 16 bytes in
  `UUID` (pass 9: every UUID field is one): today the minted request id
  (MI-3). Replace any v4 or ad-hoc id generation core keeps for
  identifiers (DQ-1 deletes the DLQ's `new_correlation_id` minting
  outright). Client-supplied UUIDs are checked for length only (UU-4),
  never for version.
- Why: decision 8.2; the `minted_ids` region of `types.proto`.
- Settled when: every id core mints is a version-7 UUID, and a client id of
  another version passes through untouched.

**MI-2** [clients] **Mint UUIDv7 in the client libraries.**
- What: wherever an SDK generates an id for its caller (a command helper's
  `request_id`, a new aggregate root), it mints a UUIDv7. These are
  client-supplied ids: the SDK never sets `RequestOrigin.minted`.
- Why: decision 8.2.
- Settled when: in every language, SDK-generated request ids and roots are
  version-7 UUIDs, and helpers reuse the same request id on retry (KS-7).

**MI-3** [core, clients] **Always-assigned request ids.**
- What: after validation and before deduplication, a request-origin command
  whose `request_id` is unset (or a Command with no origin) gets a minted
  UUIDv7 in `request_id`, with `minted = true`, recorded in
  `EventMeta.origin`. A client command that
  arrives with `minted` set is refused `INVALID_ARGUMENT`. A minted id is
  never claimed, fingerprinted or used to deduplicate; `HandleAsync` (KS-6)
  and DLQ replay (DQ-3) still require a client-supplied one. The derived
  correlation then follows PS-3. Clients expose `minted` when reading
  origins and never set it.
- Why: decision 8.3 (supersedes "refuse keyless" in annals too).
- Settled when: every persisted event has a set
  `origin.request.request_id` (for request origins); two identical
  keyless requests both apply, with different minted ids; a client-set
  `minted` is refused; and a client-keyed retry is still answered
  DUPLICATE.

## UU: one UUID type, v5 derived ids, text at the boundary (pass 9)

**UU-1** [clients] **UUID display and input helpers in every client.**
- What: for the generated `UUID` type in Go, Python, Java, C#, C++ and
  TypeScript (Rust is done in `angzarr-proto`, `angzarr_proto::ids`):
  format as canonical text (36 lowercase hex characters, hyphenated
  8-4-4-4-12), parse the hyphenated form in either case (refusing simple,
  braced and URN forms), and convert to and from the language's native UUID
  type and 16-byte arrays. A malformed wire value (not 16 bytes) is reported,
  never silently formatted as a UUID. Client APIs take and return UUID
  objects; text appears only at display and input boundaries.
- Why: decision 9.3; the `uuid` region of `types.proto`.
- Settled when: a shared golden list of (text, bytes) pairs, including
  upper-case input and rejected forms, passes in every language with the
  same results as the Rust crate's `tests/ids.rs`.

**UU-2** [core, clients] **v5 `compute_root` and fact correlation.**
- What: `compute_root(domain, key)` = UUIDv5(`ANGZARR_ROOT_NAMESPACE`
  `d4741b1a-52cd-43cf-add1-3dbb9615510b`, UTF-8 `"{domain}:{key}"`), refusing
  a domain containing `:`, in core and every client; replace whatever root
  derivation each has today. Core sets an absent fact correlation to
  UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`
  `e9ef0ae2-6fc6-4c14-b713-ef03971dd867`, `external_id`) (PS-3). annals does
  the same through `angzarr-proto` (tracked in the session plan).
- Why: decision 9.2; the `derived_ids` region of `types.proto`.
- Settled when: every runtime reproduces the documented values
  (`compute_root("player", "alice@example.com")` =
  `cfe936c0-2912-5ca9-96e6-f37c0b441759`; fact `"pi_1234"` =
  `917f26ae-ea2e-58af-86de-77013a69617e`) from a shared golden list, and
  existing derived roots have a migration (or a wipe, pre-production). The
  same golden list carries the pass-10 fingerprint vectors (KS-4), for core
  and annals; clients need them only if they compute fingerprints.

**UU-3** [core] **Storage columns become uuid-typed.**
- What: every stored request id and correlation id (event meta, the
  idempotency claim store, the correlation index of CQ-1, `dlq_entries.
  correlation_id`) becomes a 16-byte UUID column: Postgres `uuid`, MySQL and
  SQLite `BINARY(16)`/`BLOB`, Bigtable row-key bytes. Where a backend can
  only hold text (KurrentDB's `$correlationId` metadata), it writes the
  canonical text and parses it back.
- Why: decision 9.1: the storage saving is the point of the change.
- Settled when: each backend's schema stores them as 16 bytes, and a
  round-trip test reads back the same UUID.

**UU-4** [core] **Validate UUID fields, and the REST routes.**
- What: refuse `INVALID_ARGUMENT` for a set `UUID` that is not 16 bytes in
  `RequestOrigin.request_id`, `Provenance.correlation_id`,
  `Query.correlation_id`, `CorrelationQuery.correlation_id` and
  `EventStreamFilter.correlation_id`, before minting or deduplication. The
  DLQ filter parses a `correlation_id` literal as canonical text. Serve the
  REST paths `/v1/stream/{correlation_id.value}` and
  `/v1/query/correlations/{correlation_id.value}/events` (URL-safe base64).
- Why: decision 9.1.
- Settled when: tests refuse 0-, 15- and 17-byte ids on each field, and the
  REST routes resolve a base64 correlation.

## CL: D9 cleanups (pass 6)

**CL-1** [core, clients] **`AggregateRoot` is deleted.**
- What: `GetAggregateRoots` streams `Cover` (with the edition).
- Why: D9.
- Settled when: no `AggregateRoot` remains.

**CL-2** [core, clients, router] **`ComponentKind` replaces the type strings.**
- What: `ComponentDescriptor.kind`, `AngzarrDeadLetter.source_component_kind`
  and `StoredDeadLetter.source_component_kind` replace the strings. The DLQ
  publishers and the `dlq_entries` table store the enum; the console filters
  on it. Codegen imports `ComponentKind` from `types.proto`.
- Why: D9.
- Settled when: no component-type string remains on the wire or in the DLQ
  table.

**CL-3** [core] **Drop `AngzarrDeadLetter.cover`.**
- What: publishers and the status console take the stream from the
  payload's cover (`rejected_command.cover` or `rejected_events.cover`).
- Why: D9.
- Settled when: no code reads a dead letter's own cover.

**CL-4** [core, clients, router] **`Projection.next_sequence`.**
- What: rename the field in every user (client-rust sets it from
  `book.next_sequence`; core's projector coordinator sets 0).
- Why: D9.
- Settled when: every producer sets the stream's next_sequence after the
  projected events.

**CL-5** [core, clients, site] **Delete `Synchronize`.**
- What: remove core's `EventQueryService::synchronize` and its test, the
  client-rust test backend's stub, the gateway route, and the site's
  `pitch.mdx` claim that it is a catch-up subscription.
- Why: decision 6.9.
- Settled when: no `Synchronize` remains.

## AU: attempt-audit sink (pass 6, D3)

**AU-1** [core] **An optional attempt-audit observability sink.**
Held until the user says when. Core code: the interface plus in-memory and
no-op implementations only.
- What, the interface specification:
  - **Shape.** One trait (or interface) per coordinator,
    `AttemptSink::record(&self, attempt: &Attempt)`, non-blocking and
    infallible from the caller's view: a sink error or slowness never fails,
    delays or changes command handling (it is buffered or dropped, and
    counted by a metric).
  - **Composable.** A command-handler coordinator takes zero or more sinks;
    a fan-out sink combines several. The default is the no-op sink.
  - **What is reported.** One `Attempt` per delivery that reaches the
    coordinator, reported once its outcome is known: the target stream
    (`Cover`), the command type URL, the arm (command or fact), the
    `Origin`, the `Provenance`, `Handling` as received and as resolved, the
    RPC (mode), the receive time, the duration, the rules version, the
    payload fingerprint, and optionally the payload bytes (configurable,
    since a payload may hold personal data). The outcome is one of: APPLIED
    (with the sequence range), DUPLICATE, PARKED, a rejection (the gRPC code
    and message: a business rejection, a stale sequence, a fingerprint
    mismatch), a malformed refusal (`INVALID_ARGUMENT`, including
    arm/origin mismatches and unknown editions), or a handler bug
    (`INTERNAL`). `HandleAsync` reports the enqueue (ACCEPTED) and, later,
    the processed outcome as a second attempt record with the same key.
  - **Never in the event store.** Attempts are observability, not domain
    history: no stream, no projection, no replay, and no effect on
    idempotency claims.
  - **Implementations.** No-op (the default) and in-memory (a bounded
    buffer, readable in tests and development). Durable sinks (a log, an
    audit queue) are left to deployments.
- Why: D3: rejections and attempts leave nothing in any stream.
- Settled when: the user says when; then the interface is in core, both
  implementations are tested, and a rejected command shows up in the
  in-memory sink with its code.

## GAP: gaps carried from earlier passes

**GAP-1** [core] **Upcasting runs only on aggregate loads.**
- What: sagas, PMs, projectors and queries see raw stored versions, and a
  missing rule silently drops the event on rebuild. Upcast on every read
  path, and fail on an unknown type URL, naming it (as annals' strict replay
  does).
- Why: correctness on rebuild.
- Settled when: every read path upcasts, and golden fixtures run in CI.

**GAP-2** [core] **No multi-stream unit of work, and 1:1 upcasters.**
- What: angzarr appends one command's events to one stream per write, and an
  upcaster maps one event to one. For comparison:
  - Marten: one session appends to many streams in one transaction.
  - Axon: a `UnitOfWork` spans one message. Upcasters can split or drop
    events.
  - **KurrentDB: `MultiStreamAppend` (25.1 and later).** This corrects the
    earlier "no multi-stream transactions".
  - annals: atomic chains across streams in one transaction.
- Why: matching annals would need a coordinator-level unit of work.
- Settled when: the user decides whether angzarr wants one.

**GAP-3** [project] **`buf breaking` does not gate merges.**
- What: `just proto-breaking` is manual, and `contracts.yml` lints only.
- Why: wire breaks are accepted pre-freeze.
- Settled when: it gates at v0.1.0, or before hatpick stores production
  events. The same moment starts `reserved` statements for every removed
  field (decision 6.6, D6, written in `proto/buf.yaml`).

## DOC: site, feature specs and branches

**DOC-1** [site] **Fix the embedded proto regions.**
- What: the site embeds regions that no longer exist: `edition`,
  `snapshot_retention`, `rejection_notification`, `page_header` and
  `sync_mode`, and (pass 6) `merge_strategy`. Use `provenance`, `handling`,
  `outcome`, `command_modes`, `idempotency_claim`, and (pass 6)
  `conflict_resolution`, `correlation_query` and `edition_admin`, and
  (pass 9) `uuid` and `derived_ids`. The
  conflict-resolution table needs the config precedence, the nonce and
  COMMUTATIVE, and the stale-sequence code is now `ABORTED`.
- Why: passes 1–6.
- Settled when: a strict site build passes.

**DOC-2** [site] **Rewrite the stale pages.**
- What: about ten pages: the merge-strategy and sync-mode tables, upcasting,
  the facts audit claims, the glossary (`cover.md`, `cloud-event.md` with the
  new id format), and every page on CASCADE, compensation, speculative
  execution and snapshot retention.
- Why: passes 1–5.
- Settled when: no page describes removed behaviour.

**DOC-3** [site] **Correct `components/commands-vs-facts.md`.**
- What: remove the Axon "decision vs notification commands" claim (C3).
  Replace "Angzarr's Solution" (facts as events with a fact sequence) with
  the `Fact` arm. Cite Equinox ingesters, not Event Modeling (C1).
- Why: the corrections.
- Settled when: the page matches the protos.

**DOC-4** [site] **Add pages for the pass-5 contract.**
- What: idempotency (keys, scope, retention, required `request_id`), the
  transient reactor outbox, status codes, PARKED, edition sink suppression,
  and the DLQ replay audit.
- Why: pass 5.
- Settled when: each topic has a page.

**DOC-5** [project] **Rewrite the feature specs.**
- What: retire the specs for removed features (CASCADE 6, ISOLATED 3,
  notifications and compensation 4, speculative 3, `undoes` 2). Add
  coordinator-contract specs for pass 5: key dedup per kind, rejection
  release, fingerprint mismatch, PARKED, `projector_failures`, ABORTED
  retries, edition sink suppression, and the replay audit.
- Why: passes 2 and 5.
- Settled when: `just contracts` passes with the new specs.

**DOC-6** [project] **The `feat/blackjack-spec` branch.**
- What: the branch exercises removed features
  (`cascade_error_mode.feature`, `compensation_delivery.feature`,
  `snapshot_retention.feature`, `speculative_client.feature`, ISOLATED in
  `sync_modes.feature`, compensation-based blackjack flows). Rebase it or
  retire those scenarios.
- Why: passes 2 and 4.
- Settled when: the branch is rebased or closed.

---

## Counts

| Workstream | Items |
|---|---|
| KS: idempotency key store | 12 |
| OB: transient reactor outbox | 6 |
| PS: provenance stamping and correlation | 5 |
| BO: business output is payloads only | 3 |
| RV: rules_version declaration | 2 |
| MD: the three RPC modes and the Outcome | 6 |
| ST: status codes | 2 |
| ED: editions, external sinks, CloudEvent id | 4 |
| SN: snapshots | 3 |
| RT: recorded_at and temporal queries | 2 |
| DQ: DLQ replay | 6 |
| RN: renames | 2 |
| PR: process-manager replies | 2 |
| FA: fact pipeline | 3 |
| HD: Handling resolution | 5 |
| WS: wire-shape migration | 5 |
| RM: removed features | 6 |
| TG: type generation and router | 2 |
| OR: one Origin (pass 6) | 2 |
| CQ: cross-domain correlation query (pass 6) | 2 |
| EA: edition administration (pass 6) | 4 |
| NC: the conflict nonce (pass 6) | 2 |
| CR: COMMUTATIVE in the client libraries (passes 6 and 8) | 2 |
| MI: minted ids and request ids (pass 8) | 3 |
| UU: one UUID type, v5 derived ids (pass 9) | 4 |
| CL: D9 cleanups (pass 6) | 5 |
| AU: attempt-audit sink (pass 6, held) | 1 |
| GAP: carried gaps | 3 |
| DOC: site, specs, branches | 6 |
| **Total** | **110** |

## By-repo index

An item tagged with several repos appears under each of them.

| Repo | Items |
|---|---|
| core | KS-1–6, KS-8–12, OB-1–3, OB-5–6, PS-1–5, BO-1, RV-1, MD-1–5, ST-1, ED-1–4, SN-1–3, RT-1–2, DQ-1–6, RN-1–2, PR-1–2, FA-1–2, HD-1–5, WS-1–5, RM-1–3, RM-6, TG-1, OR-1–2, CQ-1–2, EA-1–3, NC-2, CR-2, MI-1, MI-3, UU-2–4, CL-1–5, AU-1, GAP-1–2 |
| router | OB-4, OB-6, PS-2, RN-1, FA-3, HD-3, WS-2, TG-1–2, OR-2, NC-1, CR-1, CL-2, CL-4 |
| clients (go, rust, python, java, csharp, cpp, typescript) | KS-7, BO-2, RV-2, MD-6, ST-2, ED-3, RN-1–2, FA-3, HD-5, WS-1–2, RM-4, RM-6, TG-1, OR-2, CQ-2, EA-4, NC-1, CR-1, MI-2–3, UU-1–2, CL-1–2, CL-4–5 |
| examples | BO-3, WS-2, RM-5 |
| site | RN-2, EA-4, CL-5, DOC-1–4 |
| project (features, CI, branches, parity) | EA-4, CR-1, GAP-3, DOC-5–6 |
