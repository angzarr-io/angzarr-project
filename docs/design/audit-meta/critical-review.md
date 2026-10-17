# Critical review record (after pass 4)

Part of the [audit-meta design record](../audit-meta-followups.md).

After pass 4 (8a803c9), an independent critical review covered the protos,
the design note and the plan. It also read angzarr core, the router,
client-rust, the annals `feat/audit` draft and hatpick, and fetched external
documentation. The yardstick: be consistent with established frameworks, and
diverge only for polyglot ease or to hide CQRS/ES complexity. The review
found **14 WRONG** and **11 DEBATABLE** items, plus items it judged FINE.

## Provenance of this record

The review's own record is
[critical-review-source.md](critical-review-source.md). It was condensed from
the reviewer's report by the coordinating session, with the findings,
evidence pointers and recommendations unchanged. **Where this file and the
source disagree on content, the source is authoritative.** This file only
tracks each finding's status and where it was resolved.

An earlier version of this file was reconstructed from the session plan
before the source was on disk. Pass 6 replaced that reconstruction with the
source's findings. Two things changed as a result:
- W1–W3 are now the source's items. The reconstruction had guessed them,
  and its W3 (annals' atomic chain) is the source's "annals fitness" item 1.
- D1–D11 are now the source's items. The reconstruction's questions (a
  separate fact endpoint, minted event ids, batching, and so on) were
  inferred and are dropped.

## WRONG (14)

| # | Finding (from the source) | Status | Resolution |
|---|---|---|---|
| W1 | Request-origin commands are not deduplicated, yet `HandleAsync` and DLQ replay run on an at-least-once bus, so one client command can be decided twice. | **Adopted** (pass 5) | Dedup on `(request_id, index)` in every mode (on `request_id` alone since pass 10, decision 10.1). `request_id` is required for `HandleAsync` and replay. A retried sync `Handle` gets DUPLICATE and the original events. Decisions 5.1 and 5.5; [idempotency.md](idempotency.md). |
| W2 | Dedup is inferred from event rows, so a decision that emits zero events leaves no claim, and a redelivery re-runs against changed state. | **Adopted** (pass 5) | An inbox contract: a claim per key recording the applied outcome (an empty range included), written in the append transaction, with retention. Decisions 5.1 and 5.4; `IdempotencyClaim` (5.19). |
| W3 | Reaction dedup assumes deterministic, per-event reactors: (a) causation is stamped with the book's max sequence, which is imprecise and changes the key if catch-up re-chunks; (b) index-keyed dedup drops or misattributes commands if output changes between runs; (c) the proto never said who stamps `Causation.event`. | **Adopted** (pass 5), except (a) | (b): a transient outbox for all reactors (decision 5.6). (c): `Causation.event` is always the triggering event; the coordinator stamps `component` and `index`. (a) is still open: per-event delivery or a per-command trigger, backlog OB-6. |
| W4 | Provenance on reaction commands is unassigned: an emitter can forge or omit the actor. | **Adopted** (pass 5) | The coordinator stamps actor and correlation from the trigger, and refuses differing values. Decision 5.7. |
| W5 | `correlation_id` is "optional", but PMs depend on it to route. | **Adopted** (pass 5) | Correlation is never empty: the caller's, or derived from the key. Decision 5.7. |
| W6 | The PM reply contract contradicts `Causation` and core: the proto says a reply's causation names "the PM's own event". | **Adopted** (pass 5) | Replies route by correlation, and causation always names the trigger. Decision 5.17. |
| W7 | Business code can write provenance on the return path (meta, sequence, the "custom covers" escape hatch). | **Adopted** (pass 5) | Business output is payloads plus an optional snapshot. Anything else is refused. Decision 5.8. |
| W8 | `rules_version` has no source, and annals makes it load-bearing. | **Adopted** (pass 5) | Declared at registration (`ComponentDescriptor.rules_version`) and stamped by the coordinator. annals' use is a documented divergence. Decision 5.9. |
| W9 | DLQ replay rewrites correlation, and its lineage cannot be expressed; the operator is recorded nowhere; event-book replay is unspecified. | **Adopted** (pass 5) | A replay keeps correlation, origin and keys, and is recorded in the entry. Decision 5.18. |
| W10 | What-if editions can leak external side effects, and CloudEvent ids collide (the default id omits the edition). | **Adopted** (pass 5) | Non-main editions never reach external sinks, and the edition is in the default id and source. Decision 5.10. |
| W11 | HandleSync and fact-failure responses are undefined, inviting duplicate retries; STRICT's `FAILED_PRECONDITION` is "retryable" for a caller but futile for async redelivery. | **Adopted** (pass 5) | HandleSync answers OK with per-projector failures; a failed fact is "accepted, parked"; one retryable status set, with a stale sequence moving to `ABORTED`. Decisions 5.11–5.13. |
| W12 | Under AGGREGATE_HANDLES a snapshot can hide the conflict window. | **Adopted** (pass 5) | The delivered snapshot is at or below `expected_sequence-1`. Decision 5.14. (Pass 6 applies the same rule to COMMUTATIVE.) |
| W13 | `as_of_time` is internally inconsistent: a prefix in one place, a filter in another. | **Adopted** (pass 5) | `recorded_at` is non-decreasing per stream, and as-of is a prefix. Decision 5.15. |
| W14 | Misleading names: `decided_at` is a sequence; `Handle` means opposite things on the command and projector coordinators; "SIMPLE" names the heaviest mode. | **Adopted** (pass 5), except "SIMPLE" | `decided_at` became `base_sequence`, and the projector's `Handle` became `HandleAsync` (decision 5.16). The mode name SIMPLE has not been renamed, and no decision on it is recorded. Modes are RPCs now (`HandleSync`), so the name appears only in documentation (see the index's open questions). |

## DEBATABLE (11): all decided by the user before pass 6

| # | Question (from the source) | Reviewer's lean | Decision | Where |
|---|---|---|---|---|
| D1 | The origin union is stated three times (`Command.origin`, `Fact.source`, `EventMeta.origin`), splitting provenance across page and arm. | One `Origin` message, reused, with "a Fact requires the fact origin" as validation. | **Adopted.** One `Origin { request \| causation \| fact }` on `CommandPage` and `EventMeta`, and as the claim key. Validation, refused loudly. | Pass 6, decision 6.1 |
| D2 | A reaction's events lose `request_id`; the originating request is reachable only by walking causation. annals keeps request on every event. | Keep it on events, or annals drops it. | **No change**: correlation is enough, so no root-request pointer. annals' request-on-every-event is a divergence, or annals drops it. | Pass 6, decision 6.2; [annals-divergence.md](annals-divergence.md) |
| D3 | There is no record of what was attempted: command payloads are not persisted, and a rejection leaves nothing. | Decide whether audit-of-attempts is in scope. | **Optional observability sink**: an interface composable into command-handler coordinators, with in-memory and no-op implementations only. Never in the event store. Core code, held until the user says when. | Pass 6, decision 6.3; backlog AU-1 |
| D4 | Correlation queries stop at one domain, but subscriptions do not; there is no forward "what did this event cause" query. | A cross-domain correlation query (KurrentDB's `$by_correlation_id`). | **Adopted.** `EventQueryService.GetCorrelatedEvents(CorrelationQuery)`; forward causation is derived from the result. Indexes per backend are backlog. | Pass 6, decision 6.4; backlog CQ-1–2 |
| D5 | A misspelt edition silently gets storage, and an unconfigured edition's divergence point is undefined. | Refuse loudly. | **Adopted.** Editions need an explicit, administrative `CreateEdition` (never a domain event), which records the divergence point (default: main's head) and may name a store. A never-created name is refused. `DeleteEdition` refuses `""` (pass 7: main is the unset edition, so an empty name is simply missing). | Pass 6, decision 6.5; pass 7, decision 7.1; backlog EA-1–4 |
| D6 | Removed fields are not reserved, and hatpick will store `EventPage` bytes as written. | Reserve; it costs nothing. | **Reserve from now on**: from the first stored production event. This round's deletions stay unreserved. Supersedes decision 1.10. | Pass 6, decision 6.6; `proto/buf.yaml` |
| D7 | AGGREGATE_HANDLES has no safety default: a decide that ignores the window is accepted silently (Axon fails it). | A safety default. | **Adopted, as a nonce.** `ContextualCommand.conflict_nonce`; the client library demands `resolve_conflicts(...)` with it, or fails the command as stale. Enforced locally. | Pass 6, decision 6.7; backlog NC-1 |
| D8 | Snapshot state has no version or invalidation rule. | An invalidation rule. | **Adopted.** A snapshot records its state type (the `Any` type URL) and `rules_version`; a mismatch on load discards it and replays. | Pass 6, decision 6.8; backlog SN-3 |
| D9 | Messages with no flow: `DeleteEditionEvents` has no RPC; `Synchronize` is unspecified; `AggregateRoot` duplicates `Cover` without the edition; `component_type` strings though `ComponentKind` exists; `AngzarrDeadLetter.cover` repeats the payload's cover; `Projection.sequence` holds next_sequence. | Clean them up. | **All adopted.** | Pass 6, decision 6.9; backlog CL-1–5 |
| D10 | Vocabulary: `Cover` is a stream id elsewhere; `MergeStrategy` is Axon's "conflict resolution"; Book and Page were kept by decision. | Renaming eases porting, at a cost. | **Rename `MergeStrategy` to `ConflictResolution`**. Keep Cover, Book and Page. | Pass 6, decision 6.10 |
| D11 | The fact codegen marker has two answers (resolved, no proto flag; or open). | Reconcile. | **Resolved**: handler registration (`#[handles_fact]` / ingest) is the declaration, and the router guards arm against handler kind. There is no proto flag. The docs now agree. | Pass 6, decision 6.11 |

## FINE

From the source:
- `Cover` as identity only, with correlation per page (Marten keeps
  correlation and causation per event; Eventuous uses meta tags).
- An optional `expected_sequence`, otherwise stamped (Axon
  `@TargetAggregateVersion`, Wolverine `Version`).
- AGGREGATE_HANDLES as Axon's `ConflictResolver` (justified).
- `Handling` and `Outcome` never persisted.
- The `Fact` arm (goal 2: one input path, infallible ingest).
- `EventRef` identity with no minted event id (justified: replay-stable and
  deterministic; it needed W10's edition fix).
- `recorded_at` as server time, with business time in the payload (Marten's
  `Timestamp` is the append time).
- Core always overriding a reaction's edition. The source asks for this to be
  stated as an override in the proto (Cover.edition: "Reactions stay in the
  edition of the event they react to").
- `PayloadReference` as transport-only (the EIP claim check).
- Removing CASCADE, compensation and speculation, for angzarr itself.

## annals fitness

The source's seven items, with their status. annals' own items are tracked
in the session plan, not here.

1. **The atomic chain is CASCADE by another name.** Decided: annals keeps it
   as a documented divergence ([annals-divergence.md](annals-divergence.md),
   decision 5.20).
2. **`CommandResponse.events` is one book, but a chain yields a set**, and
   `command_handler.proto` is not compiled by the leaf crate. Open, with the
   annals work.
3. **Metadata mismatches.** Request on every event: D2, a divergence or
   dropped. Correlation: always set since pass 5. `recorded_at`: stamped at
   persist since pass 5. `rules_version`: load-bearing in annals, a
   divergence.
4. **Dedup.** Since pass 5 angzarr deduplicates request commands too (W1).
5. **AGGREGATE_HANDLES.** annals checks strictly, while hatpick wants the
   overlap-only window. Pass 6's COMMUTATIVE is the framework's overlap-only
   resolver.
6. **annals-angzarr is stale against the protos.** Open, with the annals
   rework.
7. **hatpick's `Inject { source_seq }`, gap check and erasure doc.** Open,
   with the hatpick rework.

## Comparisons, corrections and "solved elsewhere"

The source's "Solved elsewhere" list and its confirmed and corrected
comparisons are in [critical-review-source.md](critical-review-source.md).
The three corrections (Axon's decision/notification commands, KurrentDB's
`MultiStreamAppend`, and Event Modeling's translation) are **adopted**; see
[decision-log.md#corrections](decision-log.md#corrections). The site fix is
backlog DOC-3.
