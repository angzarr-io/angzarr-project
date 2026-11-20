# State and concurrency: a developer guide

This guide is for anyone writing an aggregate or process manager on
angzarr (or angzarr-embedded). It explains what your handler sees, why it
always decides on the current state, what happens when two writers race
for one stream, and how your business code deals with "conflicts" itself.
Its last sections cover versioning commands and re-running reactors after
a bug fix.

The normative text lives in the design docs and the protos:
- `docs/design/pipeline.md` §2 (the pipeline), §4 (concurrency) and §5
  (the expected sequence);
- `docs/design/command-handling.md` §3 (status codes), §4 (the race
  re-run cap) and §9 (Emit);
- `docs/design/handler-contract.md` §4 to §7 (what a handler is handed and
  answers);
- `docs/design/snapshots.md` (where state snapshots come from and when one
  is offered);
- `proto/io/angzarr/v1/types.proto`, the `concurrency` region
  (`ExpectedSequenceMismatch`) and the `handling` region (`Handling`), and
  `proto/io/angzarr/handler/v1/command_handler.proto` (`HandleRequest`,
  `HandleResponse`).

Where this guide and those disagree, they win. Report the disagreement.

**Status.** This describes the spec as ruled on 2026-11-02 (decision log
entries 14.84, 14.85, 14.92 to 14.95, 14.98, 14.100, 14.104 and 14.109, in
`docs/design/audit-meta/decision-log.md`). Earlier versions of this guide
described conflict resolutions (STRICT, AGGREGATE_HANDLES, COMMUTATIVE), a
`(state)` option and `(conflict)` units. All of that is deleted (decision
47, entry 14.92): the coordinator has no conflict concept.

## Contents

1. [What your handler is handed](#1-what-your-handler-is-handed)
2. [Why the handler always decides on current state](#2-why-the-handler-always-decides-on-current-state)
3. [Racing writers and the race re-run cap](#3-racing-writers-and-the-race-re-run-cap)
4. [The client's expected sequence](#4-the-clients-expected-sequence)
5. ["Conflicts" are business rules](#5-conflicts-are-business-rules)
6. [What your handler returns: Emit, the state and the rules version](#6-what-your-handler-returns-emit-the-state-and-the-rules-version)
7. [Snapshots](#7-snapshots)
8. [Versioning commands](#8-versioning-commands)
9. [Re-running reactors](#9-re-running-reactors)

## 1. What your handler is handed

Your component's business process serves one call,
`CommandHandlerService.Handle`, for commands and facts alike (decision
14.98). Its request, `HandleRequest`, carries:

- `input`: the `CommandBook` (its cover, the stream; its page, with the
  `command_id`, the `correlation_id` and a body that is either the Command
  arm, with its `Handling` as the client sent it, or the Fact arm, with
  its origin);
- `history`: the stream as the coordinator loaded it, a validated snapshot
  (if one is offered) and every page after it, and `next_sequence`, the
  head;
- `recorded_at`, when the input was accepted;
- `causation`, the trigger, for a policy's output or a refusal fact only.

Before `Handle` is called, the coordinator has run pipeline steps 1 to 4
(`docs/design/pipeline.md` §2): validated the input, assigned its ids,
loaded the stream and deduplicated (a `command_id` the stream already
holds is answered DUPLICATE and your handler never runs), and checked the
expected sequence (§4 below). Every payload is in its current shape: the
coordinator upcast it through your component's upcaster sidecar.

The client library decodes the snapshot's state, folds every delivered
page into it in order, and calls your handler with the typed command or
fact and the state. You write no fold loop and no envelope checks.

## 2. Why the handler always decides on current state

The coordinator appends your answer's events **at the head it loaded**,
using the store's per-stream optimistic append. If another write to the
same stream landed between the load and the append, the append fails, and
the coordinator **re-runs the whole input on the new head**: it loads
again, deduplicates again, and calls your handler again with the moved
state (`docs/design/pipeline.md` §4).

So your handler never sees a stale view of its own stream. Whatever it
decides, it decides against the state it is about to append to. It cannot
see concurrent writers itself, which is why the atomicity of the write is
the coordinator's job and never yours.

Ordering is per stream only. Writes to other streams never cause a re-run,
and nothing orders one stream's events against another's.

## 3. Racing writers and the race re-run cap

Re-runs are bounded by the **race re-run cap**: a count of runs, the first
included, default 10, configurable, at least 1 (a configuration of 0 is
refused when it is loaded; decision 14.84). The coordinator backs off
exponentially, with jitter, between runs (`docs/design/command-handling.md`
§4). There is no opt-out.

When every run loses its race until the cap, nothing is persisted, and
what happens next depends on who is waiting:

| Input | Caller | At the cap |
|---|---|---|
| A command | waiting (`Handle`, `HandleSync`) | answered INTERNAL `ANGZARR_REASON_RETRY_CAP_EXHAUSTED` (args `stream`, `attempts`, `cap`); **not** dead-lettered, because the caller holds it (14.85) |
| A command | none (`HandleAsync`, a policy's reaction) | dead-lettered with reason `ANGZARR_REASON_RETRY_CAP_EXHAUSTED` and alerted; a policy step then follows its `on_policy_bug` setting |
| A fact | waiting or not | dead-lettered with reason `ANGZARR_REASON_RETRY_CAP_EXHAUSTED` and alerted, and its sender answered INTERNAL `ANGZARR_REASON_FACT_DEAD_LETTERED`, non-retryable (14.100, 14.109) |

Facts differ from commands because a fact is never refused and nothing
else holds it: the dead letter is where an operator finds it. A sender that
retries a dead-lettered fact has a logic bug; it should not retry.

A race at the cap is rare. If you see it often, one stream is too hot:
split the work across more streams (more roots), not more retries.

## 4. The client's expected sequence

A client that wants "only if nothing changed since I looked" sets
`Handling.expected_sequence` on its command: the `next_sequence` it decided
against ("I decided having seen version N"). This is the one staleness
check the coordinator makes (decision 14.94; `docs/design/pipeline.md`
§5):

- **Set, and equal to the head the coordinator loaded:** the command goes
  on to your handler.
- **Set, and not the head** (behind it or ahead of it alike): the
  coordinator refuses it **before your handler runs**, FAILED_PRECONDITION,
  with the framework's one typed refusal,
  `io.angzarr.v1.ExpectedSequenceMismatch { expected, head }`. It travels
  as any typed refusal: reason `ANGZARR_REASON_COMMAND_REFUSED`, metadata
  `refusal_type` = `io.angzarr.v1.ExpectedSequenceMismatch`, the object in
  the status details. Nothing is written; the client re-reads and decides
  again.
- **Unset:** the client stated none, and the command is decided on the
  current state. The coordinator never stamps one in.

Three consequences:

- **Deduplication comes first.** A retry of an applied command is answered
  DUPLICATE, whatever its expected sequence.
- **A race re-run makes it stale.** A command with an expected sequence
  that loses a race at its write is re-run, finds the head moved, and is
  refused `ExpectedSequenceMismatch`. One without re-runs on the new head.
- **No command declares it.** Your commands never list
  `ExpectedSequenceMismatch` in their `refuses`; the coordinator raises it,
  never your code. A `HandleAsync` command so refused is dead-lettered
  with the refusal as the dead letter's refusal arm, and alerted.

Your handler never needs to compare `expected_sequence` itself: by the
time it runs, a set expected sequence equals `history.next_sequence`.

Policies' reactions carry no `Handling` (a reactor never saw the
destination's state), so they are never stale; they are appended at the
head the destination loaded.

## 5. "Conflicts" are business rules

Because your handler always decides on the current state, what used to
be called conflict resolution is ordinary business logic: look at the
state, and either emit events or refuse with a typed refusal your command
declares.

The blackjack table (`proto/io/angzarr/examples/v1/table.proto`, its
Concurrency paragraph) shows the pattern:

- **Two bets on one seat.** Two `PlaceBet` commands for seat 2, prepared
  from the same view, race. The first lands. The second is re-run on the
  state the first left, finds a bet already placed, and the handler
  refuses it `AlreadyBet { seat }`. Two bets on different seats prepared
  from the same view both land: neither handler finds anything wrong.
- **Two actions on one hand.** Of two `Hit`/`Stand`/`DoubleDown` commands
  prepared from the same view, the second is decided on the state the
  first left, and is refused by the rules when it no longer fits
  (`NotYourTurn`, `NoRoundInProgress`).

To do the same in your domain:

1. Decide what "concurrent" means for each command **as a business
   question**: which states make it wrong? Usually it is the same question
   as validation, asked of the current state.
2. Declare one refusal message per reason, each with its status
   (`option (io.angzarr.v1.refusal_status) = …`, required), and list it in
   the command's `refuses` (`docs/design/component-options.md` §10, §11).
   A command whose `refuses` is empty cannot refuse.
3. In the handler, check the state and return the refusal or the events.
4. If a client needs "only if unchanged", it sets `expected_sequence`
   (§4). That is the client's choice, not the handler's.

A handler that wants its caller to re-read and re-decide, without a
business refusal, answers ABORTED under its own key
(`docs/design/command-handling.md` §3). That is a different outcome from a
refusal: a policy's Translate never sees it.

A fact can never be refused. A fact handler records the fact on whatever
the current state is, flagging oddities with events of its own (a payment
received for an unknown order, say).

## 6. What your handler returns: Emit, the state and the rules version

Every command and fact handler returns an `Emit`, in every client library
(`docs/design/command-handling.md` §9): `Emit::of(events)`, a list of
events applied in order, optionally followed by `.then(step)`, a
continuation run on the state with those events folded in. All of it is
one decision: a refusal or a bug anywhere refuses or fails it all, and the
wire carries one event list (`HandleResponse.events`). A step must be
idempotent on its own result, and each library gives a test helper for
that. There is no step cap: a step that always continues never terminates,
which is a handler bug.

The client library fills the rest of `HandleResponse` on every answer:

- `state`: the state with the answer's events folded in. Never set by
  business code.
- `rules_version`: the full version of your business binary, baked in when
  it is built (for example `1.4.2+build.7`), the same value your component
  registered (`ComponentDescriptor.rules_version`). The coordinator stamps
  it onto every event (`EventMeta.rules_version`) and any snapshot written
  from the answer. An answer reporting another version is refused,
  INTERNAL `ANGZARR_REASON_RULES_VERSION_MISMATCH`, and nothing is
  persisted (`docs/design/handler-contract.md` §7). An answer whose state
  is not the registered state type is refused the same way,
  `ANGZARR_REASON_STATE_TYPE_MISMATCH`.

The coordinator wraps each returned event in an `EventPage` under the
input's cover, at the next sequences, with one `EventMeta` for the write.
Your handler cannot choose a cover, a sequence or meta.

## 7. Snapshots

Snapshots are a framework optimisation, never business data
(`docs/design/snapshots.md`). Because the client library returns the state
on every answer, the coordinator can store it as a snapshot whenever its
storage policy says to (by default it keeps the newest only), and offer it
with the next delivery, dropping the pages it covers. Neither side asks for
one, and your handler never checks one.

A snapshot is offered only when both hold (`docs/design/snapshots.md` §3,
§4):

1. its state type equals the `StateDescriptor.type_name` your component
   registered; and
2. its rules version is compatible with the registered one: after
   stripping one leading `v`, both SemVer with equal major.minor; or, when
   either is not SemVer, equal as recorded.

Otherwise the delivery carries no snapshot and every page from 0, and the
client library folds the full history. So a state-schema change or a rules
change never needs a snapshot migration: the next load replays, and the
next snapshot is written under the new version.

Your component's descriptor names the state type
(`StateDescriptor.type_name`, the fully-qualified message name, no type
URL prefix), generated from your state message's `(component)` anchor
(`docs/design/component-descriptors.md` §3). Do not write it by hand.

## 8. Versioning commands

Commands **can** be upcast. Your component's coordinator runs an incoming
command's (or fact's) payload through the same upcaster chain as events,
by type URL, before dispatch, in the component's upcaster sidecar
(`docs/design/upcasting.md` §3). Your business code, and the client
library around it, only ever see the current type. A type URL that reaches
no handler after upcasting is refused INTERNAL
(`ANGZARR_REASON_UNKNOWN_COMMAND_TYPE`, or `ANGZARR_REASON_NO_FACT_HANDLER`
for a fact), naming the type URL as sent and the type URL the chain ended
at.

**Prefer not to** (`docs/design/upcasting.md` §4). In order of
preference:

1. **Evolve the command compatibly.** Add fields. In proto3 an absent field
   reads as its default, so old clients keep working. Never renumber or
   retype a field.
2. **Handle both versions in the domain during a transition.** Register a
   handler for the old type URL beside the new one, decide what the old
   command means (a business decision, not a schema one), and delete the
   old handler once the old clients are gone.
3. **Upcast, only as a migration aid with a planned removal.** Command
   upcasting hides stale clients: they keep working, so nothing tells anyone
   to upgrade them. It also adds machinery for data that is never stored.
   When you add one, record the date or release by which it is deleted.

Event upcasting has none of these caveats. Stored events never go away, so
their upcasters are permanent.

## 9. Re-running reactors

You shipped a policy with a bug, fixed it, and released a new build (so a
new `rules_version`, which is the build's version). The events it caused
are wrong. Re-running the reactor will **not** fix them, by design. The
normative text is `docs/design/identity-and-streams.md` §7.4 (Reactor
re-runs); the reasoning is decision 13.4 and
`docs/design/audit-meta/idempotency.md`.

**What deduplicates.** Each command or fact a policy emits gets a derived
id: UUIDv5 of the trigger event, the policy's registered component name
and the output's position in its answer
(`docs/design/identity-and-streams.md` §3.2). Nothing about the policy's
code or `rules_version` goes in. So if you reset the policy's checkpoint
and let it run over triggers it already handled, it emits the same ids,
and every destination, a process manager included, answers DUPLICATE with
the events the first, buggy run produced. Even if the fixed code would now
emit different commands, the re-run changes nothing.

**History is never lost.** Nothing in angzarr overwrites, deletes or
re-sequences an event of the main timeline. The buggy-era events stay in
their streams, and stay readable, with the `rules_version` that produced
them.

**Checkpoint resets are for recovery only**: re-delivering triggers whose
output never made it into the outbox (for example after restoring a
position store). Do not use them to repair.

**How to repair: issue new commands.**
1. Find what to fix. `GetCorrelatedEvents` gives you each affected
   workflow; `EventMeta.rules_version` tells you which events the buggy
   version decided. (Which trigger led to which reaction command is in the
   coordinators' traces, not on the events; see
   `docs/design/queries-and-subscriptions.md` §4.)
2. Decide the correction as a business question. Often it is a
   compensating command ("reverse charge", "reissue reminder"), not "do it
   again": downstream readers may already have acted on the wrong events.
3. Send it as NEW commands, each with a fresh `command_id` (let the SDK or
   coordinator mint it). New ids apply; their events append after the old
   ones, with later sequence numbers, and projections see the correction.
4. Where the fix is "run the corrected reactor over these triggers", use a
   re-drive: a new command whose events the fixed reactor reacts to.
   angzarr will ship standard re-drive commands for this (backlog RD-1);
   until then, define one in your domain.

**Risks.**
- **Assuming a reset repairs.** It does not, silently: every command is
  answered DUPLICATE and the dashboards look healthy. Check that your fix
  produced new events.
- **Repairing twice.** A repair command is an ordinary command: give each
  correction one id and reuse it on retry, or a retried repair applies
  twice.
- **Readers of the old events.** Projections, external sinks and other
  reactors have already seen the buggy events. A correction must make sense
  to them as a new fact, which is why compensating commands are usually
  better than replays.
- **Reaction ids are frozen.** Never rename a policy's registered name to
  "force" new ids: renaming changes every id it derives from then on, so
  any trigger it handles again (a reset, a redelivery not yet in the
  outbox) applies a second time, with no record of why.
