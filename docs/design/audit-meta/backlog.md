# Code follow-up backlog (passes 1–14)

Part of the [audit-meta design record](../audit-meta-followups.md).

The `feat/audit-meta` passes (1–14) changed only the protos, the
`rust/angzarr-proto` crate and the docs. **Nothing in this backlog is done.** It is the
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

## CI: command identity and deduplication on events (pass 12)

Replaces the KS key-store workstream (closed below).

**CI-1** [core] **The (stream, `command_id`) index, and dedup on events.**
- What: in every storage backend, index `EventMeta.causation.command_id`
  per stream
  (not unique: one command may write several events). Before business code
  (pipeline step 3), look up (`CommandBook.cover`, `command_id`). On a hit,
  read those events in sequence order and answer `DELIVERY_OUTCOME_DUPLICATE`
  without running business code. An append that loses the optimistic
  sequence race re-runs from the lookup. Delete today's causation and fact
  dedup paths, which this replaces.
- Why: decision 12.2; the `command_identity` region of `types.proto`.
- Settled when: on every backend, two concurrent deliveries of one command
  give exactly one APPLIED and one DUPLICATE with identical events; a
  redelivery of a zero-event decision is decided again (APPLIED); and the
  lookup cost is independent of stream length.

**CI-2** [core, clients] **The `command_id` derivations.**
- What: reaction command ids are UUIDv5(`ANGZARR_COMMAND_NAMESPACE`
  `e2c9f744-9fe1-4b4b-bfee-ae514dde293b`, the six netstrings of the trigger's
  domain, edition (`""` for main), root text, sequence, component and
  index). Fact command ids are UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`,
  `external_id`). Implement both in core (the reactor coordinators stamp
  reaction ids) and in any client that computes them; annals uses
  `angzarr_proto::ids` (tracked in the session plan).
- Why: decision 12.1; the `derived_ids` region of `types.proto`.
- Settled when: every runtime reproduces the documented vectors
  (`45764676-e6e4-56fe-8c80-d782423577ee` and the others in `types.proto` and
  the crate's `tests/ids.rs`) from a golden list shared with UU-2.

**CI-3** [core] **Assign ids before deduplication.**
- What: at pipeline step 2, mint a UUIDv7 `command_id` for a client
  Command without one (`HandleAsync`: before enqueueing). Derive a Fact's,
  and refuse one sent with any other value (`INVALID_ARGUMENT`). Set an
  absent `correlation_id` (PS-3). Dead letters store the command with its
  ids assigned and its Handling as sent. Delete the `HandleAsync` and replay
  requirement for a client-supplied key, and the `UNIMPLEMENTED` answer for
  backends without atomic claims.
- Why: decisions 12.1 and 12.2 (the `HandleAsync` judgement call).
- Settled when: a keyless `HandleAsync` command redelivered from the queue
  is answered DUPLICATE; a replayed dead letter of a keyless command is
  DUPLICATE when the original applied; a Fact with a foreign `command_id` is
  refused.

**CI-4** [core] **The normative pipeline order.**
- What: validate, assign ids, deduplicate, resolve or check Handling, then
  business code, in every RPC and in the reaction and replay paths. Today
  the STRICT check and dedup are not ordered by contract.
- Why: decision 12.5 (review T6).
- Settled when: a retry of an applied STRICT command whose
  `expected_sequence` is now stale is answered DUPLICATE, never ABORTED.

**CI-5** [core] **Framework-authenticated entry points.**
- What: issue framework components (saga and PM coordinators, the outbox
  dispatcher, the DLQ replayer) mTLS identities, and recognise them at every
  coordinator. Refuse `CommandPage.causation_id` (on a reaction command or
  a saga's rejection fact) from any other caller, and every call to
  `SagaCoordinatorService.Execute`, with `PERMISSION_DENIED`
  (`ProcessManagerCoordinatorService` is deleted by 14.31). The
  REST gateway forwards the caller's identity rather than its own.
- Why: decision 12.10 (review T5, SG3 and CH1); the `entry_points` region
  of `command_handler.proto`.
- Settled when: a client `Handle` with a `causation_id` and a client call to
  `POST /v1/saga/execute` are both refused `PERMISSION_DENIED`, and the same
  requests from a framework identity succeed.

**CI-6** [core] **Security logs, and no actor in the data.**
- What: every coordinator and admin service writes the authenticated caller,
  the RPC, the time and the `command_id` (or the edition name or dead-letter
  id) to a deployment-configured security log. Delete every actor column and
  field: `Provenance.actor` stamping, `editions.created_by`, and the DLQ
  replay operator column (`dlq_replay_audit`).
- Why: decision 12.3; the `security_logs` region of `types.proto`.
- Settled when: no stored event, edition or dead-letter row carries an
  identity, and each RPC's caller appears in the security log with the
  command id.

**CI-7** [clients] **SDK command ids.**
- What: every SDK's command helpers set `CommandPage.command_id` (a v7
  minted for the caller, one per command) and reuse it verbatim on retry.
  SDKs no longer need deterministic
  serialisation for idempotency. Correlation: a builder sends no
  `correlation_id` unless the caller sets one; the coordinator fills it.
  There is no batch helper (decision 14.27).
- Why: decisions 12.1, 14.15 and 14.27. Replaces KS-7.
- Settled when: a retried SDK call is answered DUPLICATE, and parity C-0305
  and C-0575 pass.

**CI-8** [core] **Dead-letter entries for parked facts.**
- What: deduplicate DLQ entries per (stream, `command_id`), so a source that
  keeps redelivering a fact whose ingest fails updates one entry rather than
  adding entries.
- Why: a parked fact writes no event, so dedup never sees it. Carried over
  from KS-9.
- Settled when: N redeliveries of a failing fact leave one DLQ entry, with an
  attempt count.

### KS: idempotency key store (pass 5, W1): closed

Superseded by pass 12 (decision 12.2: no key store). Each item's
disposition:
- **KS-1** (claim store), **KS-2** (check and answer from the range): closed
  and replaced by CI-1.
- **KS-3** (release rejections): closed. Nothing to release, because a
  rejection writes no event.
- **KS-4** (fingerprint), **KS-10** (fact mismatch refusal), **KS-11** (the
  fact-mismatch setting), **KS-12** (causation mismatch): closed. There is
  no fingerprint, and a reused id with a different payload goes undetected
  (an accepted cost).
- **KS-5** (retention and expiry): closed. Dedup is forever.
- **KS-6** (`HandleAsync` key requirement and backend capability): closed
  and replaced by CI-3.
- **KS-7** (deterministic serialisation and request keys): closed and
  replaced by CI-7.
- **KS-8** (reactions on backends without atomic claims): closed. The
  capability no longer exists.
- **KS-9** (parked-fact DLQ entries): moved to CI-8.

## OB: transient reactor outbox (pass 5, W3)

The outbox is one capability, not a saga feature (decision 14.31, the
owner's ruling of 2026-10-28: "if we need an outbox it should be
polymorphic"). Build it once, naming no component kind: any component
whose output leaves its own stream uses it. Today only sagas do, for
their commands and, since 14.31, the rejection facts their on-refused
callbacks craft.

**OB-1** [core] **The transient outbox, kind-agnostic; sagas first.**
- What: one outbox that stores a component's outbound output atomically
  with its source checkpoint (position store), dispatches it, then clears
  it, with no knowledge of the component's kind. Wire sagas to it: a
  `SagaResponse`'s commands, and the rejection facts of their on-refused
  callbacks (OB-7). Today saga commands are sent directly, with
  `SyncMode::Async` hardcoded in `handlers/core/saga.rs`.
- Why: `saga.proto`, the transient outbox text; decision 14.31.
- Settled when: in a crash-injection test (crash after store, before
  dispatch), the restart re-sends byte-identical commands with the same
  command ids, and the saga is not re-run for that trigger; and the
  outbox's interface names no component kind.

**OB-2** (the PM transient outbox): **closed** by decision 14.31. A PM
is a domain: it consumes no stream, so it has no checkpoint, and its
only output is its own events, appended like an aggregate's. It needs no
outbox. Removing the PM's command dispatch and any reactor-determinism
dead-lettering from core is PR-6.

**OB-7** [core, clients, router] **The saga's on-refused callback.**
- What: when the outbox relay receives a business rejection
  (`FAILED_PRECONDITION`) of a saga command whose type the saga's
  descriptor lists in `refusal_types`, call `SagaService.OnRefused`
  with `Refusal { event, command, response }`; check the returned fact
  is for the saga's `input_domain` and sets no Handling; stamp its
  `causation_id`, correlation, edition and `"angzarr-refusal:"` origin;
  and write it as a new outbox entry in the transaction that clears the
  command's entry. A refused command with no callback is dead-lettered
  and alerted, and a failing callback dead-lettered and alerted (owner's
  rulings). Every coordinator accepts a `Fact` with `causation_id` only
  for the domain of the stream it names. angzarr-cli generates
  `on_refused_<Command>(Refusal)` from `(on_refused)`, lints mismatches,
  and fills `refusal_types`; client libraries serve `OnRefused`. annals
  makes the same call directly in its chain.
- Why: decision 14.31, amending 2.2; `SagaService` (Refusals) and
  `Refusal` in `saga.proto`, `(on_refused)` in `options.proto`, the
  `derived_ids` region (Refusal facts) of `types.proto`.
- Settled when: scenarios C-0608 to C-0610, C-0612, C-0613 to C-0620
  and EU-1562 pass, and the worked refusal-fact id in `types.proto` is
  reproduced by core, every client and annals.

**OB-3** [core] **Co-locate checkpoints and outboxes.**
- What: the position store and the outbox must share a transaction, so the
  backend matrix gains a "transient outbox" capability.
- Why: "stored atomically with the source checkpoint".
- Settled when: every backend either supports it or refuses to host
  reactors.

**OB-4** [router] **Reactor output returns to the coordinator.**
- What: router dispatch functions (for example
  `angzarr_router_dispatch_saga`) return the reactor's output for the
  coordinator to store, and never send it themselves.
- Why: the outbox owns dispatch.
- Settled when: the router API has no send path for reaction commands.

**OB-5** [core] **Outbox documentation.**
- What: rewrite `src/bus/README.md` and the patterns docs, which describe a
  PM-only outbox.
- Why: the outbox is one kind-agnostic capability, used today by sagas;
  a PM needs none (decision 14.31).
- Settled when: the docs match the protos.

**OB-6** [core, router] **Per-event causation for saga output (W3a).**
- What: a saga receives a whole `EventBook`, and core stamps causation with
  the book's maximum sequence (`source_max_sequence` in
  orchestration/saga/mod.rs`). That is imprecise for audit, and the derived
  command id (CI-2, which hashes the trigger) changes if catch-up delivers
  the events in different chunks. Either deliver one triggering event per
  saga call, or have the router report which event produced each command,
  so the coordinator stamps the exact `causation_id`.
- Why: W3(a), the one part of W3 that pass 5 left open (review SG2).
  `causation_id` is "always the triggering event" in the contract.
- Settled when: re-chunked catch-up re-sends commands with identical
  command ids, and each command's `causation_id` names the event it answers.
- The same holds for a saga's rejection facts, whose refusal origin is
  derived from the refused command's reaction name (decision 14.31).

## PS: provenance stamping and correlation (passes 1, 5 and 12, W4/W5)

**PS-1** [core] **Persist `EventMeta`.**
- What: stamp `EventMeta` on every page the coordinator writes, in its
  pass-14 shape: `causation` (`command_id`, for every event, a PM's
  included; `triggering_event` is deleted by 14.31), `fact` (facts),
  `correlation_id`, `recorded_at`, and `rules_version` (from the response,
  RV-1). No actor, origin or base sequence, and no copy of a reaction
  command's `causation_id` (it goes to traces, PS-6).
- Why: passes 1, 12 and 13 (decisions 12.4, 13.1 and 13.3).
- Settled when: a round-trip test reads back full meta for a client
  command, a reaction command, a fact and a PM process event, and a
  reaction command's events carry no trigger.

**PS-2** [core, router] **Stamp reaction identity from the trigger.**
- What: the saga and PM coordinators stamp each emitted command's
  `causation_id` (the trigger's `EventRef`), its derived `command_id`
  (CI-2) and the trigger's `correlation_id`. A reaction command that sets
  any of them to a different value, emits a Fact, or sets `fact_origin`, is
  dead-lettered and alerted.
- Why: W5 and decision 12.1. (W4's actor stamping is gone with the actor,
  decision 12.3.)
- Settled when: tests show an empty reaction command is stamped, and a
  foreign correlation or causation is refused.

**PS-3** [core] **Correlation is never empty.**
- What: use the caller's value (a UUID). Otherwise set it, at pipeline step
  2: a client Command's `command_id` verbatim (client-supplied or minted),
  and a Fact's derived `command_id` (UUIDv5 of `external_id`). Never mint a
  correlation. Reaction commands keep the trigger's (PS-2).
- Why: W5; decisions 8.3, 9.2 and 12.1.
- Settled when: retries of one client-keyed command land in one correlation
  equal to its command id; redeliveries of one fact land in its documented
  v5 value; and no persisted event has an unset correlation.

**PS-4** [core] **Correlation is per page only.**
- What: stop reading correlation from `Cover`, and implement
  `Query.correlation_id` against `EventMeta.correlation_id` (one
  correlation per write).
- Why: pass 1.
- Settled when: query-by-correlation works across a domain's streams.

**PS-5** [core] **Fix the filed core bugs.**
- What: the correlation query ignores the domain (uncurious-president), and
  cached replays relabel correlation (unpaved-ultimate). Both are in
  angzarr's task log.
- Why: they corrupt the provenance this contract relies on.
- Settled when: both tasks are closed.

**PS-6** [core] **Record the reaction trigger edge in traces (pass 13).**
- What: the saga and PM coordinators record, for every reaction command
  they stamp, its `causation_id` (the trigger's `EventRef`) and its
  `command_id` in the command's OpenTelemetry span (as span attributes,
  with the span linked to the trigger's), and the receiving coordinator
  records the `command_id` on the append's span. Logs carry the same pair.
  This is the only record of "which event led to this reaction command"
  once the events no longer carry it.
- Why: decision 13.3; the `command_identity` region of `types.proto`
  (`causation_id` is transport and trace metadata), and the forward
  causation text on `CorrelationQuery`.
- Settled when: from a trace of a saga chain across three domains, every
  reaction command's trigger and the events it produced can be read off,
  and no event carries the trigger.

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
  payloads (`Any`), not a raw `EventBook`; the client library adds the
  post-command state itself (SN-4).
  Remove every SDK path that lets a handler set a cover, sequence or meta.
- Why: the "custom covers" escape hatch is gone (`options.proto`).
- Settled when: no generated handler signature mentions `EventBook` as
  output.

**BO-3** [examples] **Fix handlers that set covers, sequences or meta.**
- What: update the examples that do this.
- Why: BO-1 would refuse them.
- Settled when: the example suites pass against BO-1.

## RV: rules_version reporting and snapshot selection (passes 5, 12 and 14, W8)

**RV-1** [core] **Registration, stamping and version skew.**
- What: call `ComponentService.Describe` on the business process when the
  coordinator first connects and every time its channel comes back up;
  each successful answer (the one `ComponentDescriptor` of the one
  component behind this coordinator) replaces the held one. Deliver nothing
  while no descriptor is held (`UNAVAILABLE` to a waiting caller; queued
  and reaction deliveries stay queued). Refuse a descriptor with an empty
  `rules_version`: hold nothing, log an error
  naming the process and component, alert, and stay `NOT_SERVING`. Log
  every failed Describe call, and alert only once it has kept failing past
  `describe_alert_grace_period` (configuration, default 2 minutes). Report
  `SERVING` (grpc.health.v1 and the readiness probe) only after a
  successful Describe. Read `rules_version` from every `CommandHandlerResponse` and
  `ProcessManagerHandleResponse`: if it differs from the registered version
  (empty included), refuse the response as a handler bug (persist and send
  nothing; `INTERNAL` to a `Handle`/`HandleSync` caller; dead-letter and
  alert an asynchronous or reaction delivery, a PM trigger included).
  Otherwise stamp it, unaltered, on that response's events
  (`EventMeta.rules_version`) and any snapshot written from it
  (`Snapshot.rules_version`).
- Why: decisions 14.1, 14.5, 14.6, 14.10 and 14.11 (superseding 12.6).
- Settled when: scenarios C-0518 to C-0521, C-0558, C-0559 and C-0561 to
  C-0564, C-0566 and C-0567 pass:
  during a rolling deployment each event carries the full version of the
  instance that decided it, and a skewed or versionless answer persists
  nothing.

**RV-2** [clients, router] **Report the build version.**
- What: bake the business binary's full version in at build time (e.g. from
  versionator) and put it on every response and in the component's
  descriptor (`ComponentDescriptor.rules_version`); refuse to build or start
  without one. Serve `ComponentService.Describe` with the one component's
  generated descriptor; business code never implements it. A business
  process hosts exactly one component: drop any multi-component host or
  router support. No hand-chosen label and no snapshot-compatibility
  declaration in business code. Remove any client-side snapshot check and any
  `snapshot_refused` handling.
- Why: decisions 14.1, 14.6 and 14.10.
- Settled when: every SDK fills `rules_version` on every response and in
  every Describe descriptor with the same build version, and folds whatever
  snapshot it is delivered, and a host or router refuses a second
  component. Scenarios C-0533 to C-0536, C-0565, C-0579 and C-0580.

**RV-3** [core] **The coordinator and the query service select snapshots.**
- What: before offering a snapshot with a delivery (aggregate or PM), or
  returning one from `EventQueryService` (a `TemporalQuery` included),
  check its state type URL against the registered `StateDescriptor.type_url`
  and its `rules_version` against the registered version under the
  domain's compatibility rule: by default, after stripping one leading
  `v`/`V`, equal major.minor when both parse as SemVer 2.0.0, otherwise
  exact equality; or the domain's configured accept pattern and optional
  reject pattern, which replace the default (RE2, full match, a reject
  match wins; a pattern outside RE2 refused at configuration load). A
  snapshot that fails is not used: deliver or return every page from
  sequence 0. A query is judged against the answering coordinator's own
  registration, and uses no snapshot while that coordinator holds none.
  Count snapshots passed
  over in a metric. Replaces SN-3's check
  and pass 12's refuse-and-redeliver path.
- Why: decisions 14.1, 14.3, 14.4 and 14.21 (review T13 is settled by the
  registered state type).
- Settled when: scenarios C-0522 to C-0530, C-0553 to C-0556 and C-0560 pass: a
  version or state-type change makes the next delivery or query carry no
  snapshot, and the replayed state equals a full replay.

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
- What: saga delivery (from the outbox, OB-1), of commands and of
  rejection facts, chooses `Handle` or `HandleAsync` from component
  configuration. A PM sends no commands (decision 14.31). Today `SyncMode::Async` is hardcoded in
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

**SN-4** [clients, router, core] **The state on every response.**
- What: the client library puts the post-command state in
  `CommandHandlerResponse.events.snapshot.state` on every response, and a
  PM's post-reaction state in `ProcessManagerHandleResponse.process_state`
  (field 5) on every response;
  no business-code hook decides when. Core persists it per the domain's
  storage policy (SN-2; default newest only), stamping `sequence` and
  `rules_version`, and offers the stored bytes unchanged with the next
  delivery (subject to RV-3 and SN-1).
- Why: decisions 14.12 and 14.14.
- Settled when: scenarios C-0568 to C-0571 pass.

**SN-3** [core] **Snapshot version-discard (pass 6, D8).** Closed by pass
12 and replaced by RV-3, which pass 14 moved back to the coordinator
(decision 14.1).

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
- What: keep the original `command_id`, `correlation_id` and
  `causation_id` (the dead letter stores them assigned, CI-3), and deliver as
  a framework component (CI-5). Delete `new_correlation_id` minting
  (`src/status/handlers/dlq.rs`, `src/dlq/audit.rs`), and set
  `ReplayDeadLetterOk.correlation_id` to the original.
- Why: W9.
- Settled when: replaying an entry whose original did apply is answered
  DUPLICATE.

**DQ-2** [core] **The replay audit record.**
- What: extend `dlq_replay_audit` (`migrations/status/{postgres,sqlite}`).
  Add an outcome of PENDING/APPLIED/DUPLICATE/FAILED, `outcome_at` and
  `detail`. No operator column: who replayed goes to the security log
  (CI-6). Drop `new_correlation_id` and
  `original_correlation_id`. Surface the records as
  `StoredDeadLetter.replays`, and move the outcome on from PENDING when the
  replayed delivery is decided, correlating by `command_id`. (The H-31
  `idempotency_key` column guards the replay *request* and stays.)
- Why: W9 (`dlq_admin.proto`).
- Settled when: `GetDeadLetter` shows a replay going PENDING, then APPLIED.

**DQ-3** [core] **Replay refusals.** Closed by pass 12: dedup by
`command_id` is permanent, so there is no age refusal, no override and no
client-key requirement (decision 12.2). Delete the refusals if any were
built.

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

**RN-1** [core, router, clients] **Delete `decided_at` (no `base_sequence`).**
- What: remove `EventMeta.decided_at` everywhere. Pass 5 renamed it
  `base_sequence`, and pass 12 deleted it: the head a decision saw is the
  sequence of its write's first event.
- Why: W14; decision 12.4.
- Settled when: neither name remains outside history.

**RN-2** [core, clients, site] **The projector coordinator's `HandleAsync`.**
- What: rename the projector coordinator's `Handle` to `HandleAsync`, at HTTP
  `POST /v1/projector/async` (gateway and Envoy routes too). Update the site's
  architecture diagrams, and the stale `service ProjectorCoordinator` block in
  `pitch.mdx`.
- Why: W14.
- Settled when: the gateway serves the new path, and the old one is gone.

## PR: process-manager replies, process events and inputs (passes 2, 5, 13 and 14, W6)

**PR-1** [core] **Route replies by correlation.**
- What: route replies to the PM instance by `correlation_id`. A PM is a
  domain that sends no commands and subscribes to nothing (decision
  14.31): the saga from the PM's domain builds each step's command from a
  PM event, carrying its correlation, and the saga from the target's
  domain turns the target's events into commands addressed to the
  instance that correlation names.
- Why: W6. This **corrects** the pass-2 backlog item, which said a reply's
  causation "names the PM's event".
- Settled when: scenario C-0601 passes.

**PR-2** (hard rejections of PM commands): **closed** by decision 14.31.
A PM sends no commands. The saga that carries a PM's step handles a hard
failure like any saga command (retry when retryable, otherwise
dead-letter), and a business refusal reaches the PM as the rejection
fact of that saga's on-refused callback (OB-7).

**PR-5** [core] **Each PM's coordinator delivers to its one PM.**
- What: a PM's coordinator is a command handler coordinator for the PM's
  domain, delivering each command and fact to the one PM behind it, with
  that PM's own state, and persisting the answer to that PM's own stream.
  Several PMs told of one event are several sagas and several
  coordinators.
- Why: decisions 14.19, 14.20 and 14.31; `process_manager.proto`.
- Settled when: scenario C-0578 passes.

**PR-3** (meta for a PM's own process events, review PM2): **closed** by
pass 13 (decision 13.2). The rule is in the protos; its implementation is
PR-4.

**PR-4** (stamp and deduplicate PM process events on their trigger):
**closed** by decision 14.31, which supersedes 13.2. A PM has no
triggers: its events are its commands' and facts' events, stamped and
deduplicated by `command_id` like any domain's (CI-1, PR-6). Delete
core's `trigger_handled` lookup and any (stream, `triggering_event`)
index.

**PR-6** [core, clients, router] **A PM is a domain.**
- What: serve a PM exactly as an aggregate: its business process
  implements `CommandHandlerService`, its coordinator serves
  `CommandHandlerCoordinatorService` for the PM's domain, with the
  aggregate's pipeline (commands may be refused, facts never are, dedup
  by `command_id` before the handler), plus one rule: a command's or
  fact's `correlation_id` must equal its cover's root (set to it when
  unset). Delete `ProcessManagerService`, `ProcessManagerCoordinatorService`,
  `ProcessManagerHandleRequest`/`Response`, the PM's subscriptions,
  checkpoint and trigger delivery, and its command output, from core, the
  router and the client libraries.
- Why: decision 14.31; `process_manager.proto`.
- Settled when: scenarios C-0596 to C-0603 pass.

**PR-7** [core, clients, router] **Starting inputs (B1).**
- What: angzarr-cli refuses `starts` on an aggregate's `(command)` entry,
  warns about a PM with no starting input, and generates
  `ComponentDescriptor.starting_types`; the client library answers
  `Describe` with it. The PM's coordinator refuses a non-PM descriptor
  listing starting types; for a correlation with no instance it skips a
  non-starting fact silently (answered `APPLIED`, no events) and refuses
  a non-starting command (`FAILED_PRECONDITION`, `PM_NO_INSTANCE`).
- Why: decision 14.31 (annals ruling B1, adapted; the command case
  ruled by the owner, 2026-10-28); `CommandOptions.starts` (`options.proto`),
  `ComponentDescriptor.starting_types` (`types.proto`),
  `process_manager.proto`, Starting an instance.
- Settled when: scenarios C-0592 to C-0595, C-0606, C-0607 and C-0611
  pass.

## VC: command versioning (pass 12)

**VC-1** [clients, router] **Upcast commands and facts before dispatch,
and refuse unknown types.**
- What: inside `CommandHandlerService.Handle`, run the payload (Command or
  Fact) through the library's upcaster chain (the event chain, by type URL)
  before dispatch. Refuse a type URL that, after upcasting, reaches no
  handler with `INVALID_ARGUMENT`: the status message names the type URL as
  sent, and a `google.rpc.ErrorInfo` in the details carries the type URL
  the chain ended at under metadata key `upcast_type_url`.
  Document in each SDK that command upcasters are a temporary migration aid
  (additive fields, or the domain handling both versions, come first).
- Why: decisions 12.11, 14.2 and 14.8; `upcaster.proto`.
- Settled when: scenarios C-0537 to C-0540 pass in every language.

## FA: the fact pipeline (pass 2)

**FA-1** [core] **Reflective dispatch.**
- What: the body arm picks the pipeline (Command goes to decide, Fact to
  ingest), and the type URL picks the handler.
- Why: pass 2.
- Settled when: a fact never reaches decide.

**FA-2** [core] **Refuse and park.**
- What: refuse a `Fact` that sets any Handling field (`INVALID_ARGUMENT`;
  decision 12.9).
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
  Precedence: Handling, then command type, then component, then the
  built-in default (COMMUTATIVE where the registered state supports it,
  otherwise STRICT; HD-4). Add forbid-override, and refuse a resolution the
  registered state does not support, both `INVALID_ARGUMENT`. The config
  shape needs designing.
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

**HD-4** [core] **The default conflict resolution comes from the registered
state.**
- What: `CommandPageExt::effective_merge_strategy` calls
  `MergeStrategy::or_default_commutative`. Replace it with a lookup in the
  component's registered `StateDescriptor` (CR-3): COMMUTATIVE when listed,
  otherwise STRICT. Rename to `ConflictResolution` (pass 6, D10).
- Why: decision 12.7 (superseding pass 6's "never the default").
- Settled when: an unconfigured stale command is resolved COMMUTATIVE for a
  state that lists it, and `ABORTED` for one that does not.

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
  `SagaCoordinatorService.Execute` take `EventBook`
  (`ProcessManagerCoordinatorService` is deleted by 14.31).
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

## OR: arm and fact source (passes 6 and 12)

**OR-1** [core] **Validate the arm against `fact_origin`.**
- What: refuse a Fact without `fact_origin`, or with an empty
  `external_id`, and a Command with a `fact_origin`, before deduplication:
  `INVALID_ARGUMENT` for a client; dead-letter and alert for a reactor
  (including a reactor that emits a Fact).
- Why: the `command_identity` region of `types.proto` (decision 12.1).
- Settled when: each mismatch is refused in every mode, and none reaches
  business code.

**OR-2** [core, router, clients] **Delete `Origin`.** Closed in its pass-6
form (`Origin` is deleted). What remains: delete every use of `Origin`,
`RequestOrigin` and `Causation` and their mapping code, in favour of the
page's `command_id`, `correlation_id`, `causation_id` and `fact_origin`,
and of `EventMeta`'s `causation` oneof, `correlation_id` and `fact`.
- Settled when: no code names the deleted messages.

## RD: re-driving reactions (pass 13, T8)

**RD-1** [core, clients] **Standard, shipped re-drive commands.**
- What: the framework ships commands that trigger reprocessing, so a
  developer repairing what a buggy reactor did never hand-builds them. A
  re-drive is a NEW client command (a fresh `command_id`) addressed to a
  stream or reactor, naming what to reprocess (for example a trigger
  `EventRef`, or a range of a source stream), whose events the reactor
  reacts to under its current rules version. Because its ids are new, its
  output applies and appends after the buggy-era events, which stay. Not a
  checkpoint reset (resets are for recovery only, and their output
  deduplicates). Define the command types (in the angzarr protos or a
  shipped domain), the coordinator or reactor handling, and an operator
  entry point.
- Why: decision 13.4; the `command_identity` region (Reactor re-runs) of
  `types.proto`; `idempotency.md` and the guide's "Re-running reactors".
- Settled when: after a reactor's rules bump, a shipped re-drive over one
  past trigger yields new commands that apply, the original events are
  untouched, and a checkpoint reset over the same trigger still yields
  DUPLICATE.

## CQ: cross-domain correlation query (pass 6, D4)

**CQ-1** [core] **A correlation index in every backend.**
- What: an index on `EventMeta.correlation_id` across all
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
  HTTP route). Client libraries offer a helper over the result: it links
  the events of a saga's rejection facts to the refused command's trigger
  exactly (on the refusal origin in `EventMeta.fact.external_id`;
  decision 14.31) and groups every event by its command (`causation.command_id`); reaction commands' trigger edges
  are not in the result (decision 13.3) and come from traces (PS-6).
- Why: `query.proto`, `CorrelationQuery` in `types.proto`.
- Settled when: a saga chain across three domains comes back in one call,
  and the helper rebuilds the PM edges and the per-command groups.

## EA: edition administration (pass 6, D5)

**EA-1** [core] **The edition registry and its admin RPCs.**
- What: store `Edition` records (name, `diverged_at`, store, created_at;
  no creator: that goes to the security log, CI-6) and serve `EditionAdminService.CreateEdition` and
  `DeleteEdition` with the documented codes. `DeleteEdition` removes the
  record and the edition's events, snapshots and projector output in
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
  fails (scenarios C-0541 to C-0545).

**NC-2** [core] **Mint the nonce.**
- What: the coordinator mints a fresh opaque value per delivery under
  AGGREGATE_HANDLES and COMMUTATIVE (empty window included) and leaves it
  empty under STRICT. Never persisted, never returned.
- Why: as NC-1.
- Settled when: two deliveries of one command carry different nonces.

## CR: COMMUTATIVE in the client libraries (passes 6, 8 and 12)

**CR-1** [clients, router, project] **`protoc-gen-angzarr` and
`angzarr_build::compile`: one generator for every language, held to a
golden suite.**
- What: one generator, shipped as a protoc plugin (`protoc-gen-angzarr`, for
  go, python, java, csharp, cpp and typescript) and as a Rust build helper
  (`angzarr_build::compile`, prost-build with angzarr's settings plus the
  generator). It reads `(state)` and `(conflict)` from the descriptors and
  emits, for each COMMUTATIVE state message, a pure `changed(before, after)`
  returning unit paths exactly as the `conflict_units` region of
  `options.proto` specifies. That covers units per field kind, the wildcard
  for unmarked, `whole_state` and unknown fields, bitwise floats, path
  syntax and escaping, `[#order]`, the non-unique-key fallback, the descend
  depth bound of 32, and the overlap rule with path prefixes. For every
  state message, COMMUTATIVE or not, it also emits the `StateDescriptor`
  (type URL and the full resolved resolution list) for registration (CR-3),
  and for Rust a `State` implementation carrying both.
- **Diagnostics**: the `unmarked-field` warning and the nine errors, with
  the exact texts in `docs/guide/state-and-conflicts.md` section 7.
  Warnings print (`cargo:warning=` in Rust, stderr otherwise), and errors
  fail generation.
- **Golden suite**: a shared fixture parity suite in angzarr-project
  `parity/`. It holds fixture protos (hatpick's `ListState` worked example,
  and one per diagnostic) and before/after state pairs with their expected
  unit sets, run against every language's generated code (and annals').
- **Resolver**: each client library's COMMUTATIVE resolver folds to
  `expected_sequence` and to the head, computes `window = changed(expected,
  head)`, runs decide on the head, computes `mine = changed(head, head +
  events)`, and acknowledges the nonce (NC-1) when they do not overlap,
  otherwise failing `ABORTED`. Delete core's coordinator-side commutative
  diff.
- Why: decisions 6.12, 8.1, 12.7 and 12.8; `ConflictResolution` and
  `StateOptions` in `types.proto`; the `conflict_units` region of
  `options.proto`.
- Settled when: the golden suite passes in every language and in annals
  (identical unit sets and diagnostics for every fixture); disjoint edits
  succeed; overlapping, unmarked-field and `whole_state` edits fail stale;
  and the handler writes no conflict code (resolver scenarios C-0546 to
  C-0550).

**CR-2** [core] **COMMUTATIVE is the default where the state supports it.**
- What: the conflict-resolution config (HD-2) accepts any resolution the
  registered state supports, per command type or component, and as a
  `Handling` override where allowed. The built-in default is HD-4's.
  Configuration naming an unsupported resolution is refused at load or
  registration.
- Why: decision 12.7 (superseding 6.12's opt-in-only).
- Settled when: an unconfigured COMMUTATIVE-capable component resolves
  COMMUTATIVE, and configuring COMMUTATIVE for any other component is
  refused.

**CR-3** [core, clients] **Describe fills `StateDescriptor`.**
- What: each client library fills `ComponentDescriptor.state` from the
  generated descriptor in its `ComponentService.Describe` answer for an
  aggregate or PM (Rust: `registry.register::<D>()` records it). The
  coordinator stores it for its one component from the Describe it pulls and
  uses only its resolution list (HD-2, HD-4, CR-2), never the schema.
- Why: decisions 12.7, 14.10 and 14.19 (review T3: the registration-time refusal
  had no data to act on).
- Settled when: a coordinator refuses a COMMUTATIVE command for a component
  whose registered state lacks it, and defaults correctly for one that has
  it.

## MI: minted ids and always-assigned request ids (pass 8)

**MI-1** [core] **Mint UUIDv7 in core.**
- What: every identifier core mints is a UUIDv7 (RFC 9562), as 16 bytes in
  `UUID` (pass 9: every UUID field is one): today the minted command id
  (CI-3). Replace any v4 or ad-hoc id generation core keeps for
  identifiers (DQ-1 deletes the DLQ's `new_correlation_id` minting
  outright). Client-supplied UUIDs are checked for length only (UU-4),
  never for version.
- Why: decision 8.2; the `minted_ids` region of `types.proto`.
- Settled when: every id core mints is a version-7 UUID, and a client id of
  another version passes through untouched.

**MI-2** [clients] **Mint UUIDv7 in the client libraries.**
- What: wherever an SDK generates an id for its caller (a command helper's
  `command_id`, a new aggregate root), it mints a UUIDv7. These are
  client-supplied ids.
- Why: decision 8.2.
- Settled when: in every language, SDK-generated request ids and roots are
  version-7 UUIDs, and helpers reuse the same command id on retry (CI-7).

**MI-3** [core, clients] **Always-assigned request ids.** Closed by pass
12 and replaced by CI-3: command ids are always assigned, and
`RequestOrigin.minted` is deleted (decision 12.1).

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
  `e9ef0ae2-6fc6-4c14-b713-ef03971dd867`, `external_id`) (PS-3), which is
  also the fact's command id (CI-2). annals does
  the same through `angzarr-proto` (tracked in the session plan).
- Why: decision 9.2; the `derived_ids` region of `types.proto`.
- Settled when: every runtime reproduces the documented values
  (`compute_root("player", "alice@example.com")` =
  `cfe936c0-2912-5ca9-96e6-f37c0b441759`; fact `"pi_1234"` =
  `917f26ae-ea2e-58af-86de-77013a69617e`) from a shared golden list, and
  existing derived roots have a migration (or a wipe, pre-production). The
  same golden list carries the pass-12 command id vectors (CI-2).

**UU-3** [core] **Storage columns become uuid-typed.**
- What: every stored command id and correlation id (event meta, the
  command id index of CI-1, the correlation index of CQ-1, `dlq_entries.
  correlation_id`) becomes a 16-byte UUID column: Postgres `uuid`, MySQL and
  SQLite `BINARY(16)`/`BLOB`, Bigtable row-key bytes. Where a backend can
  only hold text (KurrentDB's `$correlationId` metadata), it writes the
  canonical text and parses it back.
- Why: decision 9.1: the storage saving is the point of the change.
- Settled when: each backend's schema stores them as 16 bytes, and a
  round-trip test reads back the same UUID.

**UU-4** [core] **Validate UUID fields, and the REST routes.**
- What: refuse `INVALID_ARGUMENT` for a set `UUID` that is not 16 bytes in
  `CommandPage.command_id`, `CommandPage.correlation_id`,
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
    `command_id`, `correlation_id`, `causation_id` or fact source,
    `Handling` as received and as resolved, the RPC (mode), the receive
    time, the duration, the rules version, and optionally the payload bytes (configurable,
    since a payload may hold personal data). The outcome is one of: APPLIED
    (with the sequence range), DUPLICATE, PARKED, a rejection (the gRPC code
    and message: a business rejection, a stale sequence, a
    `PERMISSION_DENIED` causation), a malformed refusal (`INVALID_ARGUMENT`, including
    arm/origin mismatches and unknown editions), or a handler bug
    (`INTERNAL`). `HandleAsync` reports the enqueue (ACCEPTED) and, later,
    the processed outcome as a second attempt record with the same
    `command_id`.
  - **Never in the event store.** Attempts are observability, not domain
    history: no stream, no projection, no replay, and no effect on
    deduplication. The caller's identity is the security log's (CI-6), not
    the sink's.
  - **Implementations.** No-op (the default) and in-memory (a bounded
    buffer, readable in tests and development). Durable sinks (a log, an
    audit queue) are left to deployments.
- Why: D3: rejections and attempts leave nothing in any stream.
- Settled when: the user says when; then the interface is in core, both
  implementations are tested, and a rejected command shows up in the
  in-memory sink with its code.

## SG: one saga, one destination (pass 14)

**SG-1** [clients, router] **A saga has exactly one destination domain.**
- What: angzarr-cli's lint fails a SAGA declaring no `output_domain`, and
  a PROCESS_MANAGER declaring any `output_domain` (allocate the error
  codes). `output_domains` is deleted (decision 14.31), so there is no
  several-destinations lint any more; delete angzarr-cli's handling of
  field 6. The client library refuses a saga answer holding a
  command for any domain but its `output_domain`: `SagaService.Handle`
  fails `INTERNAL` with no commands, and the coordinator dead-letters the
  trigger and alerts.
- Why: decision 14.24; `ComponentOptions` (`options.proto`), `SagaResponse`
  (`saga.proto`).
- Settled when: scenarios C-0582, C-0583, C-0604 and C-0605 pass (C-0581
  is retired). C-0604 also needs angzarr-cli to refuse an `(event)` entry
  naming a PM with a `domain`.

## QS: standalone query server (pass 14)

**QS-1** [core] **Run `EventQueryService` standalone.**
- What: a read-only query server serving `EventQueryService` over a
  domain's event store with no component behind it: no command RPCs
  (`UNIMPLEMENTED`), never a snapshot (every page from 0). Its upcasting
  waits on the owner (decision 14.26).
- Why: decision 14.26; `query.proto`.
- Settled when: scenarios C-0588 and C-0589 pass.

## GAP: gaps carried from earlier passes

**GAP-1** [core] **Upcast on every read and publish path.**
- What: today upcasting runs only on aggregate loads, so sagas, PMs,
  projectors and queries see raw stored versions. The owning coordinator
  upcasts its stream's events by calling its own business process's
  `UpcasterService` on every way out: loading for `Handle` (and a PM's
  `process_state`), answering `EventQueryService`, and wherever stored
  events reach a subscriber (live publishing and reads of stored history:
  catch-up, gap fill, rebuild). Consumers get current shapes only and carry no upcasters. Fail on
  an unknown type URL, naming it (as annals' strict replay does). The store
  is never rewritten.
- Why: decisions 14.22, 14.25 and 14.29 (the open question of how readers of
  another component's stream are upcast is settled).
- Settled when: scenarios C-0584 to C-0587 pass, and golden fixtures run in
  CI.

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
  `sync_mode`, and (pass 6) `merge_strategy`, and (pass 12) `provenance`,
  `origin` and `idempotency_claim`. Use `handling`, `outcome`,
  `command_modes`, and (pass 6) `conflict_resolution`, `correlation_query`
  and `edition_admin`, and (pass 9) `uuid` and `derived_ids`, and (pass 12)
  `command_identity`, `security_logs`, `event_meta` and `entry_points`. The
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
- What: deduplication (command ids, the per-stream lookup, the accepted
  costs), the transient reactor outbox, status codes, PARKED, edition sink
  suppression, the DLQ replay audit, and the security-log principle.
- Why: pass 5.
- Settled when: each topic has a page.

**DOC-5** [project] **Rewrite the feature specs.**
- What: retire the specs for removed features (CASCADE 6, ISOLATED 3,
  notifications and compensation 4, speculative 3, `undoes` 2). Add
  coordinator-contract specs for passes 5 and 12: command-id dedup per
  kind (including the zero-event re-decide), the pipeline order, the
  framework-only `causation_id`, PARKED, `projector_failures`, ABORTED
  retries, edition sink suppression, and the replay audit.
- Why: passes 2, 5 and 12.
- Settled when: `just contracts` passes with the new specs.

**DOC-7** [site] **Publish the state-and-conflicts guide.**
- What: move `docs/guide/state-and-conflicts.md` (or a mirror) into the
  site's guide area, and link it from annals' docs, once CR-1's generators
  exist.
- Why: decision 12.8 (the guide describes generators that do not exist
  yet; the site documents shipped behaviour).
- Settled when: the site serves the guide, and its build examples run.

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

Open items only. The closed KS items, SN-3, DQ-3, MI-3, OB-2, PR-2, PR-3 and PR-4 are listed
in place with their disposition but not counted.

| Workstream | Items |
|---|---|
| CI: command identity and dedup on events (pass 12) | 8 |
| OB: transient reactor outbox | 6 |
| PS: provenance stamping and correlation | 6 |
| BO: business output is payloads only | 3 |
| RV: rules_version reporting and snapshot selection | 3 |
| MD: the three RPC modes and the Outcome | 6 |
| ST: status codes | 2 |
| ED: editions, external sinks, CloudEvent id | 4 |
| SN: snapshots | 3 |
| RT: recorded_at and temporal queries | 2 |
| DQ: DLQ replay | 5 |
| RN: renames | 2 |
| PR: process-manager replies, process events and inputs | 4 |
| VC: command versioning (pass 12) | 1 |
| FA: fact pipeline | 3 |
| HD: Handling resolution | 5 |
| WS: wire-shape migration | 5 |
| RM: removed features | 6 |
| TG: type generation and router | 2 |
| OR: arm and fact source | 2 |
| RD: re-driving reactions (pass 13) | 1 |
| CQ: cross-domain correlation query (pass 6) | 2 |
| EA: edition administration (pass 6) | 4 |
| NC: the conflict nonce (pass 6) | 2 |
| CR: COMMUTATIVE and the generator (passes 6, 8 and 12) | 3 |
| MI: minted ids (pass 8) | 2 |
| UU: one UUID type, v5 derived ids (pass 9) | 4 |
| CL: D9 cleanups (pass 6) | 5 |
| AU: attempt-audit sink (pass 6, held) | 1 |
| SG: one saga, one destination (pass 14) | 1 |
| QS: standalone query server (pass 14) | 1 |
| GAP: carried gaps | 3 |
| DOC: site, specs, branches | 7 |
| **Total** | **114** |

Pass 12 closed 15 items (KS-1–12, with KS-9's content moved to CI-8;
SN-3, DQ-3 and MI-3), opened 13 (CI-1–8, RV-3, PR-3, VC-1, CR-3 and
DOC-7), and rewrote others in place (PS-1–3, RV-1–2, DQ-1–2, RN-1, HD-2,
HD-4, OR-1–2, CR-1–2, MI-1–2, UU-2–4, EA-1, AU-1, OB-6): 110 open items
became 108.

Pass 13 closed PR-3 (decided; its implementation is PR-4), opened 3 (PR-4,
PS-6, RD-1), and rewrote CI-1, PS-1, OR-2 and CQ-2 in place: 108 open
items became 110. Review T8 needs no item of its own beyond RD-1.

Pass 14 rewrote RV-1, RV-2, RV-3, SN-3 and VC-1 in place (RV-3 moved from
the client libraries to core) and pointed NC-1 and CR-1 at their
scenarios: 110 open items stay 110. The follow-up rulings added SN-4
(decision 14.12) and PR-5 (decision 14.16, rescoped to core by 14.20): 112.
The later pass-14 rulings added SG-1 (14.24) and QS-1 (14.26) and rewrote
GAP-1 (14.25): 114. Decision 14.31 closed PR-2, opened PR-6 and PR-7, and
rewrote OB-1, OB-2, OB-5, OB-6, PR-1, PR-4, SG-1 and MD-5 in place: 115.
The owner's settlement of 14.31 (2026-10-28, a PM is a domain; refusals
through the saga's on-refused callback) closed OB-2 and PR-4, opened
OB-7 (the on-refused callback), and rewrote PR-1, PR-5, PR-6, PR-7,
PS-1, CI-5, CQ-2 and MD-5 in place: 114.

## By-repo index

An item tagged with several repos appears under each of them.

| Repo | Items |
|---|---|
| core | CI-1–6, CI-8, OB-1, OB-3, OB-5–7, PS-1–6, BO-1, RV-1, RV-3, MD-1–5, ST-1, ED-1–4, SN-1–2, SN-4, RT-1–2, DQ-1–2, DQ-4–6, RN-1–2, PR-1, PR-5–7, FA-1–2, HD-1–5, WS-1–5, RM-1–3, RM-6, TG-1, OR-1–2, RD-1, CQ-1–2, EA-1–3, NC-2, CR-2–3, MI-1, UU-2–4, CL-1–5, AU-1, QS-1, GAP-1–2 |
| router | OB-4, OB-6, PS-2, RN-1, RV-2, SN-4, VC-1, FA-3, HD-3, WS-2, TG-1–2, OR-2, NC-1, CR-1, CL-2, CL-4, SG-1, PR-6–7, OB-7 |
| clients (go, rust, python, java, csharp, cpp, typescript) | CI-2, CI-7, BO-2, RV-2, SN-4, MD-6, ST-2, ED-3, RN-1–2, VC-1, FA-3, HD-5, WS-1–2, RM-4, RM-6, TG-1, OR-2, RD-1, CQ-2, EA-4, NC-1, CR-1, CR-3, MI-2, UU-1–2, CL-1–2, CL-4–5, SG-1, PR-6–7, OB-7 |
| examples | BO-3, WS-2, RM-5 |
| site | RN-2, EA-4, CL-5, DOC-1–4, DOC-7 |
| project (features, CI, branches, parity) | EA-4, CR-1, GAP-3, DOC-5–6 |
