# annals divergence statement

Part of the [audit-meta design record](../audit-meta-followups.md).

## Statement

**annals is not angzarr.** They share the `io.angzarr.v1` protos, some code
and their intents. annals is still a separate runtime with its own
guarantees, and it does not have to match angzarr's runtime behaviour.

**annals operates on the proto types directly** (user, pass 12). Its kernel
depends on `rust/angzarr-proto` and handles `Cover`, `EventRef`,
`EventPage`, `EventMeta`, `CommandBook` and the rest as they are generated.
There is no parallel `StreamKey`, `EventId`, `Book` or `Meta` type, and the
annals-angzarr adapter largely folds into the kernel. All checking happens in
one parse step, which yields a checked wrapper with non-optional accessors,
so nothing downstream unwraps an `Option`. That parse step is domain-blind,
as angzarr's coordinators are. For this, `angzarr-proto` maps `bytes` to
`bytes::Bytes` and derives `Eq` and `Hash` on its key types.

annals keeps an **atomic in-process chain**: a command, its events, and the
reactions they trigger are staged across streams and committed in one
Postgres transaction. This divergence is **intentional**. It makes in-process
Rust work easy: one process, one transaction, with no bus, no outbox and no
retry loop. hatpick's server embeds annals and calls it directly, in
process, with no HTTP layer into annals. angzarr appends one stream per
write and runs reactions asynchronously (decision 2.1), so the same domain
behaves differently under the two runtimes. This is accepted.

## What follows from the divergence

- **No claims, no fingerprints, no `record_command`** (pass 12). annals
  deduplicates exactly as angzarr does: by `command_id` on its events, with
  an index on (stream, `command_id`), and the same accepted costs
  (zero-event decisions re-decided, a reused id undetected, dedup forever).
  In-process and atomic, it has no redelivery of its own. The two
  at-least-once edges are covered by ids:
  - **Webhook facts**: the fact's derived `command_id` (UUIDv5 of
    `external_id`) is found on the stream when the source redelivers.
  - **HTTP retries**: a client-supplied `command_id`, reused on retry.
- **No transient outbox.** Reactions commit in the same transaction as their
  trigger, so there is nothing to re-send. Their command ids are still the
  derived ones, so the audit record is identical.
- **Causation is never accepted from outside.** No caller outside the
  process can deliver a reaction. annals' own in-process chain stamps
  `causation_id` on the reaction command (it is not persisted on events,
  pass 13) and the derived `command_id`. angzarr needs mTLS-identified
  framework components for the same guarantee (decision 12.10).
- **The "DLQ" is a logger.** annals has no dead-letter store or replay.
  Whatever angzarr would dead-letter (a failing fact ingest, a reactor bug, a
  malformed reaction command), annals writes to its log. Every such entry is
  prefixed with a warning that anything arriving there almost certainly
  indicates a problem.
- **`rules_version` means different things.** In angzarr it is the
  business binary's full build version (e.g. `"1.4.2+build.7"`), baked in at
  build time, reported with every response and at registration
  (`ComponentDescriptor.rules_version`), and stamped in full. angzarr reads
  it for one thing besides explaining a decision: its coordinator offers a
  snapshot only when the snapshot's version passes the domain's
  compatibility rule (major.minor by default; decision 14.1). annals takes
  the value from the domain's declaration, the author's short label (e.g.
  `"v3"`), and its runtime relies on it in its own way, in annals'
  `docs/design/audit.md`. The proto comment on `EventMeta.rules_version`
  points here. Both runtimes still take it from the business logic and
  stamp it unaltered. Whether annals adopts the build version is annals'
  decision; until it does, an annals label under angzarr's default rule is
  not a semantic version, so it selects snapshots by exact equality.
- **No root-request pointer in angzarr (D2, pass 6).** angzarr records only
  correlation and the direct cause (the producing command, or a PM process
  event's trigger) on a reaction's events. Correlation is enough to find the
  workflow (`GetCorrelatedEvents`); since pass 13 the trigger edge of a
  reaction command is in traces, not on events (decision 13.3). If annals
  wants the originating command on every event, that is its own divergence,
  decided in its own design. On the wire, `EventMeta` has no slot for it.

## Where annals follows angzarr

- **`EventMeta` is the same** (pass 13, revised by 14.31): `causation`
  (`command_id`, its one arm; a PM takes facts only, so
  `triggering_event` is deleted), `fact`, `correlation_id`,
  `recorded_at` and `rules_version`. There is no actor (who-did-it goes to
  security logs in both), no origin, no base sequence, and no copy of a
  reaction command's `causation_id`.
- **Reactor re-runs** (pass 13): the same derivation, with no
  `rules_version` in it, so a re-run dedupes in annals too, and repairs are
  new commands (decision 13.4).
- **The same pipeline order**: validate, assign ids, load the stream then
  the dedup lookup, resolve and check Handling, business code. annals'
  in-process coordinator struct loads the snapshot and newer events (or
  events up to the command's expected sequence) before it looks the
  command up. Under STRICT, a command whose expected
  sequence is not the head is rejected as stale.
- **Conflict resolution: all three strategies, and COMMUTATIVE is the
  default in both runtimes** where the state declares conflict units,
  otherwise STRICT (decision 12.7). annals reads each state's resolutions
  from its registry (the same `StateDescriptor`), looked up by
  `cover.domain`. AGGREGATE_HANDLES and COMMUTATIVE get the window since the
  expected sequence (with a snapshot at or below expected−1), as in angzarr.
- **COMMUTATIVE uses the same conflict units.** annals' `changed()` is
  generated from the same `(state)` and `(conflict)` markers (`options.proto`,
  `conflict_units` region) and must pass the same golden fixture suite as
  the client libraries (backlog CR-1), so a state message resolves
  identically under both runtimes. The COMMUTATIVE risk (dependent values
  split across units) applies equally; see
  [the developer guide](../../guide/state-and-conflicts.md).
- **The same command ids**: a client-supplied id or a minted UUIDv7; reaction
  ids from `angzarr_proto::ids::reaction_command_id`; fact ids from
  `angzarr_proto::ids::fact_command_id`. Correlation, when absent, is the
  command id (a fact's derived one included).
- Stream identity is (domain, edition, root), and main is the unset edition
  (pass 7). A set edition is never empty.
- Sequences are u64, and `EventPage.sequence` is always definite.
- **One UUID type (pass 9).** Command, correlation and root ids are the
  wire's 16-byte `UUID`, never strings. Text appears only at display and
  input, through `angzarr_proto::ids`. `external_id` stays a string.
- **Derived roots** are `angzarr_proto::ids::compute_root(domain, key)`.
- Facts use an infallible `ingest`, which gets a read-only context (the
  recorded time, the correlation, the fact source and the rules version). A
  Fact with any Handling field is malformed. Strict replay: an unknown event
  type URL fails, naming it.
- **Commands may be upcast**, with the same discouragement (decision 12.11).
  An unknown command type with no upcaster path is refused, naming the type
  URL.
- Business output is payloads, and the runtime stamps meta.

The plan's annals items are tracked in the session plan, not here.
"Materially similar" to angzarr means the same wire meaning, not the same
execution model.
