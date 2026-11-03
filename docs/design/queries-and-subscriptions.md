# Queries and subscriptions

**Status:** normative (decisions 13.3, 14.39, 14.51, 14.64; as amended by decisions 14.105 and 14.106). Moved from the comments of `proto/io/angzarr/transport/distributed/v1/query.proto` and `stream.proto` (decision 14.109). The services are `io.angzarr.transport.distributed.v1.EventQueryService` and `EventStreamService`; the messages are `query.proto`'s (`Query`, `TemporalQuery`, `CorrelationQuery`, `SequenceRange`, `SequenceSet`) and `stream.proto`'s (`SubscribeRequest`, `StreamFrom`, `CorrelationFrom`, `StreamCursor`).

How events are read back: EventQueryService for queries, and
EventStreamService for live events with catch-up. Use GetEvents for bulk
reads and EventStreamService.Subscribe for live events, with catch-up
from a resume point.

## 1. EventQueryService

EventQueryService is a separate, read-only interface, independent of
CommandHandlerCoordinatorService. An aggregate (or process manager)
coordinator serves it for its own component's domain. It may also run
standalone, as a read-only query server for downstream readers with no
component behind it; such a server serves no command RPCs: a command or
fact sent to it is answered UNIMPLEMENTED
DISTRIBUTED_REASON_COMMANDS_NOT_SERVED (arg domain; decision 14.51).

Snapshots. A coordinator judges a snapshot against its own registration
([snapshots.md](snapshots.md) §3 and §5). A standalone query server
holds no registration, so it never returns a snapshot: every result
carries every page from sequence 0 (up to the query's point).

Upcasting. A coordinator upcasts every event it returns through its
component's upcaster sidecar (see docs/design/upcasting.md; decision
14.39).

Editions. A Query or CorrelationQuery naming an unknown edition (no fork
event of it exists: never created with EditionAdminService.ForkStream,
or deleted; [edition-meta-events.md](edition-meta-events.md) §2 and §5)
is refused NOT_FOUND.

The RPCs:

```text
  GetEventBook         A single EventBook (unary): for explicit queries
                       with gRPC tooling.
  GetEvents            The EventBooks matching a Query, streamed: for
                       bulk retrieval (SSE).
  GetCorrelatedEvents  Every event of one correlation, across all
                       domains (§4).
  ListStreams          Every stream (SSE): one Cover (domain, edition,
                       root) per stream.
```

## 2. Selecting events: Query

A Query selects events within one domain. cover.domain is required, and
cover.edition picks the timeline (unset = main; a set name must be a
known edition, [edition-meta-events.md](edition-meta-events.md) §2, and
each stream is read by its fork:
main below its fork sequence, then the edition's own events; a stream
not yet forked reads as main). For every event of one correlation across
all domains, use EventQueryService.GetCorrelatedEvents (CorrelationQuery,
§4).

```text
  By stream:       cover { domain, root }
  By correlation:  cover { domain } + correlation_id; every stream of the
                   domain is searched, one EventBook per matching stream
  Both:            cover { domain, root } + correlation_id; that stream only
```

The selection (a SequenceRange, a SequenceSet or a TemporalQuery), when
set, applies within each selected stream. A SequenceRange with no upper
queries to the latest.

The correlation selector (Query.correlation_id): when set, only pages
whose EventMeta.correlation_id equals it (the same 16 bytes) are
returned; a set value that is not 16 bytes is INVALID_ARGUMENT.
Correlation is recorded per page only (covers carry none); all pages of
one write share one correlation. It never crosses cover.domain
(CorrelationQuery does).

## 3. Temporal queries

A TemporalQuery retrieves aggregate state at a point in history. The
returned EventBook may start from a snapshot instead of sequence 0, but
only from one that cannot contain state from after the point:

```text
  - as_of_sequence N: a snapshot with sequence <= N, followed by pages
    snapshot.sequence+1 .. N.
  - as_of_time T: the stream's prefix up to and including the last event
    whose EventMeta.recorded_at <= T. recorded_at is non-decreasing per
    stream ([identity-and-streams.md](identity-and-streams.md) §5.4), so
    this is a prefix: no later event can have an
    earlier recorded_at. The book may start from a snapshot whose last
    folded event (the page at snapshot.sequence) lies in that prefix.
```

Without a qualifying kept snapshot (by default only the newest is kept)
the book carries no snapshot and every page from 0 up to the point.
Either way, folding the book yields the same state as a full replay to
the point.

## 4. Correlated events and forward causation

GetCorrelatedEvents answers every event of one correlation, across all
domains: the whole workflow a request or a fact started. It answers one
EventBook per stream (domain, edition, root) holding that stream's pages
with the correlation, in sequence order. The order of books is
unspecified. A Query's correlation selector stays within one domain;
this RPC does not. An unset correlation_id, or one that is not 16 bytes,
is INVALID_ARGUMENT; a correlation with no events is an empty stream, not
NOT_FOUND. REST: the path segment is the UUID's bytes, so transcoding
takes base64 (URL-safe), not canonical UUID text
([identity-and-streams.md](identity-and-streams.md) §2).

CorrelationQuery.edition is the timeline, as Cover.edition: unset = main;
a set name must be non-empty (a set "" is refused INVALID_ARGUMENT) and
must be a known edition ([edition-meta-events.md](edition-meta-events.md)
§2), and each stream is read as the
edition reads it (main's events below that stream's fork sequence, then
its own; a stream not yet forked reads as main).

Forward causation, from the result alone. Every reaction (a policy's
commands, their events, a process manager's events, and refusal facts
and their events) carries its trigger's correlation
([identity-and-streams.md](identity-and-streams.md) §6.2), so everything
event E led to is in the result. How exactly each edge is known depends
on the kind of event (decision 13.3):

```text
  - Events of a refusal fact are linked EXACTLY: their
    causation.command_id is the refused command's id, derived from E,
    the policy and the command's index
    ([identity-and-streams.md](identity-and-streams.md) §3.2 and §3.3;
    decision 14.31).
  - Events of reaction commands are linked only COARSELY, by
    correlation: the pages of one command share its
    causation.command_id, but the command's trigger (ReactionDelivery.causation)
    is not on its events. The exact trigger edge (E -> the commands a
    policy emitted for it -> their events) is in the traces and
    logs the coordinators write (OpenTelemetry), not in the store.
```

Accepted cost: the event store alone answers "what belongs to this
workflow", but not "which events did this policy's reaction to E
produce"; that question goes to the traces, whose retention the
deployment chooses. Rejected commands leave no events, so they do not
appear (see the attempt-audit sink in the design record).

The GetCorrelatedEvents RPC's own comment summarised this as "exact for
process events, by correlation only for reaction commands' events"; the
CorrelationQuery text above names refusal facts' events as the exact
case.

## 5. EventStreamService.Subscribe: catch-up, then live

EventStreamService streams events to subscribers, catch-up then live
(decision 14.105).

Subscribe subscribes to one target (SubscribeRequest.target): one
stream, or every stream of one correlation. Each answer is an EventBook
of one stream's pages. The server first delivers every page the target
holds after the subscriber's resume point (catch-up), then every page
committed after, as it commits (live), with no gap and no duplicate
between the two, so a subscriber that queried first loses nothing to the
race between its query and its subscription.

Order is per stream only: a stream's pages arrive in sequence order;
pages of different streams arrive in no defined order. There is no
cross-stream order and no store-wide position: a resume point is one
sequence per stream, the next one to deliver, inclusive, as
SequenceRange.lower (StreamFrom.from_sequence, CorrelationFrom.seen;
decision 14.106).

Refusals: a target that is unset, a cover with no domain or a root that
is not 16 bytes, or a correlation_id unset or not 16 bytes, is
INVALID_ARGUMENT; an unknown edition is NOT_FOUND (as
EventQueryService).

REST: Server-Sent Events (SSE). A stream subscription is GET
/v1/stream/{domain}/{root}, with from_sequence and cover.edition as
query parameters. A correlation subscription is POST
/v1/stream/correlations/{correlation_id}, the request its body, since
its resume point (seen) is a list of messages, which a query string
cannot carry. A browser's EventSource opens GET only, so a browser
subscribes to a correlation with a fetch-based SSE reader (decision
14.106: accepted). Path segments that are UUIDs take the UUID's
bytes field, so HTTP transcoding takes them as base64 (URL-safe), not as
canonical UUID text (the accepted cost of UUID-typed ids;
[identity-and-streams.md](identity-and-streams.md) §2).

## 6. Resume points

One stream (StreamFrom): every page of the stream with a sequence at or
above from_sequence, then live. The stream's timeline is cover.edition,
read as EventQueryService reads it. A subscriber that reconnects sets
from_sequence to the last sequence it received + 1. from_sequence is the
first sequence to deliver, inclusive, as SequenceRange.lower: 0 is the
stream's start.

One correlation (CorrelationFrom): every page whose
EventMeta.correlation_id is correlation_id, in every domain, from each
listed stream's cursor (inclusive), and from the start of any stream not
listed; then live. correlation_id is required. CorrelationFrom.edition is
the timeline, as CorrelationQuery.edition: unset = main; a set name must
be non-empty and a known edition, and each stream is read as the edition
reads it.

Building seen: for each EventBook received, the subscriber keeps its
cover and its last page's sequence + 1, the highest per cover. On
reconnect, seen is one StreamCursor per stream it kept. A stream it has
never received from is simply not listed. seen holds at most one cursor
per stream; each cover's edition is the subscription's (a cursor of
another edition, or two of one stream, is INVALID_ARGUMENT). A
StreamCursor's next_sequence is the next sequence to deliver of that
stream, inclusive: the last sequence the subscriber received + 1.
