# Projectors: delivery, positions and per-stream projection

**Status:** normative (decision 14.68; as amended by the DRAFT decisions 14.78, 14.96, 14.97 and 14.107 pending review). Moved from `proto/io/angzarr/component/v1/projector.proto`'s and `proto/io/angzarr/handler/v1/projector.proto`'s comments (decision 14.109). The service is `io.angzarr.component.v1.ProjectorService`; the messages are `io/angzarr/handler/v1/projector.proto`'s (`ProjectRequest`, `ProjectResponse`), under the handler layer's rule (docs/design/handler-contract.md §2).

A projector is client logic that projects events to read models. Client
logic does not care about sync: the coordinator decides.

## 1. What Project is handed

Project is handed a run of one stream's events (decision 14.78, DRAFT), in
order, upcast. A projector folds the run into one write, reading each
page's context from its EventMeta. The projector persists its read model
and answers the projection; the coordinator builds core's Projection from
it (§5).

## 2. Per-stream projection: no cross-stream order

A projector over several domains receives each stream's run independently,
in any order across streams: there is NO cross-stream order (decision
14.96, DRAFT). Within one stream the pages are in sequence order.

Multi-domain projectors should be rare. They are not substitutes for
process managers or business logic: the capability exists for system
capabilities such as the timekeeping module, global logging and the like
(the owner, 2026-11-02; decision 14.96, DRAFT).

## 3. Editions

A projector keys its read model by edition (Cover.edition; the edition is
part of stream identity, [edition-meta-events.md](edition-meta-events.md)
§6), as by stream.

Events from a non-main edition are projected like any others; the
projection's output follows that edition's storage configuration (an
in-memory edition's projections are kept in memory;
[edition-meta-events.md](edition-meta-events.md) §9).
Its CloudEvents publish to the configured sinks like main's (decision
14.107, DRAFT).

## 4. Delivery and positions

Delivery (decision 14.97, DRAFT; the owner: "coordinator should not mark
as done until business logic responds with an affirmative"). The
coordinator records a run's position (its processed state, decision
14.68) ONLY after the projector's affirmative ProjectResponse. An error
status, or no answer, leaves the run unmarked, and it is delivered again.

So a run whose read-model write landed but whose mark did not (a crash
between them) is delivered again: the projector skips what it has already
applied, by (stream, sequence), which every page of the request carries.

## 5. What the coordinator builds from the answer

What Project answers is the projection, and nothing the coordinator knows.
The coordinator builds core's Projection from it: cover the run's,
projector the component's registered name, next_sequence the last page's
sequence + 1. That is what HandleSync answers its caller
(io.angzarr.transport.distributed.v1.CommandSyncResult.projections) and
what the projector's position records.
