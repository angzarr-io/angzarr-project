# angzarr-embedded divergence statement

Part of the [audit-meta design record](../audit-meta-followups.md).

## Statement

**angzarr-embedded is not core's coordinator.** They share the `io.angzarr.v1` protos, some code
and their intents. angzarr-embedded is still a separate runtime with its own
guarantees, and it does not have to match angzarr's runtime behaviour.

**angzarr-embedded operates on the proto types directly** (user, pass 12). Its kernel
depends on `rust/angzarr-proto` and handles `Cover`, `EventRef`,
`EventPage`, `EventMeta`, `CommandBook` and the rest as they are generated.
There is no parallel `StreamKey`, `EventId`, `Book` or `Meta` type, and the
angzarr-embedded adapter largely folds into the kernel. All checking happens in
one parse step, which yields a checked wrapper with non-optional accessors,
so nothing downstream unwraps an `Option`. That parse step is domain-blind,
as angzarr's coordinators are. For this, `angzarr-proto` maps `bytes` to
`bytes::Bytes` and derives `Eq` and `Hash` on its key types.

angzarr-embedded keeps an **atomic in-process chain**: a command, its events, and the
reactions they trigger are staged across streams and committed in one
Postgres transaction. This divergence is **intentional**. It makes in-process
Rust work easy: one process, one transaction, with no bus, no outbox and no
retry loop. hatpick's server embeds angzarr-embedded and calls it directly, in
process, with no HTTP layer into angzarr-embedded. angzarr appends one stream per
write and runs reactions asynchronously (decision 2.1), so the same domain
behaves differently under the two runtimes. This is accepted.

As built, angzarr-embedded's chain is not one
transaction: a command commits on its own stream and each policy step after
it is its own atomic write to one stream, run before the call returns and
resumed by position. Where it parts from the coordinator contract, and why,
is recorded once, below.

## What follows from the divergence

- **No claims, no fingerprints, no `record_command`** (pass 12). angzarr-embedded
  deduplicates exactly as angzarr does: by `command_id` on its events, with
  an index on (stream, `command_id`), and the same accepted costs
  (zero-event decisions re-decided, a reused id undetected, dedup forever).
  In-process and atomic, it has no redelivery of its own. The two
  at-least-once edges are covered by ids:
  - **Webhook facts**: the fact's derived `command_id` (UUIDv5 of
    `external_id`) is found on the stream when the source redelivers.
  - **HTTP retries**: a client-supplied `command_id`, reused on retry.
- **The runtime's divergences are recorded once**, as the tags on the
  coordinator-contract scenarios angzarr-embedded's conformance runner does
  not run: angzarr-embedded's
  `crates/angzarr-embedded-conformance/src/tags.test.rs`, each
  `divergence_*` tag with its reason (the in-process chain, no outbox, no
  causation from outside, the waiting caller, editions). That file is the
  list; this one does not repeat it.
- **No root-request pointer in angzarr (D2, pass 6).** angzarr records only
  correlation and the direct cause (the producing command, or a PM process
  event's trigger) on a reaction's events. Correlation is enough to find the
  workflow (`GetCorrelatedEvents`); since pass 13 the trigger edge of a
  reaction command is in traces, not on events (decision 13.3). If angzarr-embedded
  wants the originating command on every event, that is its own divergence,
  decided in its own design. On the wire, `EventMeta` has no slot for it.

## Where angzarr-embedded follows angzarr

- **`rules_version` is the same** (decision 14.104, DRAFT, which closes
  its divergence). In both runtimes it is the business binary's
  full build version (e.g. `"1.4.2+build.7"`), baked in at build time,
  reported with every response and at registration
  (`ComponentDescriptor.rules_version`), and stamped in full. Both accept
  a version that is not SemVer at registration, and both offer a snapshot
  under the same rule (types.proto, Snapshot): strip one leading `v` or
  `V`, then equal major.minor when both parse as SemVer 2.0.0, otherwise
  exact equality of the versions as recorded. The proto comment on
  `EventMeta.rules_version` no longer notes a divergence.
- **`EventMeta` is the same** (pass 13, revised by 14.31): `causation`
  (a oneof, decision 14.102, DRAFT: `command` with its `command_id`, or
  `fact` with its `command_id` and origin; a PM is a domain with no
  triggers, so `triggering_event` is deleted), `correlation_id`,
  `recorded_at` and `rules_version`. There is no actor (who-did-it goes to
  security logs in both), no origin beyond a fact's, no base sequence, and no copy of a
  reaction command's `causation_id`.
- **Reactor re-runs** (pass 13): the same derivation, with no
  `rules_version` in it, so a re-run dedupes in angzarr-embedded too, and repairs are
  new commands (decision 13.4).
- **The same pipeline order**: validate, assign ids, load the stream then
  the dedup lookup, resolve and check Handling, business code. angzarr-embedded's
  in-process coordinator struct loads the snapshot and newer events (or
  events up to the command's expected sequence) before it looks the
  command up. Under STRICT, a command whose expected
  sequence is not the head is rejected as stale.
- **Conflict resolution: all three strategies, and COMMUTATIVE is the
  default in both runtimes** where the state declares conflict units,
  otherwise STRICT (decision 12.7). angzarr-embedded reads each state's resolutions
  from its registry (the same `StateDescriptor`), looked up by
  `cover.domain`. AGGREGATE_HANDLES and COMMUTATIVE get the window since the
  expected sequence (with a snapshot at or below expected−1), as in angzarr.
- **COMMUTATIVE uses the same conflict units.** angzarr-embedded's `changed()` is
  generated from the same `(state)` and `(conflict)` markers (`options.proto`,
  `conflict_units` region) and must pass the same golden fixture suite as
  the client libraries (backlog CR-1), so a state message resolves
  identically under both runtimes. The COMMUTATIVE risk (dependent values
  split across units) applies equally; see
  [the developer guide](../../guide/state-and-conflicts.md).
- **The same command ids**: a client-supplied id or a minted UUIDv7; reaction
  ids from `angzarr_proto::ids::policy_command_id`; fact ids from
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
  The kernel upcasts them, through the domain's upcaster sidecar or a Rust
  upcaster registered with it, never the router (decision 14.39). An
  unknown command type with no upcaster path is refused, naming the type
  URL.
- Business output is payloads, and the runtime stamps meta.

The plan's angzarr-embedded items are tracked in the session plan, not here.
"Materially similar" to angzarr means the same wire meaning, not the same
execution model.
