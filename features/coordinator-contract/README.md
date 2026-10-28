# Tier: coordinator-contract

Cucumber specs for behaviour the **coordinator** (core) owns: what happens
to commands, events and snapshots after a client hands them over. Client
libraries only set proto fields that select this behaviour; they never
implement it.

## Files

| Feature | Covers |
|---|---|
| `conflict_resolution.feature` | The default resolution from the registered state, unsupported resolutions refused, STRICT's ABORTED, AGGREGATE_HANDLES and COMMUTATIVE delivered with the window and a fresh nonce; reaction commands are never stale |
| `component_discovery.feature` | The coordinator asks its business process to describe its one component on connect and on every reconnect; nothing is delivered before; readiness; a versionless description is refused; failed requests logged, alerted after the grace period |
| `process_manager_delivery.feature` | A process manager is a domain behind its own coordinator (14.31): its own delivery, state and stream; which inputs start an instance (B1: a non-starting command refused, a fact skipped); commands it may refuse, facts it never does; dedup before the handler; other domains' events arriving only through policies, and decisions leaving through policies |
| `upcasting.feature` | The owning coordinator upcasts on load, on query and wherever stored events reach a subscriber (live or stored history) through its own business process; the store is never rewritten |
| `query_server.feature` | A standalone query server: queries with no component behind it, no commands, never a snapshot |
| `rules_version.feature` | The reported build version stamped in full on events and snapshots; the state returned with every answer stored per policy and offered unchanged; which snapshot is offered (registered state type, the default major.minor rule, exact match for non-semantic versions, a domain's accept and reject patterns) |
| `fact_flow.feature` | Fact injection: 0-based sequencing, `external_deferred.external_id` idempotency, failure handling; a fact carrying a causation_id accepted only by its trigger's domain |
| `state_building.feature` | Aggregate state reconstruction from snapshot + pages, `next_sequence` arithmetic |
| `edition_propagation.feature` | Source/trigger edition stamped onto every policy emission, a refusal fact included; a PM's events in its input's edition; main-timeline aliases (`""`, unset, `"angzarr"`) |
| `edition_forks.feature` | Editions as per-stream forks (14.32): the fork event at main's next sequence, the per-stream read rule, the fork travelling with the data, outside inputs refused until propagated (EDITION_NOT_FORKED), main reads for unforked streams, the unknown edition, listing with no registry, deletion sequenced after the work in flight, removing every row of the edition (a later arrival re-forks; a failed delete is dead-lettered), main byte-for-byte unchanged, the time-based option, PMs |
| `temporal_query.feature` | `TemporalQuery` as_of_sequence / as_of_time and when a snapshot may start the result |
| `policy_refusal.feature` | A refused policy command: the target records nothing and may return a typed refusal object; the policy builds the one refusal fact, passing CommandRefused (the object packed) through to its source's on_refused handler or translating it into a domestic fact; the refused command's id is the fact's id; one outbox transaction; no path (a run-time dead letter), a failing callback, a fact for another domain |
| `sync_modes.feature` | ASYNC, DECISION, SIMPLE, CASCADE, ISOLATED and the per-command `PageHeader.sync_mode` (caller's mode is a floor) |
| `dead_letter_queue.feature` | `angzarr.dlq.{domain}` routing and `AngzarrDeadLetter` contents per failure source |

## Who runs these

- **core** is the only implementer. Each scenario is a requirement on the
  coordinator; core binds them either through a coordinator cucumber runner
  or through unit tests that cite the scenario ID (edition propagation is
  covered that way today — see the header of `edition_propagation.feature`).
- **Client repos do not run this tier.** A client-side step definition can
  only simulate the coordinator, which tests nothing; client-rust's
  simulation worlds for `fact_flow`, `merge_strategy` (now `conflict_resolution`) and `state_building`
  are slated for removal for that reason.

## Domain vocabulary

Generic only — `order`, `inventory`, `payment`, `shipping`. No example (blackjack) types
(same rule as `../client/`, STEP_VOCABULARY.md §12, §17).

## Scenario IDs

`@C-NNNN`, shared with `../client/` and `../../parity/`; every scenario is
tagged and `just check-feature-ids` enforces presence, format and
uniqueness. Allocate the next with:

```bash
git grep -hoE '@C-[0-9]{4}' -- features parity | sort -u | tail -1
```
