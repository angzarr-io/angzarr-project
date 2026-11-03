# Editions: forks, the not-forked rule and deletion

**Status:** normative (decisions 14.32, 14.36, 14.86; DRAFT decisions 14.106 and 14.107 pending review). The messages are `io/angzarr/v1/types.proto`'s `meta_events` region (`MetaEvent`, `EditionCreated`); the administration RPCs are `io/angzarr/transport/distributed/v1/meta.proto`'s `EditionAdminService`.

**What editions are for.** An edition's main use is operations research
and experimenting: a what-if run of real commands against a fork of real
streams. It is not restricted to that, and it may hold real data. An
edition is a deliberately crafted system, so explicit creation is the
rule: whoever builds one decides which streams it holds, and forks each
with ForkStream (the owner, 2026-11-02: "the explicit creation is
absolutely permissable because they're crafted systems"; decision 14.107,
DRAFT).

## 1. A fork is explicit, per stream

An edition X is a set of per-stream forks and nothing else: there is no
edition registry and no separate metadata store. A stream (D, X, R) exists
in X from its fork, and every fork is made explicitly, by
`EditionAdminService.ForkStream`, at the `fork_sequence` the caller states
(decision 14.107, DRAFT: there is no automatic propagation).

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
meta_event }` (decision 14.106, DRAFT). `EditionCreated` is the one
meta-event (decision 14.107, DRAFT).

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
appended for it and nothing propagates (decision 14.107, DRAFT, which
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
