# Editions: forks, the not-forked rule and deletion

**Status:** normative (decisions 14.32, 14.36, 14.65, 14.86; decisions 14.106 and 14.107). The messages are `io/angzarr/v1/types.proto`'s `meta_events` region (`MetaEvent`, `EditionCreated`), `Cover.edition` and the `editions` region (§6 to §9 moved from their comments, decision 14.109); the administration RPCs are `io/angzarr/transport/distributed/v1/meta.proto`'s `EditionAdminService`.

**What editions are for.** An edition's main use is operations research
and experimenting: a what-if run of real commands against a fork of real
streams. It is not restricted to that, and it may hold real data. An
edition is a deliberately crafted system, so explicit creation is the
rule: whoever builds one decides which streams it holds, and forks each
with ForkStream (the owner, 2026-11-02: "the explicit creation is
absolutely permissable because they're crafted systems"; decision 14.107,
ruled 2026-11-02).

## 1. A fork is explicit, per stream

An edition X is a set of per-stream forks and nothing else: there is no
edition registry and no separate metadata store. A stream (D, X, R) exists
in X from its fork, and every fork is made explicitly, by
`EditionAdminService.ForkStream`, at the `fork_sequence` the caller states
(decision 14.107: there is no automatic propagation).

ForkStream appends one `EditionCreated` to (D, X, R) at that sequence: its
own EventPage.sequence IS the fork point (decision 14.86), stated nowhere
else, and the page's cover names the edition. (D, X, R) reads main's
events below the fork point, then X's own (the fork event first). Main's
later events never reach it.

The parent is authoritative, period (the owner, 2026-11-02: "the parent
should never have any concept of forks/branches. It is authoritative,
period."): main's stream holds nothing of any edition, records no fork,
and is never written, read for, or held back by an edition's lifecycle. A
store accepts any stated sequence at or below main's head for that stream
(the sequence main's version would use next) and refuses one above it as a
conflict; it never moves a fork to the head. The fork point is per stream:
no cross-stream snapshot is promised.

## 2. The not-forked rule

A command or fact in X addressed to a stream with no `EditionCreated` in
X is an error, whoever sent it: refused FAILED_PRECONDITION
`ANGZARR_REASON_EDITION_NOT_FORKED` (args `stream`, `edition`), checked
when the input is loaded, before business code runs; nothing runs and
nothing is persisted (the owner: "propagation of an edition without
edition created should be an error").

- A client's input is answered the refusal; the client forks the stream
  and resends.
- A policy's reaction in X to a stream not forked in X is a failed
  delivery like any other: dead-lettered with this key as its reason, and
  alerted. It is the framework's key, not a typed refusal, so it never
  reaches the policy's Translate. A policy that works in an edition needs
  every stream it reaches forked first.
- The same rule refuses an input in an edition that was never created or
  has been deleted: no stream of it holds an `EditionCreated`.

A query or subscription of a stream not forked in X reads main's version
(identical so far) and forks nothing. A query or subscription naming an
edition no stream is forked in is refused NOT_FOUND.

## 3. Meta-events

A meta-event is a real event, appended to a stream and stamped like any
other, but the framework's, not a domain's. It is told apart by TYPE: an
EventPage's body is `oneof { google.protobuf.Any event; MetaEvent
meta_event }` (decision 14.106). `EditionCreated` is the one
meta-event (decision 14.107).

- Stores act on the `meta_event` arm: a store reads an edition stream
  through its `EditionCreated`, and `ListEditions` and `DeleteEdition`
  enumerate an edition's streams by it.
- Business handlers NEVER see one: the client library hands business code
  only the `event` arm.
- No input carries one: a CommandPage has no meta arm, so a command whose
  payload happens to be an `EditionCreated` is an ordinary command of an
  unknown type.

## 4. Deletion by enumeration

`EditionAdminService.DeleteEdition` enumerates X's forked streams from
their `EditionCreated` events, as `ListEditions` reads them, and removes
each stream's rows of X directly: its events (the fork event included),
snapshots, projector output, outbox entries and positions. Nothing is
appended for it and nothing propagates (decision 14.107, which
revisits the 2026-10-28 ruling that a deletion is an event that propagates
through the policies: its premise, forks that propagate, is gone). Main
is never touched.

A stream whose removal fails is retried under the retry cap, then
dead-lettered (`AngzarrDeadLetter.failed_edition_removal`, the stream's
cover, reason `ANGZARR_REASON_EDITION_REMOVAL_FAILED`) and alerted.
DeleteEdition answers once every stream is removed or so dead-lettered.

Once a stream's rows are removed, a later input to it in X is refused by
the not-forked rule (§2). Work in flight in X while it is deleted may
reach a removed stream and is refused the same way; an edition is
deleted when its experiment is done. Only ForkStream brings the name back.

## 5. The administration RPCs

EditionAdminService's RPC behaviour (moved from
`proto/io/angzarr/transport/distributed/v1/meta.proto`'s comments,
decision 14.109). What an edition is, and its summary, are core's
(io/angzarr/v1/meta.proto; decision 14.64).

Every edition operation is authorised as an operator action from the
call's credentials, and who performed one goes to the deployment's
security log, never into the data
([identity-and-streams.md](identity-and-streams.md) §8). Nothing here
writes to, records in or indexes against main (§7), and main can be
neither forked into nor deleted (moved from
`proto/io/angzarr/v1/meta.proto`'s header, decision 14.109).
ForkStream forks one stream into an edition at the sequence the request
states (fork_sequence): it appends EditionCreated at that sequence to
(the stream's domain, edition, root), creating the edition if no fork
event of it exists yet (§1). Every stream an edition holds is forked
this way: there is no automatic propagation, and an input in the edition
to a stream not forked is refused ANGZARR_REASON_EDITION_NOT_FORKED (§2;
decision 14.107). It answers the fork event's EventRef.

The request's stream is named in the edition to create or extend:
domain, root, and edition (required, non-empty). Its main version is
forked. The fork is per stream (one domain and root): there is no global
position to fork at and no cross-stream snapshot (decisions 14.35 and
14.36). The fork point is always stated by the caller (decision 14.36):
the sequence the EditionCreated is appended at, which is its own fork
point (decision 14.86). Main is authoritative and is never written for
it: the fork is the edition's alone. 0 is a valid fork at the start of
the stream; there is no "head when unset". Any sequence at or below
main's head (main's next sequence for the stream) is taken; one above it
is refused ABORTED (the store's conflict, the status for a failed
test-and-set), writing nothing.

```text
  INVALID_ARGUMENT     edition is empty or unset (main is unnamed and
                       cannot be forked into), or the cover names no
                       domain or root;
  ALREADY_EXISTS       the stream is already forked in this edition;
  ABORTED              fork_sequence is above main's head for the
                       stream.
```

ListEditions lists the editions: a query over the edition stores' fork
events (no record is kept anywhere else, and main is never read for it).

DeleteEdition deletes an edition by enumeration, as §4 describes
(decision 14.107): it finds every stream forked in it by its
EditionCreated, as ListEditions does, and removes each stream's rows of
the edition directly; it answers once every stream is removed or so
dead-lettered. A later input in the edition is refused by the not-forked
rule; only ForkStream brings the name back. Main is never touched. The
name is required and non-empty.

```text
  INVALID_ARGUMENT  name is empty (a name is required; main is unnamed
                    and can never be deleted);
  NOT_FOUND         the edition is unknown (no stream of it is
                    forked).
```

## 6. An edition is core, and part of stream identity

Moved from `proto/io/angzarr/v1/types.proto`'s comments on Cover.edition
and its `editions` region (decision 14.109).

An edition is the NAME of the timeline a stream belongs to (Cover.edition).
Editions are core, whatever the transport: the angzarr-embedded kernel and
core's coordinator alike keep and read editions (the angzarr system
layer); only their administration RPCs are the distributed transport's.

The main timeline is unset (absent). The main timeline has no name; there
is no magic value for it. A set edition is a named, non-main edition and
must be non-empty: a set empty string is malformed and refused
INVALID_ARGUMENT wherever a Cover is accepted. Editions are part of stream
identity on the wire (in Cover and in EventRef.stream), so an edition's
events can never be mistaken for, or copied as, main-timeline events.

A fork above main's head is a conflict (decision 14.36; §1). The
not-forked refusal (§2) is decisions 14.65 and 14.107.

## 7. Main knows nothing

An edition's forks are FRAMEWORK META-EVENTS in the edition's own streams
(decision 14.32): EditionCreated, an EventPage's meta_event arm (§3).
Business handlers never see them.

Main knows nothing (the owner's invariant). Every datum and message of an
edition's lifecycle lives in the edition's own streams (D, X, R), in the
edition's configured store, and every row of X carries X in its key.
Nothing is appended to, recorded in, indexed against or read from main's
streams for an edition's lifecycle, except that a creation READS main's
head (its fork sequence) and a stream in X reads main's events below it.
Listing editions and checking that one exists query X's own creation
events. X's outbox entries, positions and deliveries are X's, kept apart
from main's. Main's coordinators, projectors and readers behave exactly as
if no edition existed: creating and deleting an edition leaves main's
streams, outbox and positions byte-for-byte unchanged.

## 8. What-if execution

A what-if is a command run in an edition: send an ordinary CommandBook
whose cover names the edition. There is no separate speculative RPC.
Reactions (policies) stay in the edition of the event they react to, and
so do the commands and refusal facts they send.

## 9. Storage and lifetime

Where an edition's rows live is configuration (an edition name, or
pattern, mapped to a store; otherwise the configured default edition
store), which may be in memory, redis, another persistent store, or the
existing production database (the edition is part of the storage key, and
the edition column stays in every database schema so the existing
database can host editions). Nothing is recorded about placement: there is
no record. Placement never changes the wire contract. Projector output
follows the edition's storage: an in-memory edition's projections are
kept in memory.

Lifetime follows the backend: memory lives as long as the process, redis
as long as its TTL, a database persists.
EditionAdminService.DeleteEdition (§5) deletes a named edition
explicitly: every row tagged with it, by enumeration of its forked streams
(§4). It does not wait for work in flight: such work that reaches a removed
stream is refused by the not-forked rule (§2; decision 14.107). Main
cannot be named, so it can never be deleted.
