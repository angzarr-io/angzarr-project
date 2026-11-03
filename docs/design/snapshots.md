# Snapshots: where they come from and when one is offered

**Status:** normative (decisions 14.40, 14.66; as amended by decision 14.104, reversing 14.88's refusal). Moved from `proto/io/angzarr/v1/types.proto`'s comments (decision 14.109). Covers what a snapshot is for, how the coordinator writes and offers one, and the validity checks (state type and rules version) that decide whether it may be used. The message is `types.proto`'s `aggregate_snapshot` region (`Snapshot`); the registration it is checked against is `ComponentDescriptor` ([component-descriptors.md](component-descriptors.md)), and rules_version on events is [identity-and-streams.md](identity-and-streams.md) §5.4.

## 1. A framework optimisation

A Snapshot is aggregate state at a given sequence number. State must be
a protobuf Message to serialize into Any.

Snapshots are a framework optimisation, never business data. How often
they are taken and how many are kept is framework/storage policy,
configured per domain and following the edition's storage configuration;
the default keeps the newest snapshot only. Business milestones are
domain events, never retained snapshots.

## 2. Where snapshots come from

The client library returns the post-command state on EVERY answer
(io.angzarr.handler.v1.HandleResponse.state, for an aggregate or a
process manager alike); business code never decides when. The
coordinator persists it per the domain's storage policy (default: keep
the newest only), setting sequence (the last event folded in) and
rules_version (the response's, in full, stamped by the coordinator, never
by business code), and offers the stored bytes, unchanged, with the next
delivery to that stream, subject to the validity checks (§3). Neither
side asks: there is no request flag. The coordinator decides when to
write one; the client library never does. A delivery that offers a
snapshot carries only the pages after it: the coordinator drops the pages
it covers, and the client library folds what it is given (decision
14.40).

## 3. Validity

A snapshot records what produced it: the state's type (the type URL of
`state`) and the rules version reported with the response that returned
the state (rules_version, the business binary's full version). The
coordinator, never the business logic, decides whether a snapshot may be
used. It offers a snapshot with a delivery (the history of
io.angzarr.handler.v1.HandleRequest, for an aggregate or a process
manager alike) only if both hold:

1. the fully-qualified name its state's type URL ends in (the text after
   its last "/") equals the type_name of the StateDescriptor the
   component registered; and
2. its rules_version passes the domain's compatibility rule (§4) against
   the version the component registered
   (ComponentDescriptor.rules_version).

A snapshot that fails either check is simply not offered: the delivery
carries no snapshot and every page from sequence 0, and business code
folds the full history. The business logic declares no snapshot
compatibility and never checks or refuses a delivered snapshot. A
state-schema change or a rules change therefore never needs a snapshot
migration: the next load replays, and the next snapshot is written under
the current rules version.

## 4. The compatibility rule

The default rule: strip ONE leading "v" or "V" from each version, then
both parse as SemVer 2.0.0 and their major and minor numbers are equal
(patch, pre-release and build metadata are ignored), so "v1.4.2" and
"1.4.7" are compatible. When either does not parse as SemVer 2.0.0 once
so stripped, the two are compatible only when they are equal as recorded
(exact string equality, nothing stripped): a rules_version that is not
SemVer is accepted at registration (decision 14.104, reversing
14.88's refusal), and a snapshot recorded under it is offered to that
version alone.

Nothing replaces the default rule: no configuration of a domain accepts
or rejects snapshot versions by pattern (decision 14.66).

## 5. Queries

Queries (EventQueryService, including a TemporalQuery) choose snapshots
the same way: a coordinator answering a query returns a snapshot only if
it passes both checks against that coordinator's own registration (one
business process per coordinator; during a rolling deployment each
instance's coordinator judges by its own instance's version). A server
holding no registration (a coordinator before its first successful
Describe, or a standalone query server, which has no component behind
it; see [queries-and-subscriptions.md](queries-and-subscriptions.md) §1)
returns no snapshot and
every page from sequence 0.

A TemporalQuery as_of_time T may start from a snapshot iff the event at
its sequence (the last event folded into `state`) has
EventMeta.recorded_at <= T, i.e. iff the snapshot lies within the prefix
recorded by T ([queries-and-subscriptions.md](queries-and-subscriptions.md)
§3).
