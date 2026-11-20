# The command pipeline: handling, validation, concurrency and outcomes

**Status:** normative (decisions 1.4, 14.31, 14.36, 14.37, 14.39, 14.40, 14.46, 14.47, 14.69, 14.84, 14.85; as amended by decisions 14.79, 14.91 to 14.94, 14.98, 14.100, 14.101 and 14.105). Moved from `proto/io/angzarr/v1/types.proto`'s comments (decision 14.109). Covers how one command or fact is processed, in every runtime and every mode: the pipeline, what is malformed, the per-stream optimistic append and race re-runs, the expected sequence, dispatch by body arm and type, and what the runtime answers. The messages are `types.proto`'s `concurrency`, `handling`, `command_page`, `command_book`, `reaction_delivery` and `outcome` regions. The command modes and status codes are [command-handling.md](command-handling.md); identity and deduplication are [identity-and-streams.md](identity-and-streams.md).

## 1. Handling

Handling is how a client asks for one command to be treated. It is never
persisted (EventMeta records what was decided, not how the command was
handled), and identity, business data and provenance never live there.

How much of the processing the caller waits for is NOT handling: it is a
call-level choice, made by which coordinator RPC the caller uses (Handle,
HandleAsync or HandleSync; see [command-handling.md](command-handling.md)
§1).

Handling is the Command arm's alone (Command.handling; decision 14.79,
ruled 2026-11-02; it was CommandBook.handling): a Fact has no field for it, and
neither has a ReactionDelivery. A reaction is delivered by the one
framework-only RPC, Deliver. Command.handling is as sent before the
coordinator, resolved after it.

A process manager is a domain (decision 14.31): Handling applies to the
commands addressed to it exactly as to an aggregate's.

## 2. The pipeline

The coordinator's order, NORMATIVE in every runtime and every mode:

```text
  1. validate      the malformed list (§3); refuse before anything is
                   minted, looked up or stored;
  2. assign ids    mint or derive command_id, and set an absent
                   correlation_id (identity-and-streams.md §6);
  3. load, then    load the stream (snapshot and events, its head)
     deduplicate   FIRST, then look up (stream, command_id); a hit is
                   answered DUPLICATE with the stored events, and
                   nothing below runs. The loaded pages exclude those
                   the snapshot covers (decision 14.40), and the pages
                   and the input's payload are upcast through the
                   component's upcaster sidecar (decision 14.39; see
                   docs/design/upcasting.md) before anything below
                   judges them;
  4. check         a command whose Handling sets expected_sequence
                   other than the head step 3 loaded is refused
                   ExpectedSequenceMismatch (§5; decision 14.94), and
                   the handler is never called;
  5. business code CommandHandlerService.Handle, for a command and a
                   fact alike (decision 14.98; the client library folds
                   the delivered state and dispatches by type), then the
                   append at the head step 3 loaded. A process manager's
                   business code is the same service (a PM is a domain;
                   decision 14.31).
```

The load comes before the lookup: under READ COMMITTED, a lookup first
could miss an original delivery that commits before the load, and the
retry would append after the original's events with no conflict (applied
twice). Loading first, a commit after the load is either seen by the
lookup or fails this delivery's append on its loaded head.

A HandleAsync command refused by business code has no caller to answer:
it is dead-lettered with its typed refusal (AngzarrDeadLetter's refusal
arm) and alerted (decisions 14.47, 14.101); so is one refused at step 4.
An append that loses an optimistic race re-runs from step 3, under the
race re-run cap (§4). On that re-run a command WITH an expected sequence
is stale (the head has moved past it) and is refused at step 4; one
without re-runs on the new head as before. Deduplication (step 3) comes
first, so a retry of an applied command is answered DUPLICATE whatever
its expected sequence.

## 3. Validation

Violations are refused loudly, never silently ignored. Each of these is
malformed, refused at step 1, before deduplication or business code:

- a policy's output with no root, whatever its target (INTERNAL,
  google.rpc.ErrorInfo reason `ANGZARR_REASON_POLICY_COMMAND_NO_ROOT`,
  metadata domain and command_type; decision 14.36, as amended), refused
  by the policy's coordinator;
- a client's Fact without origin, or with an empty external_id, or with a
  command_id other than its derivation
  ([identity-and-streams.md](identity-and-streams.md) §6.5);
- a set UUID that is not 16 bytes, or a set empty Cover.edition.

A client's malformed command is answered INVALID_ARGUMENT, by every
coordinator RPC (HandleAsync included: it validates before enqueueing),
and an input in an edition to a stream with no fork there (an edition
never created or deleted included) FAILED_PRECONDITION
ANGZARR_REASON_EDITION_NOT_FORKED, checked at load, before business code
(see [edition-meta-events.md](edition-meta-events.md) §2; decision
14.107). A reaction has no caller
to answer, so a malformed one is dead-lettered as a reactor bug (and
alerted), never delivered.

A command refused at validation never reaches the DLQ with a minted id:
it has none ([dead-letters.md](dead-letters.md) §2).

## 4. Concurrency

Concurrency (decision 14.92; the owner's decision 47: "does the
coordinator need to care, at all, about conflicts, or should we just
delegate it?" ... "and let the business logic handle it"). The
coordinator has NO conflict-resolution concept: no resolution, no
conflict window, no conflict units, no conflict report.
ConflictResolution, StateOptions, the (state) and (conflict) options and
ConflictUnit are deleted.

What stays, and why it is not conflict handling:

- The store's per-stream optimistic append. The coordinator loads a
  stream (its snapshot, its pages, its head) and appends the decision's
  events AT THE HEAD IT LOADED. A handler cannot see concurrent writers,
  so write atomicity cannot be delegated to it.
- A lost race is re-run on the new head by the coordinator (the kernel
  owns retries; the owner's ruling of 2026-10-30), so the handler always
  decides on current state. Re-runs are capped by the race re-run cap (a
  count of runs, the first included, default 10, at least 1; decision
  14.84), with exponential backoff and jitter between them
  ([command-handling.md](command-handling.md) §4; decision 14.46). At the
  cap nothing is persisted; a waiting caller is answered INTERNAL
  `ANGZARR_REASON_RETRY_CAP_EXHAUSTED` and nothing is dead-lettered, and
  work with no caller waiting is dead-lettered and alerted (a fact,
  dead-lettered and its sender answered INTERNAL
  `ANGZARR_REASON_FACT_DEAD_LETTERED`; decisions 14.85, 14.100). Ordering
  is per stream: no other stream's writes matter.

## 5. The expected sequence

A client's expected sequence (Handling.expected_sequence: "I decided
having seen version N", the stream's next_sequence the client decided
against) is the one thing the coordinator checks of staleness (decision
14.94; the owner's ruling, amending 14.93): set, and not the head
it loaded, the command is refused ExpectedSequenceMismatch before the
handler is called (pipeline step 4), behind or ahead alike. There is no
mode and no resolution: a command with no expected sequence (unset: the
client stated none) is decided on the current state, and one with it is
either at the head or refused. The coordinator never stamps it.

ExpectedSequenceMismatch is the framework's one refusal (decisions 14.93
and 14.94): the client's expected sequence is not the stream's head. It
is raised by the COORDINATOR, never by business code, and listed in no
command's refuses. FAILED_PRECONDITION (business, fatal, decision 14.37:
the caller re-reads and decides again), by its (refusal_status) option.
On the wire it travels as any typed refusal: reason
`ANGZARR_REASON_COMMAND_REFUSED`, refusal_type
io.angzarr.v1.ExpectedSequenceMismatch, the object in the status details;
a HandleAsync command so refused is dead-lettered with it as
AngzarrDeadLetter's refusal arm. Behind and ahead are one refusal: either
way the client decided against a version that is not the head.

## 6. Dispatch by arm and type

A CommandPage is the one command of a CommandBook: its identity
(command_id, correlation_id; [identity-and-streams.md](identity-and-streams.md)
§6) and a body that is either a decision-requesting Command, with how it
is to be handled, or an already-happened Fact, with where it came from
(decision 14.79).

Reflective dispatch. The framework picks the pipeline from which body arm
is set (the arm's message type): a Command goes through decide
(fallible: it may be rejected), a Fact through ingest (infallible).
Within the pipeline the payload's type URL picks the handler, after the
coordinator, through the component's upcaster sidecar, has brought an
old payload type up to the current one (decision 14.39; see
[upcasting.md](upcasting.md)); Command and Fact payloads alike are
upcast, and the client library never sees an old type. A payload whose
type URL reaches no handler is refused by the client library INTERNAL (a
bug: decision 14.37) with reason `ANGZARR_REASON_UNKNOWN_COMMAND_TYPE`
(`ANGZARR_REASON_NO_FACT_HANDLER` for a fact), which is also the status
message (decision 14.37: a key, never text), naming the type it was given
as ErrorInfo metadata "type_url". The coordinator answers its caller with
that status, its ErrorInfo metadata "type_url" holding the type URL as
sent and "upcast_type_url" the type URL the sidecar returned (the sent
one when no rule applies).

On the wire the arm is the fact marker; in code, one handler attribute
(#[handles]) serves both kinds, and the message's option, (command) or
(fact), is the declaration (decision 14.98): the router refuses an
arm that does not match it. There is no proto flag for facts. A process
manager's stream takes both arms, like any domain's (decision 14.31).

A client's command or fact rides a CommandPage; a policy's output and a
refusal fact ride a ReactionDelivery (§10), whose body is a oneof of the
two arms and whose causation is the trigger. A policy emits what its
destination declares (decision 14.69): a command for a declared command
type, a fact for a declared fact type, the arm chosen by its generated
code from the destination's declaration, (command) or (fact); one the
destination does not declare is refused by its router, as above. A
policy also delivers the refusal fact of a refused command (the domestic
fact its callback translates the refusal into; the one refusal path,
decision 46 #5), to the exact stream of its trigger (decision 14.31,
amending 2.2; PolicyService in [policies.md](policies.md) §3).

## 7. Commands and facts

### 7.1 Commands

A command proper is a request for the aggregate to decide. decide may
emit events or reject it. A rejected command writes nothing, so the same
command_id may be retried.

Commands may be upcast: the coordinator runs the payload through the same
upcaster chain as for events, by type URL, in the component's upcaster
sidecar, before dispatch (decision 14.39; see
[upcasting.md](upcasting.md), which also explains why that is
discouraged).

### 7.2 Facts

A fact is something that already happened outside the system (a webhook,
an integration), delivered through the command coordinator like any
command (Handle, HandleAsync or HandleSync).

Facts are upcast like commands: the coordinator runs the payload through
the same upcaster chain, by type URL, in the component's upcaster
sidecar, before dispatch (decision 14.39; see
[upcasting.md](upcasting.md)).

Fact handlers are infallible: they record the fact (possibly together
with events that flag it, e.g. a payment received for an unknown order)
and never reject it. A failing fact handler is a bug, not a business
rejection: the fact is dead-lettered and alerted, and the sender is
answered INTERNAL `ANGZARR_REASON_FACT_DEAD_LETTERED`, non-retryable
(decision 14.100; the owner: "if retrying senders repark, it's a
logic bug"). The framework deduplicates on the command_id derived from
origin.external_id, per addressed stream, before the handler runs; a
dead-lettered fact wrote nothing, so a DLQ replay of it runs its handler
again. A fact that loses a race at its write to another write to the
same stream is re-run on the new head under the race re-run cap, and one
that reaches the cap is dead-lettered the same way (reason
`ANGZARR_REASON_RETRY_CAP_EXHAUSTED`, alerted, its sender answered
INTERNAL `ANGZARR_REASON_FACT_DEAD_LETTERED`; decisions 14.46, 14.100).

A Fact has no Handling to set: it is appended at the head the coordinator
loaded, like any input (§4).

## 8. The delivery outcome

DeliveryOutcome is what the runtime did with one delivery of a command:
the result of its handling, NEVER persisted. Nothing of it is written to
any stream, and replaying a stream cannot reproduce it. The command's
business result is its events. A distributed coordinator answers it
beside the events
(io.angzarr.transport.distributed.v1.CommandResult.delivery and
CommandSyncResult.delivery; decision 14.105), and the
angzarr-embedded kernel answers the same pair, events and delivery.
Deduplication is [identity-and-streams.md](identity-and-streams.md) §7.

```text
  APPLIED    business code ran and the result committed: the events are
             new (possibly none; a zero-event decision leaves nothing to
             deduplicate against, so a redelivery is APPLIED again).
  DUPLICATE  the addressed stream already held events with this
             command_id: business code did not run, and the events are
             those, re-read from the stream.
```

A fact that could not be recorded is no outcome either: it is
dead-lettered, and its sender answered INTERNAL
`ANGZARR_REASON_FACT_DEAD_LETTERED` (decision 14.100).

A rejection is never an outcome: it is a gRPC error status, and it writes
nothing, so the same command_id may be retried.

## 9. One command per CommandBook

A CommandBook is exactly one client command or fact addressed to one
stream (decision 1.4). A policy's output is a ReactionDelivery instead
(decision 14.79). A CommandBook carries exactly one command, its page.
More than one is unsupported: deduplication, the expected-sequence check,
errors and the outcome are all per command. A caller with several
commands sends several CommandBooks (a client library may batch such
calls on its side). (EventBooks, by contrast, group the pages of one
stream under a shared Cover.) CommandBook is the request itself: the
coordinator's Handle, HandleAsync and HandleSync take it directly, with
no request wrapper.

## 10. Reaction delivery

A ReactionDelivery is one output of a policy, or a refusal fact, as its
coordinator delivers it to the destination's coordinator (decision 14.79,
ruled 2026-11-02; owner ruling Q4 on decision 46). It is built only by a policy's
coordinator, from the policy's answer (io.angzarr.handler.v1.Output,
TranslateResponse) and its trigger, and taken only by the framework-only
Deliver RPC (the angzarr-embedded kernel passes it in process). A client
cannot send one.

It carries no Handling (no expected sequence: a reactor never saw the
destination's state). It carries no fact origin: the destination derives
a fact's, external_id the command_id's canonical text and description
naming the payload's type and `component`.

Its cover is the destination stream: the policy's output_domain and the
output's root in the trigger's edition; for a refusal fact, the trigger's
own stream. Its body is the command or fact, as the policy answered it,
in the arm of its kind (Output's arm; a refusal fact is always the fact
arm): a oneof, not a flag (decision 14.91). Neither arm is core's
Command or Fact: a reaction carries no Handling, and its fact's origin is
derived. Its command_id is derived from (trigger, policy, index) for an
output ([identity-and-streams.md](identity-and-streams.md) §3.2); the
refused command's for a refusal fact. Its correlation_id is the
trigger's. Its causation is the trigger, the event the policy reacted to:
the reaction command_id is derived from it, and it is NOT persisted on
the events the delivery produces (their causation is the command;
[identity-and-streams.md](identity-and-streams.md) §6.3). Its component
is the policy's registered component name: the fact origin's
description, and the reacting component of the derived id.
