# Audit-meta proto passes: design record (index)

## Status

Open. The `feat/audit-meta` passes (1–14) changed **only** the protos under
`proto/io/angzarr/`, the `rust/angzarr-proto` crate and the documentation
(the design record here, and from pass 12 a developer guide under
`docs/guide/`). No angzarr code has changed. The user is not taking on heavy angzarr refactoring now, so every
code consequence is recorded in the backlog, which is the part that must not
be lost.

Wire breaks are accepted pre-freeze. Reservation policy (D6, pass 6):
removed fields and messages are deleted outright, with no `reserved`
statements, up to and including pass 13. From the first stored production
event onwards, every removal reserves its number and name (see
`proto/buf.yaml` and backlog GAP-3).

## Documents

| Document | Contents |
|---|---|
| [audit-meta/decision-log.md](audit-meta/decision-log.md) | Every decision of passes 1–14: why, the accepted cost, and the standard it aligns with, with superseded entries marked. Also the corrections (Event Modeling, KurrentDB, Axon). |
| [audit-meta/critical-review-source.md](audit-meta/critical-review-source.md) | The post-pass-4 critical review's own record (authoritative for the findings' content). |
| [audit-meta/critical-review.md](audit-meta/critical-review.md) | The status of each review finding: W1–W14, D1–D11, FINE and annals fitness, with where each was resolved; and the illuminated review's findings decided in passes 12 and 13 (T3–T8, T13, CH1, SG3, PM2). |
| [audit-meta/idempotency.md](audit-meta/idempotency.md) | The idempotency research (a comparison table) and the chosen design since pass 12: one `command_id` per command, deduplicated on the events, with its accepted costs; PM process events deduplicated on their trigger, and reactor re-runs (pass 13); the superseded key-store design in brief. |
| [audit-meta/backlog.md](audit-meta/backlog.md) | **The code follow-up backlog**, by workstream with a by-repo index. 110 open items, each with what, why, and what settles it; items closed by passes 12 and 13 are kept in place with their disposition. |
| [audit-meta/annals-divergence.md](audit-meta/annals-divergence.md) | Why annals keeps its atomic in-process chain, and what it does and does not need as a result (no claims, no outbox, a logging "DLQ"). Also where annals matches angzarr: the proto types themselves, `EventMeta`, command ids and dedup on events, the pipeline order, conflict units with COMMUTATIVE the default in both. |
| [../guide/state-and-conflicts.md](../guide/state-and-conflicts.md) | **Developer guide** (pass 12): custom options, the `(state)` option, marking conflict units, how COMMUTATIVE resolves and its risks, the generator's warnings and errors, the build setup, registration, versioning commands, and (pass 13) re-running reactors. |

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
- **Pass 8** (682af21): decisions 8.1–8.3, by the user.
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
    client ids stay opaque (superseded for request and correlation ids by
    pass 9).
  - **Request ids are always assigned**: `RequestOrigin.minted` (field 3)
    marks a coordinator-minted id, recorded for audit and never
    deduplicating; only client-supplied ids are keys. An absent correlation
    is the request id verbatim (a fact's: its `external_id`, superseded by
    pass 9); nothing mints a correlation.
  - **annals** generates `changed()` from the same markers (same golden
    suite), and now fingerprints request keys like angzarr: neither is a
    divergence.
- **Pass 9** (e733dd2): decisions 9.1–9.3, by the user.
  - **One UUID type**: `RequestOrigin.request_id`, `Provenance`,
    `Query`, `CorrelationQuery`, `EventStreamFilter`, `StoredDeadLetter`
    and `ReplayDeadLetterOk` `correlation_id` change from `string` to the
    16-byte `UUID` (types.proto `uuid` region), for storage cost. Client
    request and correlation ids must be UUIDs (any version); a set one that
    is not 16 bytes is `INVALID_ARGUMENT`. `FactOrigin.external_id`,
    actors and the CloudEvent `id` stay strings. Protobuf JSON shows base64:
    accepted.
  - **v5 derived ids** (`derived_ids` region): `compute_root(domain, key)` =
    UUIDv5(`d4741b1a-52cd-43cf-add1-3dbb9615510b`, `"{domain}:{key}"`); a
    fact's absent correlation = UUIDv5(`e9ef0ae2-6fc6-4c14-b713-ef03971dd867`,
    `external_id`). Caller-chosen roots are any 16 bytes, derived roots v5,
    minted roots v7.
  - **Text is a boundary concern**: canonical lowercase hyphenated text only
    at display and input, through per-language helpers. Rust:
    `angzarr_proto::ids` (`Display`, `FromStr`, byte and `uuid::Uuid`
    conversions, `compute_root`, `fact_correlation`). Others: backlog UU-1.

- **Pass 10** (7956dc8; 10.4 in pass 11, fd61f93): decisions 10.1–10.4,
  by the user.
  - **`RequestOrigin.index` deleted**: a request id is per command, and
    the request claim key is the request id alone (per addressed
    aggregate). Batch callers mint one id per command and group them by
    correlation. `Causation.index` stays.
  - **Fact mismatch**: the same `external_id` with a different payload is
    refused `FAILED_PRECONDITION` by default, configurable per command type
    or component to DUPLICATE plus an alert and a metric (configuration,
    not wire; backlog KS-10, KS-11).
  - **Causation mismatch** (10.4): always refused, dead-lettered with an
    alert, never DUPLICATE and not configurable; a mismatch can only be a
    framework bug or a corrupted outbox (backlog KS-12). Documentation only.
  - **v5 fingerprint**: UUIDv5(`ANGZARR_FINGERPRINT_NAMESPACE`
    `a749bd8c-7bf0-47e6-a5c9-dc54ebde74aa`, 4-byte big-endian type URL
    length ++ type URL ++ value bytes); `IdempotencyClaim.fingerprint` is a
    `UUID`. Misuse detection, not tamper protection, and not the deferred
    hash chain. Rust: `angzarr_proto::ids::fingerprint`.
  - *Superseded by pass 12:* the claims, the fingerprint and both mismatch
    rules are deleted (decision 12.2).
- **Pass 12** (eec6676): decisions 12.1–12.12, by the user, from the
  illuminated review of fd61f93.
  - **One `command_id` per command** (`CommandPage` 8): client-supplied or
    a minted v7; derived v5 for reaction commands (netstrings of the trigger
    `EventRef`, component and index, under the new
    `ANGZARR_COMMAND_NAMESPACE` `e2c9f744-9fe1-4b4b-bfee-ae514dde293b`) and
    for facts (`external_id`, the fact-correlation namespace).
    `causation_id` (an `EventRef`) is plain metadata; `fact_origin` keeps
    the fact source. `Origin`, `RequestOrigin` (with `minted`) and
    `Causation` are deleted.
  - **Dedup on the events**, by an index on (stream, `command_id`); a
    duplicate is answered from those events. `IdempotencyClaim`, the
    fingerprint, retention, the DLQ age refusal and the fact-mismatch rule
    are deleted. Accepted costs: zero-event decisions re-decided, reused
    ids undetected, dedup forever.
  - **Normative pipeline order**: validate, assign ids, dedup, resolve
    Handling, business code.
  - **`EventMeta` = `{command_id 13, causation_id 15, fact 16,
    correlation_id 14, recorded_at 5, rules_version 7}`**; `Provenance`,
    the actor and `base_sequence` are deleted. **No actor anywhere**
    (`Edition.created_by` and `DeadLetterReplay.operator` too): who-did-it
    goes to security logs.
  - **`rules_version` per response**: `CommandHandlerService.Handle`
    returns `CommandHandlerResponse { events, rules_version,
    snapshot_refused }`; snapshot validity is checked in the client library.
    `ComponentDescriptor.rules_version` is deleted.
  - **State options**: `(state)` = `StateOptions { repeated
    ConflictResolution conflict_resolutions }` (50106, replacing the bool);
    `ComponentDescriptor.state` = `StateDescriptor { type_url, options }`;
    `ConflictUnit.whole_state`. **COMMUTATIVE is the default** where the
    state declares conflict units, otherwise STRICT. The generator's
    diagnostics are specified.
  - **Entry points**: `causation_id` and trigger books only from
    framework-authenticated callers (mTLS); clients get `PERMISSION_DENIED`.
  - **Commands can be upcast**, discouraged (a migration aid with a planned
    removal).
  - The crate: `bytes::Bytes`, `Eq`/`Hash` on key types,
    `ids::reaction_command_id` and `ids::fact_command_id` in place of
    `ids::fingerprint`.
- **Pass 13** (5850057): decisions 13.1–13.6, by the user, closing
  PM2/PR-3 and T8.
  - **`EventMeta.causation`** = `oneof { UUID command_id = 17; EventRef
    triggering_event = 18; }`, the event's direct cause. Fields 13
    (`command_id`) and 15 (`causation_id`) deleted, unreserved.
  - **PM process events**: `causation.triggering_event`, the trigger's
    correlation, deduplicated on `triggering_event` within the PM's stream.
  - **No command-causation on events**: a reaction command's trigger stays
    on `CommandPage.causation_id` (transport and trace metadata) and goes
    to OpenTelemetry traces. Forward causation from `CorrelationQuery` is
    exact for process events, by correlation for reaction commands' events.
  - **Reactor re-runs: no switch.** Reaction ids never include the rules
    version, so re-runs dedupe; checkpoint resets are for recovery; repairs
    are new commands; standard re-drive commands are backlog RD-1.
  - **No reacting-component field**: source control says what makes what.
- **Pass 14** (this change): decisions 14.1–14.2, by the owner.
  - **`rules_version` is the build version**, reported per response and at
    registration (`ComponentDescriptor.rules_version` 4), stamped in full.
  - **The coordinator selects snapshots**: registered state type, then the
    domain's compatibility rule (major.minor; exact for non-semver; RE2
    accept/reject patterns, reject wins). `snapshot_refused` removed and
    reserved on both responses.
  - **Unknown type after upcasting**: the message names the sent type URL,
    the details the chain's final one; facts are upcast too.

### Worked example: hatpick's `ListState`

```proto
message ListState {
  option (io.angzarr.v1.state) = {
    conflict_resolutions: [CONFLICT_RESOLUTION_COMMUTATIVE]
  };
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
Since pass 12 COMMUTATIVE is this state's default; the
[developer guide](../guide/state-and-conflicts.md) works through where such
markers can go wrong.

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
- **Request-origin idempotency** (pass 5): a key store; replaced in pass 12
  by one `command_id` per command, deduplicated on the events. See
  [idempotency.md](audit-meta/idempotency.md).
- **Reactor nondeterminism** (pass 5): a transient outbox for all reactors,
  with no purity contract.
- **The parked-fact answer** (pass 5): a `DeliveryOutcome` value, not an
  `Outcome` field.
- **Where `rules_version` comes from** (pass 5, revised in passes 12 and
  14): it is the business binary's full build version, reported with every
  response (`CommandHandlerResponse.rules_version`) and at registration
  (`ComponentDescriptor.rules_version`), and stamped in full.
- **Who decides snapshot validity** (pass 12, revised in pass 14): the
  coordinator, against the registered state type and the domain's
  version-compatibility rule (major.minor by default; configurable accept
  and reject patterns). `snapshot_refused` is removed (decision 14.1).
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
- **Client-supplied versus minted ids** (pass 8; superseded in pass 12):
  `RequestOrigin.minted` is deleted with `RequestOrigin`; minted command ids
  deduplicate like any other.
- **Correlation when absent** (pass 8, revised in passes 9 and 12): the
  command id verbatim (client or minted); for a fact, its derived command
  id, UUIDv5(`ANGZARR_FACT_CORRELATION_NAMESPACE`, `external_id`); never
  minted.
- **How UUIDs travel** (pass 9): one 16-byte `UUID` message for every UUID,
  request and correlation ids included; text only at display and input
  boundaries; base64 in protobuf JSON accepted.
- **One namespace or two for derived ids** (pass 9): two, so a fact's
  correlation can never equal a derived root; pass 10 added a third, for the
  fingerprint, which pass 12 replaced with the reaction command-id
  namespace.
- **The request index** (pass 10): deleted; one request id per command,
  batches grouped by correlation.
- **Fingerprints** (pass 10; superseded in pass 12): deleted with the
  claims. A reused id with a different payload goes undetected (an accepted
  cost, decision 12.2).
- **Who did it** (pass 12): not data. No actor in events, editions or dead
  letters; every coordinator writes the authenticated caller to a security
  log (decision 12.3).
- **Command ids and dedup** (pass 12): one `command_id` per command,
  deduplicated on the events by (stream, `command_id`), forever (decisions
  12.1, 12.2).
- **The default conflict resolution** (pass 12): COMMUTATIVE where the
  state declares conflict units, otherwise STRICT, learnt from
  `ComponentDescriptor.state` (decision 12.7).
- **Who may send causation** (pass 12): only callers authenticated as
  framework components; clients get `PERMISSION_DENIED` (decision 12.10).
- **Command upcasting** (pass 12): supported and discouraged (decision
  12.11).
- **Meta for a PM's own process events** (pass 13, PM2): causation is the
  trigger (`EventMeta.causation.triggering_event`), with the trigger's
  correlation; deduplicated on it within the PM's stream (decision 13.2).
- **Causation on events** (pass 13): only the direct cause; a reaction
  command's trigger goes to traces, not events (decision 13.3).
- **Reactor re-runs** (pass 13, T8): no switch; same ids always dedupe;
  repairs are new commands (decision 13.4).
- **A reacting-component field** (pass 13): none; source control says what
  makes what (decision 13.5).

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
- **Repeated parks of one fact.** One DLQ entry per command id, or one per
  attempt (backlog CI-8).
- **Shipped re-drive commands** (backlog RD-1): their command types, where
  they live (the angzarr protos or a shipped domain), and the operator
  entry point.
