# Tier: handler-contract

Cucumber specs for the **router**: what a client library's router does when
the coordinator calls the business process. Inside
`CommandHandlerService.Handle` (one call for commands and facts, decision
14.98), `PolicyService.React` and `Translate`, and `ProjectorService.Project`,
that is what happens between the delivery and business code and between
business code and the answer. The messages are the handler layer's
(`io.angzarr.handler.v1`, decision 14.78): each request carries the books,
read-only, and each response only what business code decides; every outcome
but success is a gRPC error status (decision 14.95). This tier is the
router's COMPLETE contract (decision 14.42): a router that passes it is a
router.

The router does only dispatch: routing by type URL, folding the starting
state and the pages it is given, running a command's or a fact's handler
(its `Emit`, continuations included, as one decision; 14.104), a policy's
reaction and its one refusal callback, and a projector, reporting the rules
version and the state, answering a typed refusal under its declared status,
and turning what escaped business code into a key and its args. It never
upcasts (14.39), never loads a snapshot (14.40), and never admits, guards an
envelope, builds or checks a descriptor, checks an expected sequence,
checks or stamps a policy's outputs, addresses a refusal fact or classifies
an error (14.42, 14.94); the coordinator has no conflict concept to judge
(14.92).
Those are the coordinator's, in [`../coordinator-contract/`](../coordinator-contract/).

## Files

| Feature | Covers |
|---|---|
| `handling.feature` | Refusing a second component (`registered`, `refused`); the post-command state on every answer; the build version on every answer; a delivered snapshot used whatever version recorded it; every delivered page folded onto the starting state; the unknown-type refusal naming the type the router was given; success only, every other outcome a gRPC status, a fact's error always a bug's (14.95, 14.98); typed refusals only, each under its declared status, an untyped rejection a bug (14.95); `Emit` as the one return type, its steps one decision, with no step cap and an idempotence test helper (14.104); a policy reacting to its one trigger event, outputs a root and a payload in the arm of their kind, its facts beside its commands as returned (Q3, 14.69, 14.91); the one refusal callback answering the domestic fact's payload alone, or a bug (14.89); errors as a key and an argument map, never English, one reason key per condition (14.37; panics and the unclassified error, 14.42); reading when the input was accepted (`recorded_at`, 14.37). The conflict nonce and units are retired with C-0541 to C-0550 (14.92) |
| `counter_dispatch.feature` | The CounterAggregate: folding prior events, emitting payloads only, refusing with a typed refusal, an unclassified failure, an unknown command, a failing fold, historical evidence, a starting state, routing under any type-URL prefix |
| `context.feature` | Facts recorded and flagged, a fact of no handler's type refused, appliers seeing sequences, handlers their cover, projector folds their place; a policy handler and a projector fold reading the event's whole metadata (14.61) |
| `policy_dispatch.feature` | The OrderPolicy: React handed one trigger event, a declared one answering an output of a root and a payload in its arm, an undeclared one emitting nothing, the handler seeing its trigger's sequence |
| `projector_dispatch.feature` | The CounterProjector: one projection, an undeclared domain folds nothing; no wildcard domain (14.53) |
| `compensation.feature` | A process manager's rollback, kept by the client library (14.74): the failed event, then each completed step's undo, newest first (C-0787 to C-0789); a reply after the rollback recorded and undone at once (C-0790, C-0791); each undo's target checked when its step is registered, one targeting a command refused (C-0792; 14.83); the refused undo of C-0793 and C-0796 retired, since no undo can be refused (14.83). Bound by the client libraries' process-manager tooling (angzarr-embedded's markup and client-python), not by a router's dispatch |

The fixtures every router runs these against are in [`fixture/`](fixture/FIXTURE.md).

## Who runs these

- **Every router**, in CI: angzarr-router (Rust, the reference) and
  client-python's native router. Each binds these scenarios by ID, from this
  directory, against the fixtures in `fixture/`.
- **`compensation.feature`** is a client library's process-manager tooling,
  not a router's dispatch (14.74): angzarr-embedded's markup (Rust) and
  client-python bind it, so the two languages agree.
- The coordinator's side of the same behaviour (stamping the version,
  choosing snapshots, admitting, checking an expected sequence, checking a
  policy's outputs, building refusal facts)
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
