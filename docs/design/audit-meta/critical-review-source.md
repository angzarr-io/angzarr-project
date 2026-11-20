# Critical review: source record

Status: source record of the independent critical review of `feat/audit-meta` at 8a803c9
(2026-10-16). It is condensed from the reviewer's report by the coordinating session; the findings,
evidence pointers and recommendations are unchanged. `critical-review.md` tracks each finding's
status; where the two disagree on content, this file is authoritative.

Repos reviewed: core rem-integration 381a2de5, angzarr-router fb3c0ac, client-rust 4372dc5,
annals feat/audit eb7dbd3, hatpick (randomish). [V] = read/fetched, [I] = inferred.

Overall: the layering (identity / business data / provenance / handling) is mostly clean and standard.
The weak points are idempotency, provenance stamping on reaction output, edition side effects, and the
annals atomic chain being CASCADE by another name.

## WRONG

- **W1 Request-origin commands are not deduplicated,** yet HandleAsync and DLQ replay run on an
  at-least-once bus, so one client command can be decided twice; RequestOrigin.request_id/index drive nothing.
  Standards: EIP Idempotent Receiver; NServiceBus outbox (dedup on incoming message id); KurrentDB event
  ids + expected revision. Classification: re-solving a solved problem. Direction: dedup on
  (request_id, index) in every mode; request_id mandatory for HandleAsync; a retried sync Handle gets
  DUPLICATE + the original events.
- **W2 Dedup is inferred from event rows** (core `source_*` columns, migrations 0012/0016;
  `check_deferred_idempotency` in orchestration/aggregate/traits.rs), so a decision emitting zero events
  leaves no claim and a redelivery re-runs against changed state. "DUPLICATE carries the first
  delivery's events" is unanswerable for an empty first delivery. Standard: NServiceBus outbox stores
  a dedup record per message regardless of output, with retention. Direction: an inbox contract, where each
  processed key maps to its outcome (even empty), written in the same transaction, with a retention window.
- **W3 Reaction dedup assumes deterministic, per-event reactors.** (a) SagaService.Handle gets a whole
  EventBook and core stamps causation with the book's max sequence (`source_max_sequence`,
  orchestration/saga/mod.rs), which is imprecise for audit and changes the key if catch-up re-chunks.
  (b) The index-keyed dedup drops or misattributes commands if output changes between runs (the PM docs
  encourage "saga + destination queries"). (c) The proto never said who stamps Causation.event.
  Standard: NServiceBus persists the first attempt's outgoing messages. Direction: per-event delivery or
  coordinator-stamped Causation.event per command; deterministic reactors OR an outbox for sagas.
- **W4 Provenance on reaction commands is unassigned:** nobody sets actor/correlation on saga/PM commands,
  so an emitter can forge or omit the actor. Core fills only correlation (`fill_correlation_id`); annals
  inherits both. Standard: NServiceBus copies ConversationId and sets RelatedTo; MassTransit propagates
  ConversationId/InitiatorId. Direction: the coordinator stamps Provenance from the trigger; differing
  values are refused.
- **W5 correlation_id is "optional" but PMs depend on it** (core derives the PM root from correlation;
  a trigger without one can't route). Direction: always set it (the caller's value, or derived).
- **W6 The PM reply contract contradicts Causation and core:** the proto says a reply's causation names
  "the PM's own event", yet PM commands' causation is the trigger and core routes replies by correlation.
  The design note repeated the wrong claim. Direction: pick one rule and fix both texts.
- **W7 Business code can write provenance on the return path:** CommandHandlerService.Handle returns
  an EventBook whose pages carry meta and sequence; options.proto advertised a raw-EventBook "escape hatch
  for … custom covers". Standards: Axon upcasters can't change identifiers or timestamps; Wolverine wraps
  returned plain objects itself. Direction: business output is payloads (+ an optional snapshot); refuse
  set meta/sequence/foreign cover.
- **W8 rules_version has no source** (not in config, ComponentDescriptor, or the handler response; only
  W7's forbidden path). annals makes it load-bearing (Rulebook). Direction: declare it once at
  registration; the coordinator stamps it; state whether it is explanatory or load-bearing.
- **W9 DLQ replay rewrites correlation, and its lineage can't be expressed:** a "NEW correlation_id"
  plus metadata that CommandBook has no field for; the operator is recorded nowhere; event-book replay is
  unspecified. Direction: keep the original correlation and origin (so dedup works); record the replay as
  handling-time audit.
- **W10 What-if editions can leak external side effects and CloudEvent ids collide:** projector output
  "follows edition storage" but CloudEvents sinks are HTTP/Kafka, not storage; the default id
  `{domain}:{root_id}:{sequence}` with source `angzarr/{domain}` omits the edition. CloudEvents: source+id
  MUST be unique. Direction: suppress or redirect external sinks off main; include the edition in id/source.
- **W11 HandleSync and fact-failure responses are undefined,** inviting duplicate retries (e.g. Stripe
  webhooks). STRICT's FAILED_PRECONDITION is "retryable" for a caller but futile for async redelivery.
  Direction: HandleSync OK + per-projector failure in Outcome; a failed fact answered "accepted, parked";
  one retryable status set.
- **W12 Under AGGREGATE_HANDLES a snapshot can hide the conflict window** (core works around it with
  `load_window_base`). Standard: Axon's ConflictResolver gets exactly the conflicting events. Direction:
  the delivered snapshot is at or below expected_sequence - 1.
- **W13 as_of_time is internally inconsistent** (a prefix in the region doc, a filter in the field doc;
  they differ with non-monotonic clocks). Direction: recorded_at non-decreasing per stream; as-of = prefix.
- **W14 Misleading names:** `decided_at` is a uint64 sequence (AIP-142 uses `_time` for times);
  `Handle` means opposite things on the command coordinator (sync) and projector coordinator
  (fire-and-forget); "SIMPLE" names the heaviest mode.

## DEBATABLE

- **D1 The origin union is stated three times** (Command.origin, Fact.source, EventMeta.origin): it splits
  provenance across page and arm and needs mapping code in every language. Lean: one Origin message
  reused, with "a Fact requires the fact origin" as validation.
- **D2 A reaction's events lose request_id;** the originating request is reachable only by walking
  causation (which can cross deleted editions). annals keeps request on every event; MassTransit
  InitiatorId / NServiceBus ConversationId keep a root pointer. Decide: keep it on events, or annals drops it.
- **D3 There is no record of what was attempted:** command payloads aren't persisted and a rejection
  leaves nothing. NServiceBus has an audit queue. Decide whether audit-of-attempts is in scope.
- **D4 Correlation queries stop at one domain but subscriptions don't;** no forward "what did this event
  cause" query. KurrentDB has a global `$by_correlation_id` projection. stream.proto had a stale field path.
- **D5 A misspelt edition silently gets storage:** unknown editions fall back to the default edition
  store (possibly production), contradicting "refuse loudly"; an unconfigured edition's divergence
  point is undefined.
- **D6 Removed fields are not reserved.** hatpick will store EventPage bytes as written, so reusing a field
  number later would misdecode stored rows. Reserving costs nothing.
- **D7 AGGREGATE_HANDLES has no safety default:** Axon fails the command when conflicting events exist and
  the handler never checks them; angzarr accepts a decide that ignores the window silently.
- **D8 Snapshot state has no version or invalidation rule** for state-schema or rules changes.
- **D9 Messages with no flow:** ComponentDescriptor/Target had zero users; DeleteEditionEvents has no RPC or
  handler (only a storage method); PayloadReference has no bus envelope on the wire; Synchronize is
  unspecified; AggregateRoot duplicates Cover without the edition; component_type /
  source_component_type are strings though ComponentKind exists; AngzarrDeadLetter.cover repeats
  rejected_command.cover; Projection.sequence holds next_sequence (client-rust routers.rs).
- **D10 Vocabulary:** Cover is Kurrent/Marten's "stream id"; MergeStrategy is Axon's "conflict
  resolution"; Book and Page were kept by decision. Renaming eases porting at a cost.
- **D11 The fact codegen marker has two answers** (plan: resolved, no proto flag; note: open). Reconcile.

## FINE

Cover is identity only, with correlation per page (Marten keeps correlation/causation per event;
Eventuous meta tags). An optional expected_sequence, else stamped (Axon @TargetAggregateVersion, Wolverine
Version). AGGREGATE_HANDLES = Axon ConflictResolver (justified). Handling/Outcome never persisted.
The Fact arm (goal 2: one input path, infallible ingest). EventRef identity with no minted event id
(justified: replay-stable, deterministic; needs W10's edition fix). recorded_at = server time, business
time in the payload (Marten's Timestamp is the append time). Core always overrides a reaction's
edition (state it as an override in the proto). PayloadReference as transport-only (EIP claim check).
Removing CASCADE, compensation and speculation is fine for angzarr itself.

## annals fitness

1. The atomic chain is CASCADE (synchronous reactions, a reaction rejection fails the origin), whereas the
   protos say no mode waits for reactions. Either declare an in-process unit-of-work profile or accept
   divergent error semantics. KurrentDB MultiStreamAppend (25.1+) and Marten/Wolverine multi-stream saves
   make a multi-stream unit of work standard.
2. CommandResponse.events is a single EventBook, but a chain yields a set; CommandResponse lives in
   command_handler.proto, which the angzarr-proto leaf crate doesn't compile.
3. Metadata mismatches: request on every event vs exclusive origin; correlation always set vs optional;
   recorded_at sampled per command vs server-stamped at persist; rules_version load-bearing vs explanatory.
4. Dedup: annals dedups request commands via CommandId; angzarr didn't.
5. AGGREGATE_HANDLES: annals checks strictly; hatpick wants the overlap-only window.
6. Stale against current protos: annals-angzarr pins 9cfed59 and uses Cover.correlation_id, CommandMeta,
   PageHeader; MAIN edition "angzarr" vs ""; Translation still present though reactions may not emit Facts.
7. hatpick: `Inject { source_seq }` duplicates Causation.event.sequence and the base sequence; the gap check
   needs ordered delivery (classify a gap as retryable); the Stamp doc's "actor None after deletion"
   contradicts pseudonymous erasure.

## Solved elsewhere

Inbox dedup recording empty outcomes with retention (NServiceBus outbox); stable reaction output across
retries (NServiceBus/Wolverine outbox); client retry idempotency (KurrentDB event id + expected revision);
correlation/causation propagation (NServiceBus, MassTransit, Marten via OTel); conflict window (Axon
ConflictResolver); multi-stream atomicity (KurrentDB MultiStreamAppend, Marten/Wolverine); correlation
index (KurrentDB `$by_correlation_id`); command audit (NServiceBus audit queue).

## Comparisons confirmed or corrected

- Axon "decision vs notification commands" (commands-vs-facts.md): **corrected; remove.** Axon's docs
  classify commands only by creation policy; no such terms exist. That page's "fact sequence indicator"
  is superseded, and process-manager.mdx still documents PM-emitted facts (the poker example needs a redesign).
- Axon upcasters can split 1→N / drop / use an intermediate representation: confirmed.
- Axon unit of work = one message's handling: confirmed ("several aggregates" unverified).
- Marten multi-stream transactions: confirmed (via Wolverine).
- Marten upcasting is 1:1: implied by the docs; splitting is not addressed.
- KurrentDB has no multi-stream transactions: **corrected** (MultiStreamAppend 25.1, AppendRecords 26.1).
- Facts-as-commands "matches Event Modeling translation": **corrected** (translation brings in events or
  views; Equinox Ingesters are the analogue).
- "Matches the Wolverine/NServiceBus inbox": confirmed only for NServiceBus message-id dedup.
- An optional expected version matches Axon and Wolverine: confirmed (Eventuous unverified).
- CloudEvents has no standard correlation extension (distributed tracing uses traceparent);
  angzarr's `correlationid` is custom.

Reviewer deferrals: Eventuous docs 404'd; Wolverine inbox page and KurrentDB `$correlationId` key not
fetched; the non-Rust/Go clients and the router not inspected in depth; the site only partially read.
