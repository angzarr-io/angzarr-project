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
| `process_manager_delivery.feature` | Each process manager behind its own coordinator gets its own delivery, process state and stream |
| `rules_version.feature` | The reported build version stamped in full on events and snapshots; the state returned with every answer stored per policy and offered unchanged; which snapshot is offered (registered state type, the default major.minor rule, exact match for non-semantic versions, a domain's accept and reject patterns) |
| `fact_flow.feature` | Fact injection from sagas/PMs: 0-based sequencing, `external_deferred.external_id` idempotency, failure handling |
| `state_building.feature` | Aggregate state reconstruction from snapshot + pages, `next_sequence` arithmetic |
| `edition_propagation.feature` | Source/trigger edition stamped onto every saga/PM emission; main-timeline aliases (`""`, unset, `"angzarr"`) |
| `temporal_query.feature` | `TemporalQuery` as_of_sequence / as_of_time and when a snapshot may start the result |
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
