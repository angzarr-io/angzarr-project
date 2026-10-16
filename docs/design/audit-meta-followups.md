# Audit-meta proto passes: follow-ups and known gaps

## Status

Open. Records what the three `feat/audit-meta` proto passes leave for angzarr's
code, the known gaps the audit surfaced, and the questions still to decide.
The protos under `proto/io/angzarr/` and the `rust/angzarr-proto` crate are
the only things these passes changed. Nothing listed here is done.

- Pass 1 (9cfed59, 17bc1cd): provenance meta, uint64 sequences, one-command
  books, the origin oneof, facts as commands, no reservations.
- Pass 2 (46404df): CASCADE/ISOLATED, compensation and notification,
  speculative execution, snapshot retention and `undoes`/`compensates`
  removed; PayloadReference made transport-only; the DRY refactor (`Cover`,
  `EventRef`, `Provenance`, `Expectation`); the `Command`/`Fact` body oneof;
  `ResponseMeta`.
- Pass 3 (this change): handling separated from identity, business data
  and provenance. `Handling { optional expected_sequence; merge; sync }`
  lives on `CommandBook` (field 6) and is never persisted; `Expectation`,
  `CommandRequest`, `ContextualCommandRequest`, `SagaHandleRequest`,
  `ProcessManagerCoordinatorRequest` and `ResponseMeta` are deleted.
  `CommandResponse` is `{ events, Outcome outcome }`, with
  `Outcome { delivery; projections }`. `CommandPage` is provenance + body
  only.

Wire breaks are accepted pre-freeze: removed fields and messages are deleted
outright, with no `reserved` statements.

## Code follow-ups, by repo

### core (coordinator, storage, bus)

From pass 1:

- Widen sequences to u64 end to end: the `EventStore` trait, Postgres
  `INTEGER`/`i32` casts, and Bigtable's `{:010}` key padding.
- Remove `Cover.ext` and the storage `ext` columns, along with router
  stamping and the roughly 60 core sites that read it. Parent references move
  into domain event payloads, and sagas route from payloads.
- Correlation is per page only. Stop reading it from `Cover`, and implement
  `Query.correlation_id` (one correlation per write).
- Delete `PageHeader`, the deferred-sequence types, `HandleFact`/`HandleEvent`/
  `Replay`, `EventRequest.skip_handler`, and saga/PM facts.
- Check or stamp the expected sequence before business code, and record
  `EventMeta.decided_at` on every event.
- Keep only `STRICT` and `AGGREGATE_HANDLES`. Under `AGGREGATE_HANDLES`,
  deliver the conflict window with the command.
- Main edition is `""` only: drop the `"angzarr"` alias, and have
  `DeleteEditionEvents` reject `""`.
- Make storage edition routing and sharding configurable per edition.
- Persist provenance: stamp `EventMeta` on every page the coordinator writes.
  Until this lands, angzarr-run streams lose causation.
- Known core bugs (filed in angzarr's log): the correlation query ignores the
  domain (uncurious-president), and cached replays relabel correlation
  (unpaved-ultimate).
- `CommandBook` runs only its first page, and extra pages are silently
  ignored. The wire now holds exactly one page, so the code should match.

From pass 2:

- Delete `CASCADE`, `ISOLATED` and the cascade error modes, along with
  `CommandResponse.reaction_errors`. Sagas and PMs always run asynchronously.
  Replay, migration and recovery tooling has no silent mode: it either lets
  reactions run or rebuilds projections afterwards.
- Delete the compensation outbox's notification path: `Notification`,
  `RejectionNotification`, `Compensate`, `HandleCompensation`,
  `RevocationResponse`, `BusinessResponse`, `SagaCompensationFailed`,
  `CompensationDeliveryFailedDetails` and escalation forwarding. Keep the
  outbox for a PM's own command delivery only. `CommandHandlerService.Handle`
  now returns an `EventBook`, and a rejection is a gRPC status.
- Implement PM reply handling: a target's answer reaches the PM as a trigger
  whose causation names the PM's event. A hard rejection of a saga or PM
  command is retried when retryable and dead-lettered otherwise (see open
  questions).
- Delete every speculative RPC. Implement what-ifs as commands in an edition:
  - configured editions use their own storage config;
  - unconfigured editions fall back to a configured default edition store
    (memory, redis, persistent, or the existing database);
  - the edition column stays in every schema;
  - projector output follows the edition's storage config.
- Snapshot policy: delete `SnapshotRetention`. Frequency and keep-count become
  framework/storage config, per domain and following the edition's storage.
  The default keeps the newest only. Temporal queries start from the nearest
  kept snapshot or from 0. The config shape still needs designing.
- `EventPage.created_at` is gone. Stamp and index `EventMeta.recorded_at`, and
  make `TemporalQuery.as_of_time` and snapshot selection use the recorded_at
  of the event at `snapshot.sequence`. `Snapshot.created_at` is deleted too.
- PayloadReference is out of the persisted pages. Move claim-checking into a
  bus envelope owned by the transport layer, and resolve it before anything
  else sees the message.
- `Cover.edition` is now a string. Move divergence points into edition
  configuration (`Edition`/`DomainDivergence` are gone from the wire).
- `EventRef` is now `{ Cover stream; sequence }`. `Provenance` holds
  `{actor, correlation_id}`, and `CommandMeta` is deleted. (`Expectation`
  went in pass 3; see below.)
- Reflective dispatch: the `CommandPage.body` arm picks the pipeline
  (`Command` goes to decide, `Fact` to ingest), and the payload type URL picks
  the handler. Deduplicate before business code: causation on
  (event, component, index), facts on `external_id` per target stream. Return
  `Outcome.delivery` (`APPLIED`/`DUPLICATE`), and never persist it.
- Refuse a `Fact` that sets `handling.expected_sequence` as
  `INVALID_ARGUMENT` (a pass-2 judgement, see open questions). Dead-letter a
  failing fact handler and alert on it.

From pass 3:

- `HandleCommand` takes `CommandBook` directly (HTTP:
  `POST /v1/ch/{cover.domain}/commands`). `SagaService.Handle`,
  `SagaCoordinatorService.Execute` and `ProcessManagerCoordinatorService.Handle`
  take `EventBook` directly. Delete the request wrappers in code.
- Resolve `CommandBook.handling` in place before business code: stamp
  `expected_sequence` when absent, and fill `merge` and `sync` from
  configuration when unspecified. `ContextualCommand` and business code see
  only resolved handling. Never persist it.
- Configuration for merge strategy and sync mode, per command type and per
  component. Precedence, highest first: `Handling` (when set and allowed),
  command-type config, component config, built-in default (STRICT, ASYNC).
  Config can forbid overriding a field per command type or component; a
  command that sets a forbidden field is refused `INVALID_ARGUMENT`, never
  silently ignored. The config shape still needs designing.
- Reaction commands (saga, PM) leave `Handling` unset. Refuse one that sets
  `expected_sequence` or `sync` as a reactor bug (`INVALID_ARGUMENT`, never
  delivered). Delete the per-command sync floor (`reaction_sync_mode` and
  the `PageHeader.sync_mode` preservation in the saga and PM stamping);
  reaction delivery mode comes from component config.
- **Core and the router disagree on explicit sequences in reaction
  commands.** Core's saga and PM stamping keeps an explicit sequence
  (`Some(SequenceType::Sequence(_)) => continue` in
  `orchestration/saga/mod.rs` and `orchestration/process_manager/mod.rs`);
  the router's `stamp_pages` replaces it. Resolved in pass 3: forbid it.
  Core must refuse it, as above, rather than pass it through.
- **Core's merge default is commutative; the protos default to STRICT.**
  `CommandPageExt::effective_merge_strategy` calls
  `MergeStrategy::or_default_commutative`. The wire contract (and pass 3's
  built-in default) is STRICT, and `COMMUTATIVE` no longer exists on the
  wire. Core must default to STRICT when neither `Handling` nor config sets
  a strategy.
- DLQ: store `rejected_command` as received (handling as sent). Replay
  `AS_IS` keeps it; `FRESH_SEQUENCE` clears `handling.expected_sequence` so
  the coordinator stamps the head (today it re-stamps page headers from a
  query). Replay must stop hardcoding `SyncMode::Simple` over the stored
  handling.
- `EventRequest.sync_mode` (projector `HandleSync`) was not touched by
  pass 3; it is an event-delivery wrapper, not command handling. Decide
  whether it stays.

### angzarr-router

- Remap onto `angzarr-proto` via `extern_path`. This ends the triple type
  generation (gap 9).
- Mirror the pass-2 dispatch: route on body arm, then type URL. Delete the
  compensation, undo and speculative dispatch, and the notification
  envelopes.
- Pass 3: `angzarr_router_dispatch_saga` takes `EventBook` bytes (not
  `SagaHandleRequest`). Reaction stamping leaves `Handling` unset and
  refuses a handler-set `expected_sequence` or `sync`; drop the
  `PageHeader.sync_mode` preservation.

### Client libraries (go, rust, python, java, csharp, cpp, typescript)

- u64 sequences everywhere (pass 1).
- Python's `unpack_parent_cover` goes with `Cover.ext` (pass 1).
- Fact handlers as an infallible interface with no error arm (annals:
  `Domain::ingest(&state, fact) -> Vec<Event>` beside fallible `decide`).
  Codegen also needs to know which handlers are fact handlers (see open
  questions).
- Conflict-resolution helpers for `AGGREGATE_HANDLES`, computed locally over
  the delivered window.
- Delete the compensation handlers, `undoes`/`compensates` codegen, rejection
  fan-out and the speculative client APIs. Regenerate for the new
  `CommandPage` shape (`provenance`, `body`) and `CommandBook.handling`;
  clients send `CommandBook` directly and read `CommandResponse.outcome`.
- Leftover 2PC in generated Python (pass 1 audit).

### Examples (examples-*, poker protos)

- Poker protos used `Cover.ext` (pass 1).
- The `compensates: DealCards` annotations on `TableHandSaga` and `TableState`
  were removed from `proto/io/angzarr/examples/v1` so the protos build. The
  example code that implemented that compensation needs reworking as a
  refusal event plus a saga.

### angzarr-project (site, features, parity)

- The site embeds proto regions that no longer exist: `edition`,
  `snapshot_retention`, `rejection_notification` (removed in pass 2), and
  `page_header` (removed in pass 1). A strict site build fails until
  `reference/patterns.mdx` and its siblings are rewritten. New regions are
  available: `provenance`, `handling`, `outcome` (pass 3 replaced the
  pass-2 `expectation` and `response_meta` regions). The `sync_mode` and
  `merge_strategy` regions now say "unspecified means the configured
  default"; the merge-strategy and sync-mode tables need the config
  precedence.
- Feature specs still exercise the removed features: CASCADE (6 files),
  ISOLATED (3), notifications and compensation (4), speculative execution
  (3), `undoes` (2), and others. Rewrite or delete them.
- Stale 2PC tasks in core's `tasks.md`, and leftover 2PC in stale branches.

## Known gaps

7. **Upcasting runs only on aggregate loads.** Sagas, PMs, projectors and
   queries see raw stored versions. A missing upcaster rule silently drops
   the event on rebuild, when it should fail. annals plans strict replay (an
   unknown type URL fails, naming it, with golden-fixture checks in CI).
   angzarr should do the same on every read path.

8. **No multi-stream unit of work, and upcasters are 1:1.** angzarr appends
   one command's events to one stream per write, and an upcaster maps one
   stored event to one current event. For comparison (from knowledge, not
   verified for this note):
   - **Marten**: one session can append to many streams and commit them in
     one Postgres transaction. Upcasting is 1:1 (one old event type to one
     new).
   - **Axon**: a `UnitOfWork` spans the handling of one message, including
     events applied to several aggregates. Upcasters work over an
     intermediate representation and can split one event into N, or drop
     it.
   - **KurrentDB** (EventStoreDB): one stream per append, and no
     multi-stream transactions. Consistency across streams is by process
     managers and idempotency.

   annals (hatpick's runtime) stages atomic chains across streams in one
   Postgres transaction. angzarr would need a coordinator-level UoW to match.

9. **Triple Rust type generation.** core, angzarr-router and client-rust each
   generate `io.angzarr.v1` from the protos. Remap them onto `angzarr-proto`
   via `extern_path`, so there is one set of types.

10. **Stale docs.** About ten pages: the merge-strategy and sync-mode tables,
    upcasting, the facts audit claims, the glossary, and every page about
    CASCADE, compensation, speculative execution and snapshot retention. In
    `site/src/content/docs/components/commands-vs-facts.md`:
    - The "Axon Framework" section claims Axon distinguishes "decision
      commands" from "notification commands". This is unverified. From
      knowledge, Axon has no such concept (its command handlers are uniform),
      so the claim needs checking against Axon's reference guide, and
      probably removing.
    - The same page's "Angzarr's Solution" section (facts as events with a
      fact sequence indicator) is superseded by the `Fact` arm.

11. **The `feat/blackjack-spec` branch exercises removed features.** Its
    features include `cascade_error_mode.feature`,
    `compensation_delivery.feature`, `snapshot_retention.feature`,
    `speculative_client.feature`, ISOLATED in `sync_modes.feature`, and
    blackjack saga/PM scenarios built on compensation. It needs rebasing
    onto the new contract, or those scenarios retiring.

12. **`buf breaking` doesn't gate merges.** `just proto-breaking` is
    manual-only, and `contracts.yml` runs lint alone. Revisit at angzarr's
    v0.1.0 freeze, or before hatpick stores production events.

## Resolved questions

- **Merge strategy placement** (resolved in pass 3): both. Configuration
  sets the default per command type and per component, and
  `CommandBook.handling.merge` overrides it where configuration allows. The
  same holds for sync mode. See the `Handling` region in `types.proto` for
  the precedence.

## Open questions

- **Edition lifetime per backend.** Memory lasts the process, redis its TTL,
  a database persists. Open: whether a TTL or GC policy is configured per
  edition, what happens to an edition whose backend evicts it mid-use, and
  whether `DeleteEditionEvents` must also clear the edition's projections and
  snapshots.
- **Multi-instance affinity for in-memory editions.** With several
  coordinator instances, an in-memory edition lives in one process. Requests
  for that edition need affinity (routing on edition name), a shared backend
  (fall back to redis), or a rule that in-memory editions are single-instance
  only.
- **Hard rejections of saga/PM commands.** With notifications gone, a
  non-retryable rejection of a reaction command is dead-lettered. Open:
  whether a PM should instead learn of it (for example, a framework-recorded
  event on the PM's own stream). Business refusals are expected to be domain
  events, so this concerns validation and precondition failures only.
- **Codegen marker for facts.** On the wire the `Fact` arm marks a fact. Open:
  how codegen knows to emit an infallible ingest handler for a payload type
  (a `CommandOptions` flag, a separate `(fact)` option, or a naming rule).
- **`expected_sequence` on a Fact.** Pass 2 documented a Fact carrying an
  expectation as malformed (`INVALID_ARGUMENT`), and pass 3 keeps that for
  `handling.expected_sequence`. The alternative is to ignore it and stamp
  the head. Confirm.
- **Forbidden overrides.** Pass 3 refuses a command that sets a `Handling`
  field configuration forbids (`INVALID_ARGUMENT`), rather than ignoring
  it. Confirm.
- **`merge` on a reaction command.** Pass 3 forbids `expected_sequence` and
  `sync` on reaction commands but tolerates `merge`, which has no effect on
  a stamped command. Confirm, or forbid it too.
