# Tier: coordinator-contract

Cucumber specs for behaviour the **coordinator** (core) owns: what happens
to commands, events and snapshots after a client hands them over. Client
libraries only set proto fields that select this behaviour; they never
implement it.

## Files

| Feature | Covers |
|---|---|
| `merge_strategy.feature` | COMMUTATIVE field-overlap merge over the window expected..actual, STRICT, AGGREGATE_HANDLES, MANUAL→DLQ for explicit-sequence commands; deferred saga/PM commands are never checked |
| `fact_flow.feature` | Fact injection from sagas/PMs: 0-based sequencing, `external_deferred.external_id` idempotency, failure handling |
| `state_building.feature` | Aggregate state reconstruction from snapshot + pages, `next_sequence` arithmetic |
| `edition_propagation.feature` | Source/trigger edition stamped onto every saga/PM emission; main-timeline aliases (`""`, unset, `"angzarr"`) |
| `temporal_query.feature` | `TemporalQuery` as_of_sequence / as_of_time and when a snapshot may start the result |
| `sync_modes.feature` | ASYNC, DECISION, SIMPLE, CASCADE, ISOLATED and the per-command `PageHeader.sync_mode` override |
| `cascade_error_mode.feature` | FAIL_FAST, CONTINUE (`reaction_errors`), COMPENSATE (Compensate markers on executed reactions), DEAD_LETTER under CASCADE |
| `dead_letter_queue.feature` | `angzarr.dlq.{domain}` routing and `AngzarrDeadLetter` contents per failure source |
| `snapshot_retention.feature` | DEFAULT and TRANSIENT pruned by a newer snapshot; PERSIST kept |

## Who runs these

- **core** is the only implementer. Each scenario is a requirement on the
  coordinator; core binds them either through a coordinator cucumber runner
  or through unit tests that cite the scenario ID (edition propagation is
  covered that way today — see the header of `edition_propagation.feature`).
- **Client repos do not run this tier.** A client-side step definition can
  only simulate the coordinator, which tests nothing; client-rust's
  simulation worlds for `fact_flow`, `merge_strategy` and `state_building`
  are slated for removal for that reason.

## Domain vocabulary

Generic only — `order`, `inventory`, `payment`, `shipping`. No poker types
(same rule as `../client/`, STEP_VOCABULARY.md §12, §17).

## Scenario IDs

`@C-NNNN`, shared with `../client/` and `../../parity/`; every scenario is
tagged and `just check-feature-ids` enforces presence, format and
uniqueness. Allocate the next with:

```bash
git grep -hoE '@C-[0-9]{4}' -- features parity | sort -u | tail -1
```
