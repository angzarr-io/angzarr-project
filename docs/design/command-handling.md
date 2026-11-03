# Command handling: modes, the pipeline's outcomes and status codes

**Status:** normative (decisions 14.37, 14.45 to 14.47, 14.51, 14.64; as amended by the DRAFT decisions 14.78 to 14.102 and 14.104 pending review). Moved from `proto/io/angzarr/v1/command_handler.proto`, which defined no message (decision 14.103, DRAFT). The services are `io.angzarr.component.v1.CommandHandlerService` and `io.angzarr.transport.distributed.v1.CommandHandlerCoordinatorService`; the pipeline is `types.proto`'s Handling region.

What a command handler answers, and how every runtime handles a command.
The handler's service is the component contract's
(io.angzarr.component.v1.CommandHandlerService,
io/angzarr/component/v1/command_handler.proto); the coordinator's RPCs
are the distributed transport's
(io.angzarr.transport.distributed.v1.CommandHandlerCoordinatorService,
io/angzarr/transport/distributed/v1/command_handler.proto). The
pipeline, the command modes and the status codes below are every
runtime's: core's coordinator and the angzarr-embedded kernel alike
(decision 14.64).

What the business logic answers is the handler layer's
(io.angzarr.handler.v1.HandleResponse,
io/angzarr/handler/v1/command_handler.proto; decision 14.78, DRAFT).

CommandHandlerCoordinatorService (the distributed transport's) and the
angzarr-embedded kernel: the entry points for commands and facts into a
domain's aggregates, for clients and framework components alike.
(CommandHandlerService, the component contract's, is the business-logic
service they call.)

## 1. Command modes

How much of a command's processing the caller waits for is
a call-level choice, never part of the command: one RPC per mode.

```text
  Handle       DECISION  Accept or reject synchronously; returns the
                         persisted events. Projectors and reactions run
                         asynchronously.
  HandleAsync  ASYNC     Validate, assign ids, enqueue and return. Nothing
                         about the decision comes back.
  HandleSync   SIMPLE    As DECISION, and also waits for the synchronous
                         projectors; their results come back in
                         CommandResponse.outcome.projections.
```

Impact ordering (lowest to highest): ASYNC < DECISION < SIMPLE.

No mode waits for reactions. Policies always run asynchronously, after the
command's events are persisted; the commands and facts policies emit (to
aggregates and process managers alike), and their refusal facts, are
separate inputs with their own outcomes (a process manager reacts to nothing
directly and emits no commands; decision 14.31). Every mode
publishes the persisted events downstream: there is no mode that writes
silently, so replay, migration and recovery tooling either lets reactions
run or rebuilds projections afterwards.

## 2. The pipeline and deduplication

Every mode follows the one pipeline (types.proto, Handling: validate,
assign ids, load and deduplicate, business code and the append) and refuses a
malformed command loudly, with the codes listed there, never ignoring the
offending field.

Deduplication is the same in every mode (types.proto, command_identity
business code runs; a duplicate is answered from the stored events. A
client Command without a command_id gets a minted UUIDv7, before
enqueueing in the case of HandleAsync, so redelivery from the queue (and
a DLQ replay) is deduplicated; a CALLER's own retry is deduplicated only
when the caller supplied the command_id and reuses it.

## 3. Status codes

One set, used by every coordinator and by every framework
retry loop (reaction delivery, the transient outbox, asynchronous
commands, projector retries). The status alone decides an error's class,
one of four (decision 14.37):
```text
  Business, fatal: FAILED_PRECONDITION, INVALID_ARGUMENT, NOT_FOUND,
              ALREADY_EXISTS, OUT_OF_RANGE, PERMISSION_DENIED (among
              them a field or route reserved for framework components;
              see entry_points). Final: never retried; a refused policy
              command reaches the policy's Translate
              (docs/design/policies.md §3); a refused HandleAsync command, with no caller
              to answer, is dead-lettered with its typed refusal
              (AngzarrDeadLetter's refusal arm; decision 14.101), and
              alerted. A handler answers
              a business rejection as this gRPC status, its typed
              refusal in the details (decision 14.95, DRAFT, reversing
              decision 46's Q2), and the coordinator passes it on.
  Business, immediate return: ABORTED, "re-read and re-decide": a
              handler's own choice, ABORTED under its own key. The
              coordinator has no conflict
              of its own to answer (decision 14.92, DRAFT). Returned at once to an outside caller, who re-reads
              and decides again; for a policy step the runtime is the
              caller, reloading and re-running the step under the capped
              backoff below, then dead-lettering it and alerting. Never a
              policy's Translate.
  Bug, fatal: INTERNAL, UNKNOWN, DATA_LOSS (a handler bug is INTERNAL
              ANGZARR_REASON_UNHANDLED_HANDLER_ERROR, its own key the cause). Never
              retried; alerted and dead-lettered at once, and never a
              policy's Translate.
  Bug, retryable: UNAVAILABLE, DEADLINE_EXCEEDED, RESOURCE_EXHAUSTED
              (a handler's retryable bug picks one: ANGZARR_REASON_UNHANDLED_HANDLER_ERROR,
              its own key the cause), UNIMPLEMENTED and every other code.
              Retried, on by default, with exponential backoff and jitter
              up to a cap (the scale, the jitter factor and the cap are
              configuration), then dead-lettered and alerted; never a
              policy's Translate. Every retryable failure carries a key
              (reasons.proto; decision 14.51), so whoever gives up when
              the retries are spent reports it: the dead letter's
              reason, or a caller's last answer.
```
The retryable statuses are not interchangeable: UNAVAILABLE means resend;
DEADLINE_EXCEEDED means resend only if the call is idempotent (a command
is, by its command_id); RESOURCE_EXHAUSTED means wait longer before
resending; ABORTED means re-read and re-decide. A policy step that
reaches the cap, or fails as a fatal bug, moves or keeps the policy's
position as its bug setting says (on_policy_bug).
## 4. The race re-run cap

One cap bounds the coordinator's own re-runs of an input that loses a
race at its write to another write to the same stream: the race re-run
cap, configuration, a count of runs (the first included, default 10; at
least 1, and a configuration of 0 is refused when it is loaded: decision
14.84, DRAFT). Every input is re-run on the new head (the concurrency
waits with the exponential backoff and jitter above, never re-running at
once. At the cap nothing is persisted. A caller waiting on Handle or
HandleSync is answered INTERNAL ANGZARR_REASON_RETRY_CAP_EXHAUSTED
(args attempts, cap), and its command is NOT dead-lettered: the caller
holds it (the owner's ruling of 2026-10-31, "sync commands write no dead
letter at the retry cap"; decision 14.46 as corrected by 14.85, DRAFT).
Only work with no caller waiting is dead-lettered and alerted: a
HandleAsync command, and a reaction (Deliver) whose policy step then
follows on_policy_bug. A fact is re-run the same way, but a fact is
never refused: at the cap it is dead-lettered and alerted, nothing is
persisted, and its sender is answered INTERNAL
ANGZARR_REASON_FACT_DEAD_LETTERED (non-retryable; decision 14.100, DRAFT). Either way the dead
letter's reason (AngzarrDeadLetter.reason) is
ANGZARR_REASON_RETRY_CAP_EXHAUSTED with the same args.
There is no opt-out: the coordinator owns race re-runs (the owner's
ruling of 2026-10-30; decision 14.84).
## 5. The expected sequence

A client's expected sequence (Handling.expected_sequence), when set and
not the head the coordinator loaded, is refused before business code:
FAILED_PRECONDITION, the framework's typed refusal
io.angzarr.v1.ExpectedSequenceMismatch (types.proto; decision 14.94,
DRAFT). A race lost at the write re-runs the command, which is then stale
and refused the same way; one without an expected sequence re-runs on
the new head.

## 6. Reaction delivery

Reaction commands and refusal facts (policy output) are not delivered
through these RPCs: a policy's coordinator delivers each as a
ReactionDelivery through the framework-only Deliver (the distributed
transport's) or in process (decision 14.79, DRAFT). Deliver answers as
Handle does (DECISION): the policy needs the decision, a refusal
included, to Translate it.

## 7. Process managers

A process manager is a domain (decision 14.31): its coordinator serves
these RPCs for the PM's own domain, and its business process implements
CommandHandlerService, exactly as an aggregate's do. Its commands may be
refused and its facts never are. The coordinator adds the PM's root and
start rules (docs/design/process-managers.md).

## 8. API sugar and what-if execution

Client libraries may expose a single handle(book, mode) call as API sugar
over these three RPCs; the mode still selects the RPC, and is never sent
on the wire.

What-if execution is an ordinary command whose cover names an edition
(see Cover.edition), in any mode; there is no speculative RPC.

## 9. What a handler returns: Emit

Every command handler (an aggregate's or a process manager's, for a
command and for a fact alike) returns an `Emit`, in every client library:
the one return type (decision 14.104, DRAFT). `Emit::of(events)` is a
list of events, applied in order; `.then(step)` optionally adds a
continuation, run on the state with those events folded in, which returns
an `Emit` of its own, and so on. A handler that needs no continuation
returns `Emit::of(events)` and nothing more.

All of it is one decision: a refusal or a bug from the handler or from any
step refuses or fails it all, and what is answered is every step's events,
in order, as one list. The wire stays that one list
(io.angzarr.handler.v1.HandleResponse.events): a continuation is the
client library's, never the coordinator's, and the coordinator cannot tell
an answer built with steps from one built without.

A step must be idempotent on its own result: run again on the state its
own events produce, it emits nothing and continues nowhere. Each client
library gives a test helper that checks it.

There is no step cap, and no key for one. The accepted cost: a step that
always continues never terminates, so its decision never answers. That is
a handler bug, with no framework guard; the idempotence rule and its test
helper are the defence.
