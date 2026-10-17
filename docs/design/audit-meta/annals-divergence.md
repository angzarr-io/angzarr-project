# annals divergence statement

Part of the [audit-meta design record](../audit-meta-followups.md).

## Statement

**annals is not angzarr.** They share the `io.angzarr.v1` protos (through the
`rust/angzarr-proto` crate), some code, and their intents. annals is still a
separate runtime with its own guarantees, and it does not have to match
angzarr's runtime behaviour.

annals keeps an **atomic in-process chain**: a command, its events, and the
reactions they trigger are staged across streams and committed in one
Postgres transaction. This divergence is **intentional**. It makes in-process
Rust work easy: one process, one transaction, with no bus, no outbox and no
retry loop. hatpick's server embeds annals, and that is the use it serves.
angzarr appends one stream per write and runs reactions asynchronously
(decision 2.1), so the same domain behaves differently under the two
runtimes. This is accepted.

## What follows from the divergence

- **No idempotency key store.** annals is in-process and atomic, with no
  at-least-once bus, so redelivery cannot happen inside it. The residual
  risks:
  - **Webhook facts.** An external source may redeliver. A unique index on
    (stream, `external_id`) rejects the duplicate at the append.
  - **HTTP retries.** A client retrying a request is the one at-least-once
    edge. An **optional `record_command` port** records request keys for
    servers that want retry safety.
- **No transient outbox.** Reactions commit in the same transaction as their
  trigger, so there is nothing to re-send.
- **`rules_version` is load-bearing.** In angzarr it is opaque, used only to
  explain a historical decision. annals treats it as load-bearing: its
  runtime relies on the value, not only reports it. How it does so is
  annals' own design, in annals' `docs/design/audit.md`. The proto comment on
  `EventMeta.rules_version` points here.
- **Provenance is stamped the same way.** annals stamps `EventMeta` (actor,
  correlation, origin, `base_sequence`, `recorded_at`) as the contract
  requires. Its chains are a different execution model, not a different wire
  meaning.

## Where annals still follows angzarr

- Stream identity is (domain, edition, root), and main is `""`.
- Sequences are u64, and `EventPage.sequence` is always definite.
- Correlation is always set. Causation names the triggering event.
- Facts use an infallible `ingest`. Strict replay: an unknown type URL fails,
  naming it.
- Business output is payloads, and the runtime stamps meta.

The plan's annals items (record_command and the commands table, refusing a
request with no id, `created_at` = `recorded_at`) are tracked in the session
plan, not here. "Materially similar" to angzarr means the same wire meaning,
not the same execution model.
