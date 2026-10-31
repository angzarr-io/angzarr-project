# Tier: handler-contract

Cucumber specs for the **router**: what a client library's router does when
the coordinator calls the business process. Inside
`CommandHandlerService.Handle`, `PolicyService.Handle` and `OnRefused`, and
`ProjectorService.Handle`, that is what happens between the delivery and
business code and between business code and the answer. This tier is the
router's COMPLETE contract (decision 14.42): a router that passes it is a
router.

The router does only dispatch: routing by type URL, folding the starting
state and the pages it is given, running decide, ingest, a policy's
handlers and its translating callback, and a projector, reporting the rules
version, the state and a stale command's conflicts, and turning what
escaped business code into a key and its args. It never upcasts (14.39),
never loads a snapshot (14.40), and never admits, guards an envelope,
builds or checks a descriptor, checks or stamps a policy's commands,
addresses a refusal fact, classifies an error or judges a conflict (14.42).
Those are the coordinator's, in [`../coordinator-contract/`](../coordinator-contract/).

## Files

| Feature | Covers |
|---|---|
| `handling.feature` | Refusing a second component; the post-command state on every answer; the build version on every answer; a delivered snapshot used whatever version recorded it; every delivered page folded onto the starting state; the unknown-type refusal naming the type the router was given; the AGGREGATE_HANDLES nonce and the COMMUTATIVE unit sets reported, never judged; a policy's commands grouped by triggering page, unchecked; OnRefused's translated fact or no translation; errors as a key and an argument map, never English, one reason key per condition (14.37; panics and the unclassified error, 14.42); reading when the input was accepted (`recorded_at`, 14.37) |
| `counter_dispatch.feature` | The CounterAggregate: folding prior events, emitting, rejecting, an unclassified failure, an unknown command, a failing fold, historical evidence, a starting state, routing under any type-URL prefix |
| `context.feature` | Facts recorded and flagged, a fact of no handler's type refused, appliers seeing sequences, handlers their cover, projector folds their place |
| `policy_dispatch.feature` | The OrderPolicy: a declared event emits in its page's reaction, an undeclared one emits nothing, the handler sees its trigger's sequence |
| `projector_dispatch.feature` | The CounterProjector: one projection, an undeclared domain folds nothing; no wildcard domain (14.53) |

The fixtures every router runs these against are in [`fixture/`](fixture/FIXTURE.md).

## Who runs these

- **Every router**, in CI: angzarr-router (Rust, the reference) and
  client-python's native router. Each binds these scenarios by ID, from this
  directory, against the fixtures in `fixture/`.
- The coordinator's side of the same behaviour (stamping the version,
  choosing snapshots, admitting, delivering the window and the nonce and
  judging the report, checking a policy's commands, building refusal facts)
  is in [`../coordinator-contract/`](../coordinator-contract/).

## Domain vocabulary

Generic only: `order`, `inventory`, `payment`, `shipping`. No poker types
(STEP_VOCABULARY.md §12, §17).

## Scenario IDs

`@C-NNNN`, shared with `../client/`, `../coordinator-contract/`,
`../codegen/` and `../../parity/`. Allocate the next with:

```bash
git grep -hoE '@C-[0-9]{4}' -- features parity | sort -u | tail -1
```
