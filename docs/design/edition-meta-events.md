# Edition meta-events: creation, propagation and deletion

**Status:** normative (decisions 14.32, 14.36, 14.86; DRAFT decision 14.106 pending review). Moved from `proto/io/angzarr/v1/meta/events.proto`, deleted when meta-events became a type (decision 14.106, DRAFT). The messages are `io/angzarr/v1/types.proto`'s `meta_events` region: `MetaEvent`, `EditionCreated`, `EditionDeleted`.

## 1. What a meta-event is

A meta-event is a real event, appended to a stream and stamped like any
other (a framework-derived command_id of its own, never that of the
command whose arrival made it), but it is the framework's, not a domain's.
It is told apart by TYPE, never by a type URL: an EventPage's body is
`oneof { google.protobuf.Any event; MetaEvent meta_event }`, and a
meta-event is the `meta_event` arm (decision 14.106, DRAFT, retiring the
`/io.angzarr.v1.meta.*` type-URL convention).

- Stores and the angzarr system layer act on the `meta_event` arm: a store
  reads an edition stream through its EditionCreated; the system layer
  removes a stream's edition rows once its EditionDeleted has propagated.
- Business handlers NEVER see one: the client library hands business code
  only the `event` arm. No applier, policy, process manager or projector
  handler receives a meta-event, and a book a handler is given holds only
  event pages.
- No input carries one. A CommandPage has no meta arm, so a meta-event
  cannot arrive from outside the system layer; a command whose payload
  happens to be an EditionCreated or EditionDeleted is an ordinary command
  of an unknown type.
- It travels on the same data flow as any event: a policy's step that
  reacts to an event in edition X carries X's meta-events onward to the
  streams it reaches (the angzarr system layer does this for core's
  coordinator and for the angzarr-embedded kernel, whose in-process chain
  of committed steps carries them the same way).

Only meta-events something needs are defined.

## 2. EditionCreated: creation and propagation

An edition's creation, per stream (Cover.edition). The first event of X's
version of a stream (D, X, R), appended at its FORK SEQUENCE: its own
EventPage.sequence IS the fork point (decision 14.86), stated nowhere
else. (D, X, R) reads main's events below it, then X's own. The edition is
the page's cover's; the event does not repeat it (decision 14.106, DRAFT).

The parent is authoritative, period (the owner, 2026-11-02: "the parent
should never have any concept of forks/branches. It is authoritative,
period."): main's stream holds nothing of any edition, records no fork,
and is never written, read for, or held back by an edition's lifecycle;
only the edition's own streams know they fork it. A store accepts any
stated sequence at or below main's head for that stream (the sequence
main's version would use next) and refuses one above it as a conflict; it
never moves a fork to the head. The fork point is per stream: no
cross-stream snapshot is promised.

Its source is a oneof (decision 14.106, DRAFT, replacing the
presence-coded `propagated_from` and `forked_by`):

- **`origin` (OriginFork):** ForkStream created it
  (transport/distributed/v1/meta.proto, at `fork_sequence`). Only an
  origin creation brings a deleted edition's name back.
- **`propagated` (PropagatedFork):** a policy's command or fact in X
  reached a stream with no EditionCreated in X. That arrival is the
  propagation: the angzarr system layer (shared code in angzarr-core,
  called by the stream's coordinator or by the angzarr-embedded kernel)
  reads that one stream's main head and appends EditionCreated at it, so
  its own sequence is that head (policies never handle sequences; if main
  appends in between, the fork still lands where it was appended), with
  `from` the EditionCreated of the stream the policy reacted to and
  `forked_by` the arriving input's command_id, and then hands the input to
  the router as an ordinary input in X. The router never sees an
  EditionCreated.

An arrival in an edition that is deleted, or being deleted, is refused
NOT_FOUND before the router is called. Concurrent arrivals race on the
append like any two writes; the loser finds the stream created and appends
no second one.

## 3. EditionDeleted: deletion

An edition's deletion, per stream (decision 14.32, the owner's rulings of
2026-10-28: "delete edition / EditionDeleted needs to be an EVENT, to
propagate via policies to other domains"; "it needs to exist in its
domains"). Per stream (D, X, R), in this order:

1. **RECORDED:** DeleteEdition appends EditionDeleted to X's origin
   streams; each other stream the deletion reaches records its own, in its
   own domain, in sequence after its earlier work.
2. **PROPAGATED:** the system layer carries it onward along the streams
   that domain's policies reached in X, writing each one's own
   EditionDeleted (never as a policy's command: no policy sees it).
3. **REMOVED:** only after it has propagated onward (the system layer's
   onward writes and outbox entries for it have completed), the stream's
   rows tagged X are removed, this event included. Nothing remains.

Who owns it (decision 14.32, amended; placed by 14.36): the ANGZARR SYSTEM
LAYER, transport-free shared system code in angzarr-core that core's
coordinator and the angzarr-embedded kernel call around the router, never
the router, which sees no meta-event. It writes EditionDeleted in X's
origin stream(s), then propagates it along the streams its policies
reached in X, as its own write in each; a stream with nothing of X left is
skipped, and nothing is created or forked there. It is not carried as a
policy command.

Main is never written. A stream in X that the deletion cannot reach
through the policy flows keeps its rows and stays visible in
ListEditions. After deletion, a later arrival in X (a policy command, or
a step's position on a removed stream) is REFUSED NOT_FOUND: X does not
exist, and the arrival re-creates neither the stream nor the edition. X is
known to be deleted, or being deleted, while any stream of it holds an
EditionDeleted, and not to exist once no EditionCreated of it remains.
