# Critical review record (after pass 4)

Part of the [audit-meta design record](../audit-meta-followups.md).

After pass 4 (8a803c9), a fresh-agent critical review covered the protos,
the design note and the plan. It also read angzarr core, the router, the
clients and the site, the annals `feat/audit` draft, hatpick-events and
fetched external documentation. The yardstick: be consistent with
established frameworks, and diverge only for polyglot ease or to hide CQRS/ES
complexity. The review found **14 WRONG** and **11 DEBATABLE** items, plus
items it judged FINE.

## Provenance of this record

**The review report itself is not on disk.** This record is reconstructed
from two sources:
- the session plan (`angzarr-annals-hatpick.plan.md`, the "Review DONE"
  through "SCOPE (user)" blocks), which names the adopted fixes W4–W14 and
  the corrections;
- a reading of the protos at 8a803c9.

Confidence varies:
- **W4–W14** are named in the plan. Their wording here is reconstructed, but
  their identity and resolution are certain.
- **W1–W3** are not named in the plan. They are inferred from the three
  decisions the plan records between the review and the adopted fixes:
  idempotency, the reactor outbox, and the annals divergence. The numbering
  is a best guess.
- **D1–D11** are not listed in the plan, which says only that they are "still
  to be asked". The items and the reviewer's leans below are inferred from the
  contract's open seams. Re-check them against the original report if it
  surfaces. All of them are **open**.
- **FINE** items are inferred in the same way.

## WRONG (14)

| # | Finding | Status | Resolution |
|---|---|---|---|
| W1 | Request-origin commands were not deduplicated (`types.proto` said so outright), yet `HandleAsync` and DLQ replay deliver at least once, so a redelivered client command could apply twice. *(Inferred.)* | **Adopted** (pass 5) | A key store for every keyed origin: a claim per addressed aggregate, written in the append transaction. `request_id` is required for `HandleAsync` and replay. See [idempotency.md](idempotency.md). |
| W2 | Reaction dedup on (event, component, index) assumed a re-run reactor re-emits the same commands in the same order. Only the PM had an outbox, so a saga re-run after a crash could send different commands under the same keys. *(Inferred.)* | **Adopted** (pass 5) | A transient outbox for all reactors: output stored atomically with the source checkpoint, re-sent verbatim, with no purity contract. |
| W3 | annals, which shares the protos, stages atomic chains across streams in one transaction, while angzarr appends one stream per write. The design record treated annals as an angzarr runtime. *(Inferred.)* | **Decided otherwise** (documented divergence) | annals keeps the atomic in-process chain intentionally; annals is not angzarr. See [annals-divergence.md](annals-divergence.md). |
| W4 | A reaction command's provenance was whatever the reactor set: a reactor could claim another actor. | **Adopted** | The coordinator stamps actor (and correlation) from the trigger, and a differing value is refused. |
| W5 | Correlation could be empty on persisted events, which breaks `Query.correlation_id` and stream subscriptions. | **Adopted** | Correlation is never empty: the caller's value, or one derived from the key. |
| W6 | `process_manager.proto` said a reply's causation "names the PM's own event". In fact causation names the triggering event, and replies reach a PM by correlation. | **Adopted** | Text fixed: replies route by correlation, and causation always names the trigger. |
| W7 | Business output could set meta, sequences and (through `emits` being empty) "custom covers": an escape hatch past the framework's stamping. | **Adopted** | Business output is payloads plus an optional snapshot. Anything else is refused, and the escape-hatch text is removed. |
| W8 | `rules_version` was "opaque" with no owner: nothing declared or stamped it. | **Adopted** | Declared at registration (`ComponentDescriptor.rules_version`) and stamped by the coordinator. annals' load-bearing use is documented as a divergence. |
| W9 | DLQ replay minted a NEW correlation_id. That broke the trace and the idempotency key, and the replay itself was unaudited. Event-book replay had no target. | **Adopted** | A replay keeps provenance, origin and keys. The replay is recorded in the entry (operator, time, mode, outcome), and event-book replay re-delivers to the failed component. |
| W10 | What-if editions could reach external sinks (webhooks, Kafka) with ids that collide with main-timeline events. | **Adopted** | Non-main editions never reach external sinks, and the edition is in the default CloudEvent id and source. |
| W11 | Error semantics were inconsistent: HandleSync had no way to report a projector failure without failing a committed command; a failed fact had no answer; retryable codes differed by path (and core parses `FAILED_PRECONDITION` messages). | **Adopted** | HandleSync is OK with `Outcome.projector_failures`; `DELIVERY_OUTCOME_PARKED`; one retryable set, with a stale sequence moving to `ABORTED`. |
| W12 | Under AGGREGATE_HANDLES, a snapshot past `expected_sequence-1` would fold part of the conflict window into state, hiding it from decide. | **Adopted** | The delivered snapshot is at or below `expected_sequence-1`. |
| W13 | `recorded_at` could go backwards (clock steps), so "pages up to the last page with recorded_at <= T" was not a prefix, and `as_of_time` was ill-defined. | **Adopted** | `recorded_at` is max(previous, now) per stream, and `as_of_time` is a prefix. |
| W14 | Misleading names: `decided_at` holds a sequence, not a time, and the projector coordinator's async RPC was `Handle` while the command coordinator's is `HandleAsync`. | **Adopted** | Renamed to `base_sequence` and `HandleAsync`. |

### Corrections (facts in the design record)

The review also corrected three factual claims (see
[decision-log.md#corrections](decision-log.md#corrections)):
- facts-as-commands is not Event Modeling's translation pattern (Equinox
  ingesters are the analogue);
- KurrentDB has `MultiStreamAppend` (25.1 and later);
- Axon has no decision/notification command distinction.

All three are **adopted**: the record is corrected, and the site fix is
backlog DOC-3.

## DEBATABLE (11): all open, to be put to the user

The leans are the reviewer's as best reconstructed. Where the plan is silent,
the lean is inferred and marked so.

| # | Question | Reviewer's lean | Status |
|---|---|---|---|
| D1 | Should facts enter through the command coordinator (one input path, a Fact arm) or through a separate ingest endpoint, as Equinox ingesters do? | Keep one path. The arm already separates the pipelines. Cite Equinox as the analogue. *(Inferred.)* | Open |
| D2 | No minted event id: identity is `EventRef` (stream, sequence). KurrentDB, Marten and CloudEvents all carry an event id. | Keep `EventRef`, and derive an id where an external format needs one, as the CloudEvent default id does. *(Inferred.)* | Open |
| D3 | One command per `CommandBook`, with no batching. | Keep. Batching belongs in client libraries. *(Inferred.)* | Open |
| D4 | `HandleAsync` returns `Empty`, with no handle to follow (compare the AIP-151 long-running operations). | Return the command's key, or its correlation, so a caller can follow the outcome. *(Inferred.)* | Open |
| D5 | HandleSync waits for synchronous projectors. Other systems give read-your-writes through position tokens (the Marten async daemon, KurrentDB checkpoints). | Keep it as a convenience, and steer users towards position-based waits. *(Inferred.)* | Open |
| D6 | Editions as wire identity, with in-memory editions on multiple coordinator instances (affinity). | Keep the identity, and decide the affinity rule. *(Inferred; see the open questions.)* | Open |
| D7 | Keeping only the newest snapshot by default makes `as_of_time` queries replay from 0. | Fine as the default. Revisit with the snapshot-policy config shape. *(Inferred.)* | Open |
| D8 | A hard rejection of a saga's or PM's command is only dead-lettered; the PM never learns of it. | Let a PM learn of it through a framework-recorded event on its own stream. *(Inferred; already an open question.)* | Open |
| D9 | `Handling.merge` lets a caller override the configured conflict strategy. | Configuration-only would be simpler. If an override stays, configuration must allow it per type. *(Inferred.)* | Open |
| D10 | The type URL prefix is `/` rather than `type.googleapis.com/`. | Keep: readers accept any prefix. *(Inferred.)* | Open |
| D11 | An event's causation names the triggering *event*, skipping the command in between (KurrentDB's convention is causation = the id of the message that caused it). | Fine: the command's key is in the origin, so the chain is recoverable. *(Inferred.)* | Open |

## FINE

These are judged consistent with established practice. The list is
inferred, since the original report's FINE list is not on disk.

- `Cover` as pure stream identity, with editions part of that identity.
- `uint64` sequences everywhere.
- The type URL as the schema version, through versioned packages.
- `Handling` and `Outcome` never persisted.
- The `Command`/`Fact` body arm, under which a fact cannot carry a causation
  origin.
- Infallible fact handlers with a dead-letter backstop.
- The removal of CASCADE, compensation channels and speculative RPCs.
- STRICT and AGGREGATE_HANDLES only, with conflict helpers in client
  libraries.
- `PayloadReference` as a transport concern only.
- One coordinator RPC per mode, with violations refused loudly.
- `""` as the only name of the main timeline.
