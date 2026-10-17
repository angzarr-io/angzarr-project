# Audit-meta proto passes: design record (index)

## Status

Open. The eight `feat/audit-meta` passes changed **only** the protos under
`proto/io/angzarr/` and the `rust/angzarr-proto` crate. No angzarr code has
changed. The user is not taking on heavy angzarr refactoring now, so every
code consequence is recorded in the backlog, which is the part that must not
be lost.

Wire breaks are accepted pre-freeze. Reservation policy (D6, pass 6):
removed fields and messages are deleted outright, with no `reserved`
statements, up to and including pass 8. From the first stored production
event onwards, every removal reserves its number and name (see
`proto/buf.yaml` and backlog GAP-3).

## Documents

| Document | Contents |
|---|---|
| [audit-meta/decision-log.md](audit-meta/decision-log.md) | Every decision of passes 1–8: why, the accepted cost, and the standard it aligns with. Also the corrections (Event Modeling, KurrentDB, Axon). |
| [audit-meta/critical-review-source.md](audit-meta/critical-review-source.md) | The post-pass-4 critical review's own record (authoritative for the findings' content). |
| [audit-meta/critical-review.md](audit-meta/critical-review.md) | The status of each review finding: W1–W14, D1–D11, FINE and annals fitness, with where each was resolved. |
| [audit-meta/idempotency.md](audit-meta/idempotency.md) | The idempotency research (a comparison table) and the chosen key-store design, with its alignments and divergences. |
| [audit-meta/backlog.md](audit-meta/backlog.md) | **The code follow-up backlog**, by workstream with a by-repo index. 104 items, each with what, why, and what settles it. |
| [audit-meta/annals-divergence.md](audit-meta/annals-divergence.md) | Why annals keeps its atomic in-process chain, and what it does and does not need as a result. Also where annals now matches angzarr: conflict units, fingerprints, minted ids. |

## Passes

- **Pass 1** (9cfed59, 17bc1cd): provenance meta, uint64 sequences, one
  command per book, the origin oneof, facts as commands, no reservations.
- **Pass 2** (46404df): CASCADE/ISOLATED, compensation and notification,
  speculative execution, snapshot retention and `undoes`/`compensates`
  removed. `PayloadReference` made transport-only. The DRY refactor (`Cover`,
  `EventRef`, `Provenance`). The `Command`/`Fact` body oneof.
- **Pass 3** (9ded171): `Handling { optional expected_sequence; merge }` on
  `CommandBook`, resolved in place and never persisted. The request wrappers
  deleted. `CommandResponse { events, Outcome outcome }`.
- **Pass 4** (8a803c9): sync is a call-level choice, one coordinator RPC per
  mode: `Handle` (DECISION), `HandleAsync` (ASYNC), `HandleSync` (SIMPLE).
  `SyncMode` and `EventRequest` deleted.
- **Pass 5** (b5a4da8): the critical review's fixes. Each item below is
  recorded in the decision log.
  - The idempotency claim model, and `IdempotencyClaim`.
  - The transient reactor outbox.
  - Reaction provenance stamping, and correlation that is never empty.
  - Business output as payloads only.
  - `ComponentDescriptor.rules_version`.
  - Edition sink suppression, and the edition in the CloudEvent id.
  - `Outcome.projector_failures`, `DELIVERY_OUTCOME_PARKED`, and one
    retryable status set (stale sequence is now `ABORTED`).
  - The AGGREGATE_HANDLES snapshot bound.
  - A monotonic `recorded_at`, and `as_of_time` as a prefix.
  - Renames: `decided_at` to `base_sequence`, and projector `Handle` to
    `HandleAsync`.
  - PM replies routed by correlation.
  - DLQ replay keeps keys and is audited (`StoredDeadLetter.replays`).
- **Pass 6** (650d774): the review's debatable items D1–D11, as decided
  by the user, plus the restoration of COMMUTATIVE. Each is in the decision
  log (6.1–6.12).
  - One `Origin` message on the page, in `EventMeta` and as the claim key;
    `Command.origin` and `Fact.source` deleted; arm/origin validation.
  - `EventQueryService.GetCorrelatedEvents(CorrelationQuery)`, across
    domains, with forward causation derived from the result.
  - `EditionAdminService { CreateEdition, DeleteEdition }` in `meta.proto`;
    never-created editions refused; `DeleteEditionEvents` retired.
  - The reservation policy in `proto/buf.yaml`.
  - `ContextualCommand.conflict_nonce` (AGGREGATE_HANDLES safety).
  - `Snapshot.rules_version`, and discard-and-replay on a mismatch.
  - `AggregateRoot`, `Synchronize` and `AngzarrDeadLetter.cover` deleted;
    `ComponentKind` in `types.proto` and used by the descriptor and the dead
    letters; `Projection.next_sequence`.
  - `MergeStrategy` renamed `ConflictResolution`, `Handling.merge` renamed
    `conflict_resolution`, and `CONFLICT_RESOLUTION_COMMUTATIVE` restored as
    an opt-in client-library resolver.
  - The review record reconciled against its source.
- **Pass 7** (279bc89): the main timeline is the **unset** edition, not
  `""` (decision 7.1, by the user). `Cover.edition` and
  `CorrelationQuery.edition` are `optional string`; a set empty edition is
  refused `INVALID_ARGUMENT`; the edition admin names are required and
  non-empty; the main CloudEvent id has no edition segment.
- **Pass 8** (this change): decisions 8.1–8.3, by the user.
  - **Conflict units for COMMUTATIVE** (`options.proto`, `conflict_units`
    region): `(commutative_state)` on the state message (50106),
    `(conflict)` = `ConflictUnit { descend, element_key, ordered }` on its
    fields (50107). A generated `changed(before, after)` returns unit paths;
    unmarked fields conflict with everything; floats compare bitwise;
    `descend` recurses to depth 32. The resolver: `window =
    changed(state@expected, state@head)`, decide on head (invariants
    hold), `mine = changed(head, head + events)`, disjoint acknowledges the
    nonce, otherwise `ABORTED`. COMMUTATIVE on a state without
    `commutative_state` is malformed. Replaces 6.12's "reflection diff".
  - **Minted ids are UUIDv7** (the `minted_ids` region of `types.proto`);
    client ids stay opaque.
  - **Request ids are always assigned**: `RequestOrigin.minted` (field 3)
    marks a coordinator-minted id, recorded for audit and never
    deduplicating; only client-supplied ids are keys. An absent correlation
    is the request id verbatim (a fact's: its `external_id`); nothing mints
    a correlation.
  - **annals** generates `changed()` from the same markers (same golden
    suite), and now fingerprints request keys like angzarr: neither is a
    divergence.

### Worked example: hatpick's `ListState`

```proto
message ListState {
  option (io.angzarr.v1.commutative_state) = true;
  map<string, Item> items = 1 [(io.angzarr.v1.conflict) = {}];  // items[<id>]
  repeated Column columns = 2 [(io.angzarr.v1.conflict) = {}];  // columns
  Settings settings = 3 [(io.angzarr.v1.conflict) = {}];        // settings
}
```

This reproduces hatpick's "touched" rule. Stale edits to different items
commute (`items[a]` against `items[b]`); two edits to one item conflict; a
column change conflicts only with another column change; a settings change
only with another settings change. Finer variants are one marker away:
`{descend: true}` on `items` gives per-field units (`items[a].weight`), and
`{element_key: "id", ordered: true}` on `columns` gives per-column units plus
`columns[#order]`. The fixture `rust/angzarr-proto/tests/fixtures/list_state.proto`
carries both and the crate's tests read the markers back from descriptors.

## Resolved questions

- **Conflict-resolution placement** (pass 3): configuration sets the
  default per command type and per component.
  `CommandBook.handling.conflict_resolution` overrides it where
  configuration allows. (Whether the resolution belongs in the message or
  only in configuration is queued by the user for later; see the open
  questions.)
- **Sync mode placement** (pass 4): not handling. It is the caller's choice
  of coordinator RPC.
- **`EventRequest.sync_mode`** (pass 4): deleted with `EventRequest`.
- **Refuse or ignore** (pass 4): refuse loudly. `INVALID_ARGUMENT` for
  clients; dead-letter for reaction commands.
- **`conflict_resolution` on a reaction command** (pass 4): forbidden. Reaction commands
  carry no `Handling`.
- **`expected_sequence` on a Fact** (pass 4): refused `INVALID_ARGUMENT`.
- **Codegen marker for facts** (after pass 2): no proto flag. The handler
  registration (`#[handles_fact]` / ingest) is the declaration, and the router
  guards the arm against the handler kind. Pass 6 (D11) states this in the
  proto too (`CommandPage`).
- **Request-origin idempotency** (pass 5): a key store. See
  [idempotency.md](audit-meta/idempotency.md).
- **Reactor nondeterminism** (pass 5): a transient outbox for all reactors,
  with no purity contract.
- **The parked-fact answer** (pass 5): a `DeliveryOutcome` value, not an
  `Outcome` field.
- **Where `rules_version` is declared** (pass 5): `ComponentDescriptor`.
- **Where the DLQ replay audit lives** (pass 5): `StoredDeadLetter.replays`.
  The published `AngzarrDeadLetter` stays immutable.
- **The review's D1–D11** (pass 6): all decided. See
  [critical-review.md](audit-meta/critical-review.md) and decisions 6.1–6.11.
- **What `DeleteEdition` clears** (pass 6): the edition's record and its
  events, snapshots, projector output and claims, in every domain.
- **Unknown editions** (pass 6): refused `NOT_FOUND`; only created editions
  get storage.
- **The main timeline's name** (pass 7): it has none. Main is the unset
  edition; a set `""` is malformed (`INVALID_ARGUMENT`).
- **COMMUTATIVE field granularity** (pass 8): declared conflict units,
  defined once in `options.proto` and generated for every language by one
  protoc plugin with a shared golden suite (backlog CR-1).
- **Client-supplied versus minted request ids** (pass 8): a bool,
  `RequestOrigin.minted`, rather than a second id field (decision 8.3).
- **Correlation when absent** (pass 8): the request id verbatim, or a
  fact's `external_id` verbatim; never minted, never hashed.

## Open questions

- **Conflict resolution in the message or only in configuration.** Queued
  by the user for later.
- **Edition lifetime per backend.** Memory lasts as long as the process, redis
  as long as its TTL, and a database persists. Open:
  - whether a TTL or GC policy is configured per edition;
  - what happens to an edition whose backend evicts it mid-use (its record
    survives in the registry while its events are gone).
- **The exact default divergence point** (backlog EA-3): a create-time stamp
  can tie with a concurrent main append, and clocks differ across
  instances.
- **Per-event saga causation** (W3a, backlog OB-6).
- **The SIMPLE mode name** (W14): not renamed, with no decision recorded.
- **Multi-instance affinity for in-memory editions.** An in-memory edition
  lives in one process. Options:
  - affinity: routing on the edition name;
  - a shared backend: falling back to redis;
  - a rule that in-memory editions are single-instance only.
- **Hard rejections of saga and PM commands.** They are dead-lettered. Open:
  whether a PM should also learn of them, through a framework-recorded event
  on its own stream (backlog PR-2). With the attempt-audit sink (D3) an
  operator can at least see them, once it exists.
- **Fingerprint mismatch on causation and fact keys.** Answer DUPLICATE and
  alert, or refuse and dead-letter (backlog KS-10).
- **Reactions on backends without atomic claims.** Refuse to host them, or
  run them with a loud warning (backlog KS-8).
- **Repeated parks of one fact.** One DLQ entry per key, or one per attempt
  (backlog KS-9).
