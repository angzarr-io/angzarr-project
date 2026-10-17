# Audit-meta proto passes: design record (index)

## Status

Open. The five `feat/audit-meta` passes changed **only** the protos under
`proto/io/angzarr/` and the `rust/angzarr-proto` crate. No angzarr code has
changed. The user is not taking on heavy angzarr refactoring now, so every
code consequence is recorded in the backlog, which is the part that must not
be lost.

Wire breaks are accepted pre-freeze: removed fields and messages are deleted
outright, with no `reserved` statements.

## Documents

| Document | Contents |
|---|---|
| [audit-meta/decision-log.md](audit-meta/decision-log.md) | Every decision of passes 1–5: why, the accepted cost, and the standard it aligns with. Also the corrections (Event Modeling, KurrentDB, Axon). |
| [audit-meta/critical-review.md](audit-meta/critical-review.md) | The post-pass-4 critical review: W1–W14, D1–D11 and the FINE items, each with its status. |
| [audit-meta/idempotency.md](audit-meta/idempotency.md) | The idempotency research (a comparison table) and the chosen key-store design, with its alignments and divergences. |
| [audit-meta/backlog.md](audit-meta/backlog.md) | **The code follow-up backlog**, by workstream with a by-repo index. 81 items, each with what, why, and what settles it. |
| [audit-meta/annals-divergence.md](audit-meta/annals-divergence.md) | Why annals keeps its atomic in-process chain, and what it does and does not need as a result. |

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
- **Pass 5** (this change): the critical review's fixes. Each item below is
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

## Resolved questions

- **Merge strategy placement** (pass 3): configuration sets the default per
  command type and per component. `CommandBook.handling.merge` overrides it
  where configuration allows. Whether the override should exist at all is
  debatable item D9.
- **Sync mode placement** (pass 4): not handling. It is the caller's choice
  of coordinator RPC.
- **`EventRequest.sync_mode`** (pass 4): deleted with `EventRequest`.
- **Refuse or ignore** (pass 4): refuse loudly. `INVALID_ARGUMENT` for
  clients; dead-letter for reaction commands.
- **`merge` on a reaction command** (pass 4): forbidden. Reaction commands
  carry no `Handling`.
- **`expected_sequence` on a Fact** (pass 4): refused `INVALID_ARGUMENT`.
- **Codegen marker for facts** (after pass 2): no proto flag. The handler
  registration (`#[handles_fact]` / ingest) is the declaration, and the router
  guards the arm against the handler kind.
- **Request-origin idempotency** (pass 5): a key store. See
  [idempotency.md](audit-meta/idempotency.md).
- **Reactor nondeterminism** (pass 5): a transient outbox for all reactors,
  with no purity contract.
- **The parked-fact answer** (pass 5): a `DeliveryOutcome` value, not an
  `Outcome` field.
- **Where `rules_version` is declared** (pass 5): `ComponentDescriptor`.
- **Where the DLQ replay audit lives** (pass 5): `StoredDeadLetter.replays`.
  The published `AngzarrDeadLetter` stays immutable.

## Open questions

- **D1–D11**, the debatable review items, are still to be put to the user.
  See [critical-review.md](audit-meta/critical-review.md).
- **Edition lifetime per backend.** Memory lasts as long as the process, redis
  as long as its TTL, and a database persists. Open:
  - whether a TTL or GC policy is configured per edition;
  - what happens to an edition whose backend evicts it mid-use;
  - whether `DeleteEditionEvents` must also clear the edition's projections
    and snapshots.
- **Multi-instance affinity for in-memory editions.** An in-memory edition
  lives in one process. Options:
  - affinity: routing on the edition name;
  - a shared backend: falling back to redis;
  - a rule that in-memory editions are single-instance only.
  (Related to D6.)
- **Hard rejections of saga and PM commands.** They are dead-lettered. Open:
  whether a PM should also learn of them, through a framework-recorded event
  on its own stream. This is D8.
- **Fingerprint mismatch on causation and fact keys.** Answer DUPLICATE and
  alert, or refuse and dead-letter (backlog KS-10).
- **Reactions on backends without atomic claims.** Refuse to host them, or
  run them with a loud warning (backlog KS-8).
- **Repeated parks of one fact.** One DLQ entry per key, or one per attempt
  (backlog KS-9).
