# The handler contract: the layer rule, Handle and its outcomes

**Status:** normative (decisions 14.37, 14.39, 14.40, 14.42, 14.56, 14.72, 14.75, 14.94, 14.101; as amended by decisions 14.78, 14.95, 14.98 and 14.100). Moved from `proto/io/angzarr/handler/v1/command_handler.proto`'s and `proto/io/angzarr/component/v1/command_handler.proto`'s comments (decision 14.109). The service is `io.angzarr.component.v1.CommandHandlerService`; the messages are `io/angzarr/handler/v1/command_handler.proto`'s (`HandleRequest`, `HandleResponse`, `Refusal`). The other kinds' messages follow the same layer rule: `io/angzarr/handler/v1/policy.proto` (docs/design/policies.md), `io/angzarr/handler/v1/projector.proto` (docs/design/projectors.md) and `io/angzarr/handler/v1/upcaster.proto` (docs/design/upcasting.md).

What each kind of business logic takes and returns, and how the coordinator
treats a command handler's answer. The pipeline, the command modes and
the status codes are docs/design/command-handling.md's; this page covers
the boundary between the coordinator and the business logic.

## 1. The handler layer

The handler layer (decision 14.78): what each kind of business
logic takes and returns, and nothing else. It sits between core
(io.angzarr.v1, the coordinator's records and envelopes) and the component
services (io.angzarr.component.v1, which bind these messages to gRPC). The
dependency direction is component -> handler -> core: the handler package
imports core, and core imports nothing of it.

The component contract's CommandHandlerService is the handler-side
contract of an aggregate's (or a process manager's) business logic: the
one service its business process serves for it, however the runtime
reaches it (in process, a local child's socket, or the network). Its
messages are the handler layer's: each request carries the books,
read-only, and each response only what business code decides. It is the
business logic for one domain's aggregates, implemented in a client
library and called by the coordinator. Business code behaves the same in
every command mode.

## 2. The layer rule

The rule that shapes every message of the handler layer, one half per
direction:

```text
  - A request carries the full angzarr context, read-only: the books the
    coordinator built (CommandBook, EventBook), with every id, cover,
    sequence and EventMeta it stamped or loaded. Business logic gets what
    it needs (the owner's ruling on decision 46, Q1).
  - A response carries only what business code decides on success:
    payloads, the post-decision state, the rules version. A refusal, a
    re-run and a bug are gRPC error statuses (decision 14.95).
    It has no field the coordinator stamps (a cover, a sequence, an id,
    EventMeta), so there is nothing for the coordinator to refuse.
```

The coordinator alone converts between this layer and core's: it wraps
each payload a response returns in core's EventPage, Snapshot or
CommandBook, under the input's cover, never transforming the payload.

## 3. One call for commands and facts

The command handler of an aggregate, and of a process manager (a domain
too, decision 14.31), is ONE call for both input kinds (decision 14.98,
ruled 2026-11-02, amending decision 46's Q3; the owner: "I want fact and command to
use the same verb ... moving from a fact to a command should be
relatively simple to do"): Handle, whose input book holds the command or
the fact arm. The input book's body arm says which. Converting a message
between (command) and (fact) changes only its option; only a command's
handling may answer a refusal.

## 4. Before Handle

Before Handle is called the coordinator has run pipeline steps 1-4
([pipeline.md](pipeline.md) §2): validated the input, assigned its
command_id and correlation_id, loaded and deduplicated it, admitted it (a
process manager's start rule; decision 14.42), and refused it if its
expected sequence is not the head (decision 14.94). Which coordinator RPC
the caller used (the command mode) is not passed on. It has upcast every
payload through the component's upcaster sidecar (decision 14.39) and
dropped the pages the snapshot covers (decision 14.40). Every delivery is
well formed (the coordinator builds it): the client library guards no
envelope (decision 14.42).

So what Handle is handed (HandleRequest) is one command or fact and the
stream it addresses, validated, its ids assigned, deduplicated, admitted
and, for a command that sets an expected sequence, found at the head;
every payload is in its current shape (upcast, decision 14.39). A set
expected_sequence equals history.next_sequence there (decision 14.94). A
policy's fact or a refusal fact arrives as a ReactionDelivery, which the
coordinator turns into the request's input book with its derived origin.
The history is the stream as loaded: the starting state (a snapshot that
passed the coordinator's validity checks, [snapshots.md](snapshots.md)
§3) and every page
after it (decision 14.40).

The handler always decides on the current state: the coordinator appends
at the head it loaded and re-runs a lost race on the new head
([pipeline.md](pipeline.md) §4; docs/design/command-handling.md §4). A command whose expected sequence is not that head is refused before
Handle is called (ExpectedSequenceMismatch; decision 14.94;
docs/design/command-handling.md §5).

## 5. In the client library

The type URL picks the handler. A type URL no registered handler claims is
refused INTERNAL (a bug: decision 14.37) with reason
ANGZARR_REASON_UNKNOWN_COMMAND_TYPE (ANGZARR_REASON_NO_FACT_HANDLER for a
fact), which is also the status message (a key, never text); the status
details carry a google.rpc.ErrorInfo whose metadata key "type_url" holds
the type URL the library was given. The coordinator answers its caller
with "type_url" as sent and "upcast_type_url" as delivered (see
docs/design/upcasting.md §3).

The state the handler sees is the starting state (history.snapshot.state,
when present) decoded, with every delivered page folded in order. The
client library folds what it is given, in order, never checking the
snapshot or comparing sequences with it.

## 6. What Handle answers: success only

Handle answers SUCCESS ONLY (decision 14.95; the owner: "grpc
should carry the error (both retryable and not)"): on success its events,
the state and the rules version (HandleResponse). Every other outcome is a
gRPC error status, per AIP-193 and decision 14.37:

```text
  - a refusal, a COMMAND's only: the business status its refusal message
    declares ((io.angzarr.v1.refusal_status), required), with a
    google.rpc.ErrorInfo (reason ANGZARR_REASON_COMMAND_REFUSED, metadata
    refusal_type) and the typed refusal object packed in the status
    details. The refusing domain records nothing. A fact's handling never
    refuses;
  - a re-run ("re-read and re-decide"): ABORTED under the handler's own
    key and args;
  - a bug: its error status (ANGZARR_REASON_UNHANDLED_HANDLER_ERROR and the
    router's other bug keys; docs/design/command-handling.md §3).
```

A fact's handling never refuses: any error status for a FACT is a bug
(decision 14.72). The fact is dead-lettered under the status's key and
args and alerted, and its sender answered INTERNAL
ANGZARR_REASON_FACT_DEAD_LETTERED (decisions 14.72 and 14.100).

A refusal records nothing. It is typed (one of the command's refuses
messages; decision 14.95): its status is the message's declared
(io.angzarr.v1.refusal_status), its google.rpc.ErrorInfo reason
ANGZARR_REASON_COMMAND_REFUSED with refusal_type, and the object packed in
the status details (decision 14.37). Where it goes:

```text
  - The coordinator answers a client caller with that status unchanged.
  - A refused HandleAsync command is dead-lettered with its refusal
    (AngzarrDeadLetter's refusal arm, decision 14.101).
  - A refused policy command reaches the policy's Translate (the one
    refusal path; docs/design/policies.md §3).
```

## 7. What the coordinator builds from an answer

```text
  - Events. HandleResponse.events are payloads only, in order: empty,
    one or many (decision 14.75). The coordinator wraps event i as an
    EventPage under the input's cover, at sequence head + i, with one
    EventMeta for the write (causation, the command or fact arm with the
    input's command_id, and correlation_id from the input's page,
    recorded_at, rules_version from this answer, and a fact's origin as
    the fact arm's origin).
  - State. HandleResponse.state is the state with the events folded in,
    filled by the client library on every answer, never by business
    code. The coordinator persists it as a Snapshot (sequence, state,
    rules_version) per the domain's storage policy; business code never
    decides whether or when.
  - Rules version. HandleResponse.rules_version is the full version of
    the business binary that produced the answer, baked in when the
    binary is built, never a label chosen by hand: the same value the
    component registered (ComponentDescriptor.rules_version). The client
    library fills it on every answer. The coordinator stamps it in full
    onto every event (EventMeta.rules_version) and any snapshot written
    from this answer.
```

The coordinator persists nothing from an answer it refuses: a
rules_version other than the registered one (an empty one included) is a
handler bug, refused, nothing persisted,
ANGZARR_REASON_RULES_VERSION_MISMATCH (decision 14.56). A caller of Handle
or HandleSync is answered INTERNAL; an asynchronous or reaction delivery is
dead-lettered and alerted. Neither is a business rejection.

## 8. A refusal as Translate receives it

The handler layer's Refusal is a business rejection as the refused
policy's Translate receives it (io/angzarr/handler/v1/policy.proto,
TranslateRequest.refusal): the typed refusal and the status it travelled
as, which the policy's coordinator reads off the target's gRPC status
(decision 14.95). Typed only: every refusal is one of its command's
refuses messages. What the policy does with it is docs/design/policies.md
§3.
