# Reason keys: the framework's failure vocabulary

**Status:** normative (decisions 14.37, 14.42, 14.44, 14.46, 14.48, 14.49, 14.51, 14.56, 14.60, 14.62, 14.64, 14.65, 14.69, 14.71, 14.80; as amended by the DRAFT decisions 14.84, 14.85, 14.88, 14.91, 14.92, 14.94, 14.95 and 14.100 to 14.107 pending review). Moved from the comments of `proto/io/angzarr/v1/reasons.proto`, `proto/io/angzarr/transport/embedded/v1/reasons.proto` and `proto/io/angzarr/transport/distributed/v1/reasons.proto` (decision 14.109). The enums are those files' AngzarrReason, EmbeddedReason and DistributedReason; the option is `reasons.proto`'s ReasonOptions (the reason region); the English is each file's `reasons.en-US.ftl`.

Every key angzarr answers, once: how keys are named, what travels on the
wire, what a key declares, and, per key, when it is raised, its class and
what is dead-lettered. The status classes themselves (decision 14.37's
four) are `docs/design/command-handling.md` §3.

## 1. Keys by layer

Keys are named by LAYER, never by role (decision 14.104, DRAFT): one enum
per layer, in the package of that layer.

```text
  io.angzarr.v1.AngzarrReason (reasons.proto): core's keys,
      ANGZARR_REASON_*, whichever core component raises them: the client
      library's router and its component host (in every language), core's
      coordinator and the angzarr-embedded kernel.
  io.angzarr.transport.embedded.v1.EmbeddedReason
      (transport/embedded/v1/reasons.proto): EMBEDDED_REASON_*, the
      local-process transport's (decision 14.64).
  io.angzarr.transport.distributed.v1.DistributedReason
      (transport/distributed/v1/reasons.proto): DISTRIBUTED_REASON_*, the
      distributed transport's (decision 14.64).
```

The rules of this document hold in each transport's file: a key
travels as its value's full name, prefix included, each carries its
(io.angzarr.v1.reason) args, and its English is the reasons.en-US.ftl
beside its file.

## 2. Who raises a key

Which component raises a key is documented in the key's comment ("Raised
by ..."); it is not encoded in the string, so a key keeps its string when
another component comes to raise it. Each key's comment opens with who
raises it. A key's string is unique across every package: it is what
travels.

## 3. The wire form

The key on the wire is the VALUE'S FULL NAME, its enum's prefix included:
the gRPC status message, the google.rpc.ErrorInfo reason and
Diagnostic.code are "ANGZARR_REASON_DUPLICATE_COMPONENT", never a number.
The prefix is buf's standard ENUM_VALUE_PREFIX rule, kept with no
exception, and names the key's layer. The numbers are bookkeeping only: no
message carries these enums as a field, nothing encodes a key by its
number, and renumbering one breaks nothing on the wire. Each
*_UNSPECIFIED value exists because proto3 demands a zero; it is never
answered.

## 4. Args

Each value's (reason) option declares the names of its args (the
ErrorInfo metadata keys and Diagnostic.args names) and how it surfaces
(§5; decision 14.65). Every live key carries the option, so `just
check-reason-keys` tells a key with no args from one whose args were never
declared, and each language's generated status table is read off it,
never typed again by hand (decision 14.60: arg-name constants are
generated from it, as options.proto's options are read).

```text
  - Args are listed by name, in the order the key's prose lists them:
    snake_case, each a valid Fluent variable name.
  - A key that concerns one stream declares a `stream` arg: the stream's
    text, its domain, `/`, its root as canonical lowercase UUID text,
    then `@` and its edition when it is in one (the main timeline is
    unset, and adds nothing), as
    `order/0192f3a4-5b6c-7d8e-9f01-23456789ab07@what-if` (decision
    14.65).
  - A key whose answerers differ declares every name any of them gives
    (the key's section says which gives which), and an answer gives none
    it does not declare.
  - A `cause` arg flattens a wrapped key and its args as `cause` and
    `cause.<arg>` ([diagnostics.md](diagnostics.md) §5). `cause` stands
    for itself and the `cause.<arg>` names it flattens to; no other
    dotted name is declared.
```

## 5. Surfaces and class

How a key surfaces is required: every live key names one, by kind
(decision 14.91, DRAFT).

```text
  grpc_status  the gRPC status the key travels with (decisions 14.65 and
               14.104, DRAFT): google.rpc.Code itself, never OK. The
               key's section says when an answerer may pick another (a
               retryable bug's status, C-0678).
  readiness    a readiness refusal: the key never travels as a status; it
               is logged and alerted as the coordinator's readiness
               ([component-registration.md](component-registration.md)
               §8; decisions 14.88 and 14.91, DRAFT).
```

Which class a status is (decision 14.37's four classes) is the
coordinator's to decide (`docs/design/command-handling.md` §3), not
listed in the protos. The class each key is answered in is given in its
section below.

## 6. Catalogs

English for a key comes from a Fluent catalog keyed by it, never from the
proto: the spec's en-US catalog is reasons.en-US.ftl, beside each
reasons.proto, one message per live key using only that key's args, which
every runtime embeds (decision 14.60).

## 7. Retryable failures carry keys; removed keys

A retryable failure carries a key too (decision 14.51): every failure a
coordinator retries, or hands back for its caller to retry, is answered
under a key of its own, so that when the retries are spent, whoever gives
up (the coordinator, as the dead letter's reason, or a caller that owns
its retries, as its last answer) reports the key, never a bare status.

A key that is removed is simply gone from its enum; the decision log
records what was removed and why (decision 14.100, DRAFT: the rewrite
holds no reservations). The numbers are bookkeeping, contiguous.

## 8. Core keys raised by the router

The router is the client library's, in every language.

### 8.1 `ANGZARR_REASON_COMMAND_REFUSED`

Raised by the router and the coordinator. The key a TYPED refusal travels
under, arg refusal_type its object's full type name, on a gRPC status (the
object in the status details, under the status the refusal message
declares, its refusal_status; decisions 14.37 and 14.95;
`docs/design/component-options.md` §10 and §11). The router raises it for
a handler's refusal; the coordinator passes that on, and raises it itself
for its ExpectedSequenceMismatch (decision 14.94). Class: business, fatal.
A dead letter holds the refusal itself (AngzarrDeadLetter's refusal arm),
its key implied as this one and its type the Any's type URL (decision
14.101).

### 8.2 `ANGZARR_REASON_UNHANDLED_HANDLER_ERROR`

A handler failed with an error it does not classify, its own key the
`cause`. INTERNAL, or, in its status's place, the retryable status a
handler picks (C-0678). Class: bug, fatal under INTERNAL; bug, retryable
under the status the handler picks (`docs/design/command-handling.md` §3).

### 8.3 `ANGZARR_REASON_HANDLER_PANICKED`

A handler panicked. Travels only as
ANGZARR_REASON_UNHANDLED_HANDLER_ERROR's cause.

### 8.4 `ANGZARR_REASON_FOLD_FAILED`

A stored event could not be folded into the state (`state_type_url`): a
bug, or a missing upcaster. Its page or range args may be absent. Class:
by its status, INTERNAL, bug, fatal.

### 8.5 `ANGZARR_REASON_FOLD_FAILED_EMITTED`

An event the command emitted could not be folded into the state. Class: by
its status, INTERNAL, bug, fatal.

### 8.6 `ANGZARR_REASON_PERSISTED_EVENT_CORRUPT`

A stored event or snapshot (`type_url`) does not decode. Class: by its
status, DATA_LOSS, bug, fatal.

### 8.7 `ANGZARR_REASON_ANY_DECODE_FAILED`

A payload did not decode as its type (`message_type`, the library's text
`ext_err_txt`). Class: by its status, INTERNAL, bug, fatal.

### 8.8 `ANGZARR_REASON_UNKNOWN_COMMAND_TYPE`

No handler takes the command type, after upcasting. The router sends
type_url only; the coordinator relays it with upcast_type_url (14.39).
Class: by its status, INTERNAL, bug, fatal. A policy's command of a type
its destination declares a fact is one case (`docs/design/policies.md`
§2).

### 8.9 `ANGZARR_REASON_NO_FACT_HANDLER`

No handler takes the fact type. Relayed as
ANGZARR_REASON_UNKNOWN_COMMAND_TYPE is (§8.8). Class: by its status,
INTERNAL, bug, fatal.

### 8.10 `ANGZARR_REASON_NO_REFUSAL_HANDLER`

A POLICY's router handed a refusal (PolicyService.Translate), of a command
type (`command_type`), with no refusal callback: only a policy written by
hand, outside Rust, can (a generated policy has its one callback,
decisions 14.76 and 14.89, and a Rust one fails to compile without it;
`docs/design/component-options.md` §12). Re-scoped by decision 14.78
(decision 46, Q6) from the source domain's router, which no longer
dispatches refusals (the one refusal path). Bug, fatal (decision 14.37):
the policy step is dead-lettered and alerted.

### 8.11 `ANGZARR_REASON_NO_COMPONENT_OF_KIND`

The business process hosts no component of the kind dispatched to. Class:
by its status, UNIMPLEMENTED.

### 8.12 `ANGZARR_REASON_NO_HANDLERS_REGISTERED`

No component is registered with the router. Class: by its status,
INTERNAL, bug, fatal.

### 8.13 `ANGZARR_REASON_DUPLICATE_COMPONENT`

A second component registered where one already is: one business process
hosts one component. ONE owner and one arg set (decision 14.88, DRAFT):
the router answers it, naming the component already registered
(`registered`) and the one refused (`refused`), each by its component
name. The component host does not check it again: it registers through
the router (C-0579; decision 14.44, amended).

## 9. Core keys raised by the component host

The component host is the client library's, in every language
(parity/client/hosting.feature). Each key here is a refusal to start.

### 9.1 `ANGZARR_REASON_UPCASTER_WITH_COMPONENT`

An upcaster hosted beside a component (`component`): an upcaster is its
own sidecar (14.39), never hosted beside a component.

### 9.2 `ANGZARR_REASON_NO_COMPONENTS_REGISTERED`

A host with no component registered (C-0504).

### 9.3 `ANGZARR_REASON_UPCASTER_UNKNOWN_DOMAIN`

An upcaster given for `domain`, which no component of the host handles:
there is nothing for it to upcast. Refused at registration, and nothing is
registered (decision 14.65).

### 9.4 `ANGZARR_REASON_UPCASTER_OTHER_DOMAIN`

The upcaster registered for `domain` upcasts another domain's payloads
(`upcaster`, the domain it names). Refused at registration, and nothing is
registered (decision 14.65).

### 9.5 `ANGZARR_REASON_REMOTE_SOURCE`

A policy or projector here (`component`) reading the events of `domain`,
which a coordinator elsewhere handles: its events are never written or
read here, so the component would never run. Refused at registration, and
nothing is registered (decision 14.65).

## 10. Core keys raised by the coordinator

The coordinator is core's and the angzarr-embedded kernel's.

### 10.1 `ANGZARR_REASON_PM_NO_INSTANCE`

An input for a process manager's root with no instance, of a type
(`type_url`) the PM does not declare as starting. Business, fatal by its
status (FAILED_PRECONDITION) for a command, which is refused; a fact is
dead-lettered with this key and its sender answered
ANGZARR_REASON_FACT_DEAD_LETTERED (`docs/design/process-managers.md` §4).

### 10.2 `ANGZARR_REASON_POLICY_COMMAND_NO_ROOT`

A policy's output (io.angzarr.handler.v1.Output) whose root is unset or
not 16 bytes: nothing fills one in, for any destination (decision 14.36,
as amended). Refused by the policy's coordinator, the trigger
dead-lettered and alerted, nothing delivered. Bug, fatal (decision 14.37).
(`docs/design/policies.md` §2.)

### 10.3 `ANGZARR_REASON_MISSING_RULES_VERSION`

A component's descriptor with no rules version. Readiness.

### 10.4 `ANGZARR_REASON_MISSING_STATE_TYPE`

A stateful component's descriptor (`component_kind`) with no state type.
Readiness.

### 10.5 `ANGZARR_REASON_POLICY_NO_OUTPUT_DOMAIN`

A policy's descriptor with no output domain. Readiness.

### 10.6 `ANGZARR_REASON_RETRY_CAP_EXHAUSTED`

The race re-run cap, whose rules are `docs/design/command-handling.md` §4.
Commands only: the coordinator gave up on a command its caller is waiting
for (Handle, HandleSync): every run lost a race at the write to another
write to the same stream, until the race re-run cap (every input is re-run
on the new head; decision 14.92). `attempts` is how many times business
code ran, `cap` the configured limit reached. Nothing is persisted, and
the command is not dead-lettered: its caller holds it (the owner's ruling
of 2026-10-31; decision 14.85, DRAFT). INTERNAL, a fatal bug's status
(decision 14.37): the retries are spent.

A command with no caller waiting (HandleAsync, a reaction) is
dead-lettered and alerted at the cap, and a policy step that sent it
follows on_policy_bug, as at any cap. A lost race carries no key, so there
is no cause. A fact's sender is never answered this: at the race re-run
cap the fact is dead-lettered and its sender answered
ANGZARR_REASON_FACT_DEAD_LETTERED. A command with no caller waiting, or a
fact, dead-lettered at either cap records this key, with the same args, as
its AngzarrDeadLetter.reason. (Decisions 14.46, 14.85.) The key is for
write races only: a retryable bug dead-lettered at its cap records its own
key, as last answered (decision 14.48, amended). The race re-run cap is at
least 1 (decision 14.84).

### 10.7 `ANGZARR_REASON_EDITION_REMOVAL_FAILED`

The rows of a deleted edition in one stream could not be removed
(DeleteEdition, [edition-meta-events.md](edition-meta-events.md) §5): the removal is
dead-lettered (the stream's cover as
AngzarrDeadLetter.failed_edition_removal) with this key as its reason, and
alerted. `attempts` is how many removals were tried, `cause` the store's
failure. Never answered to a caller: DeleteEdition answers once every
stream is removed or so dead-lettered (decision 14.107, DRAFT). (Decision
14.48, amended.)

### 10.8 `ANGZARR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN`

A reaction command (a policy's) addressed to a domain its coordinator
cannot route: no component of the domain is registered with it, and it
knows no coordinator for the domain elsewhere. Found when the policy's
answer is checked (io.angzarr.handler.v1.ReactResponse): refused, its
trigger dead-lettered with this key as its AngzarrDeadLetter.reason, and
alerted. Never delivered. Bug, fatal (decision 14.37): a deployment that
wires a policy to a domain it does not host is fixed by its operator, not
by a retry. A client's command for an unknown domain is the client's
malformed input, never this. (Decision 14.49.)

### 10.9 `ANGZARR_REASON_HANDLER_UNAVAILABLE`

The coordinator could not reach the business process that handles
`domain`: its process is not running, the connection or the transport
failed, or the call timed out before an answer (`cause`, the transport's
failure, a third-party library's text as `cause.ext_err_txt`). Nothing ran
and nothing was written. Bug, retryable (decision 14.37): UNAVAILABLE
means resend, under the retry cap with backoff and jitter. At the cap the
input is dead-lettered with this key and its args, as last answered, as
its AngzarrDeadLetter.reason (transient, by its status), never
ANGZARR_REASON_RETRY_CAP_EXHAUSTED, which is for write races only
(decision 14.48, amended), and alerted. A business process that is reached
and answers a retryable bug of its own answers
ANGZARR_REASON_UNHANDLED_HANDLER_ERROR (C-0678), never this. (Decision
14.49.)

### 10.10 `ANGZARR_REASON_CHAIN_TOO_DEEP`

A limit a coordinator may enforce: where it follows a chain of reactions
from the input a caller sent (the input at depth 0, a policy's reaction to
its events at depth 1, and so on), a reaction that would go deeper than
its chain depth limit (`limit`, configuration): a policy cycle that never
settles, or a cascade longer than allowed. The reaction is not delivered;
the trigger whose reaction it was is dead-lettered with this key as its
AngzarrDeadLetter.reason (retry_count 0), and alerted. Bug, fatal
(decision 14.37): the same chain runs as deep again, so a retry cannot
help, and a business status would reach Translate, whose reaction deepens
the chain. A coordinator that does not follow chains never answers it.
(Decision 14.49.)

### 10.11 `ANGZARR_REASON_STORE_UNAVAILABLE`

The coordinator's event store failed to answer (I/O, a timeout, a dropped
connection, a busy or locked database: `cause`, the store's failure, a
third-party driver's text as `cause.ext_err_txt`); a write may or may not
have landed. Bug, retryable (decision 14.37): resent under the retry cap
with backoff and jitter, safe because a resend starts at deduplication (a
write that landed after all is answered DUPLICATE). At the cap the input
is dead-lettered with this key and its args, as last answered, as its
AngzarrDeadLetter.reason (transient, by its status), and alerted; a
waiting caller is answered this key. A write that lost a race is never
this: the store was sure, and the coordinator re-runs it. (Decision
14.51.)

### 10.12 `ANGZARR_REASON_UPCASTER_UNAVAILABLE`

The upcaster sidecar `domain`'s coordinator upcasts through (decision
14.39) is configured but could not be reached, or answered under a
retryable status (`cause`): the coordinator delivers nothing it would have
to upcast and reports NOT_SERVING (`docs/design/upcasting.md` §5). A
waiting caller and a query are answered this key, to resend; queued and
reaction deliveries stay queued until the sidecar is back, so it is never
a dead letter's reason. A rule that fails (an error status from Upcast) is
a handler bug, never this. Class: by its status, UNAVAILABLE, bug,
retryable. (Decision 14.51.)

### 10.13 `ANGZARR_REASON_RULES_VERSION_MISMATCH`

A handler's answer (io.angzarr.handler.v1.HandleResponse) whose
rules_version (`reported`, an empty one included) is not the version the
component registered (`registered`: its ComponentDescriptor.rules_version).
Bug, fatal (decision 14.37): refused and nothing persisted; a caller of
Handle or HandleSync is answered it, an asynchronous or reaction delivery
dead-lettered with it as its AngzarrDeadLetter.reason and alerted
(`docs/design/command-handling.md`; C-0558, C-0559, C-0748). (Decision
14.56.)

### 10.14 `ANGZARR_REASON_EDITION_NOT_FORKED`

An input (a client's command or fact, or a policy's reaction) to a stream
in an edition (`edition`) that is not forked there (`stream`, the input's
stream in that edition): the store knows no EditionCreated of the stream
in the edition, whether the edition was never created, was deleted, or
simply does not hold this stream. Checked when the input is loaded, before
business code runs: nothing runs and nothing is persisted. Business, fatal
(decision 14.37): a client forks the stream (ForkStream) and resends; a
policy's reaction is dead-lettered with this key, as any failed delivery,
and alerted. There is no automatic fork (decision 14.107, DRAFT). (C-0633;
decision 14.65.)

### 10.15 `ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER`

A policy's reaction, a command or a fact, addressed to its trigger's own
stream (`stream`: the trigger's domain and root, and its edition, which
every output is stamped with), of type `command_type`. A policy may
address its own domain at another root, never the stream that triggered
it. Refused by the policy's coordinator
(io.angzarr.handler.v1.ReactResponse, the output stamped with the
trigger's edition): nothing is delivered, and the trigger is dead-lettered
with this key as its AngzarrDeadLetter.reason (retry_count 0), and
alerted. Bug, fatal (decision 14.37): the same policy answers the same way
again. (C-0784; decision 14.71.)

### 10.16 `ANGZARR_REASON_NO_INPUT_DOMAIN`

A policy or a projector descriptor that names no source: a policy's empty
input_domain, a projector's empty input_domains (`component_kind` says
which). Its sources are derived from the events it names (decision 14.78;
`docs/design/component-options.md` §4), and there is no wildcard domain
(decision 14.53), so it would react to or fold nothing. One rule, the
coordinator's, for both kinds (decision 14.101, DRAFT): readiness, as
every descriptor rule's (decision 14.65).

### 10.17 `ANGZARR_REASON_DESCRIPTOR_NO_KIND`

A descriptor whose kind (the ComponentDescriptor.kind oneof) is unset, or
an arm this coordinator does not know. Readiness (decision 14.65, 14.78).

### 10.18 `ANGZARR_REASON_FACT_DEAD_LETTERED`

A fact that could not be recorded and is dead-lettered (decision 14.100,
DRAFT; the owner: "non-retryable. if retrying senders repark, it's a logic
bug. they shouldn't be retrying"): its handler failed, answered an error,
or the fact lost a race at every write until the race re-run cap. `cause`
is the dead letter's reason (its key and args, flattened), `stream` the
fact's. Bug, fatal (decision 14.37): INTERNAL, never retried; the dead
letter holds the fact for an operator. A policy that delivered the fact
takes this as its step done: it neither retries the fact nor dead-letters
it again (`docs/design/policies.md` §2).

### 10.19 `ANGZARR_REASON_DESCRIPTOR_NO_DOMAIN`

An aggregate's or a process manager's descriptor with no domain: after the
one component name (decision 14.87) the name no longer implies it.
Readiness (decisions 14.65, 14.101, DRAFT).

### 10.20 `ANGZARR_REASON_STATE_TYPE_MISMATCH`

A handler's answer whose state (`state_type`, the name its type URL ends
in) is not the type the component registered (`registered`, its
StateDescriptor.type_name): its snapshots would never be offered back to
it. Bug, fatal (decision 14.37): refused, nothing persisted; a caller of
Handle or HandleSync is answered it, any other delivery dead-lettered with
it and alerted. The coordinator's equivalent of the retired host check
(decision 14.102, DRAFT: the coordinator owns every descriptor check),
beside ANGZARR_REASON_RULES_VERSION_MISMATCH, which is the equivalent for
the rules version.

### 10.21 `ANGZARR_REASON_SYNC_PROJECTION_FAILED`

HandleSync only ([command-handling.md](command-handling.md) §10): the
decision committed, and a projector the call named (`projector`, its
registered name) then failed to project its events (`cause`, the
projector's failure, its key and args). The decision stays committed. Bug,
retryable (decision 14.37): the caller resends with the same command_id,
which deduplicates (DUPLICATE), answers the same events and waits on the
named projectors again. Never a dead letter's reason: a caller waits, and
nothing is undone. There is no partial answer (decision 14.105, DRAFT,
deleting ProjectorFailure).

### 10.22 `ANGZARR_REASON_SYNC_NO_PROJECTORS`

HandleSync with no projector named (HandleSyncRequest.projectors empty): a
caller that waits for no projector calls Handle. Business, fatal (decision
14.37): nothing runs. (Decision 14.107, DRAFT.)

### 10.23 `ANGZARR_REASON_SYNC_PROJECTOR_NOT_SUBSCRIBED`

HandleSync naming a projector (`projector`) that is not subscribed to the
command's domain (`domain`), a name no projector is registered under
included. Business, fatal (decision 14.37): nothing runs. (Decision
14.107, DRAFT.)

## 11. The local-process transport's keys

EmbeddedReason (decision 14.64): what whatever runs a child process (the
component host) answers when the child breaks the launch protocol
(`docs/design/child-protocol.md` §7): its readiness (health SERVING on the
host's path), its exit, and a conformance probe's input.

### 11.1 `EMBEDDED_REASON_CHILD_NOT_SERVING`

A child whose overall server (service `""`) did not report SERVING on
grpc.health.v1, on the socket path the host chose, within the host's time
limit for a start (`timeout_ms`, in milliseconds), or that exited first:
`component` its name in the host's configuration, `status` the last health
status it answered by its name (`NOT_SERVING`, `SERVICE_UNKNOWN`), or its
number when it has none, or `none` when no check was answered. The host
fails to start the child (`docs/design/child-protocol.md` §2 and §7;
decisions 14.62 and 14.80).

### 11.2 `EMBEDDED_REASON_CHILD_EXIT_STATUS`

A child that exited on its stdin's end with a status other than 0
(`exit_code`), when a child shutting down exits with 0: what a host's
conformance probe refuses (`docs/design/child-protocol.md` §5 and §7;
decision 14.62).

### 11.3 `EMBEDDED_REASON_CHILD_NOT_EXITED`

A child that did not exit by itself on its stdin's end within its grace:
`ended` is how it did end, `signalled` (a signal ended it), `terminated`
(by the host's SIGTERM), `killed` (by its SIGKILL) or `not-running`. What
a host's conformance probe refuses (`docs/design/child-protocol.md` §5 and
§7; decision 14.62).

### 11.4 `EMBEDDED_REASON_PROBE_INPUT`

A host's conformance probe given an input a child of its kind (`kind`, as
its configuration names it: `domain`, `policy`, `projector`) does not
handle: a command for a policy, a book of events for a domain. Nothing is
sent to the child (`docs/design/child-protocol.md` §7; decision 14.62).

## 12. The distributed transport's keys

DistributedReason (decision 14.64): what only a distributed coordinator
raises, for registration by Describe, a standalone query server and the
bus's claim check, and for DlqAdminService.

### 12.1 `DISTRIBUTED_REASON_COMPONENT_NOT_REGISTERED`

The coordinator holds no descriptor of `domain`'s component
([component-registration.md](component-registration.md) §4 and §5): it has not yet been
described, or its Describe failed or was refused, so the coordinator
delivers nothing to it. A waiting caller is answered this key, to resend;
queued and reaction deliveries stay queued until the component is
registered, so it is never a dead letter's reason. A business process that
is described and then cannot be reached is
ANGZARR_REASON_HANDLER_UNAVAILABLE (§10.9). Class: by its status,
UNAVAILABLE, bug, retryable. (Decision 14.51.)

### 12.2 `DISTRIBUTED_REASON_COMMANDS_NOT_SERVED`

A command or fact sent to a standalone query server for `domain`'s event
store, which has no component behind it and takes no commands
(query_server.feature, C-0588). Bug, retryable (decision 14.37): a
misroute or a stale deployment, which the caller's resend to the right
address, or a corrected deployment, can clear. Never a dead letter's
reason: a query server queues nothing. (Decision 14.51.)

### 12.3 `DISTRIBUTED_REASON_PAYLOAD_UNAVAILABLE`

A claim-checked payload (PayloadReference, at `uri`) the coordinator could
not retrieve from its payload store (`cause`, the store's failure, a
third-party library's text as `cause.ext_err_txt`). Bug, retryable
(decision 14.37): retried under the retry cap with backoff and jitter; at
the cap dead-lettered with a PayloadRetrievalFailed as its why
(AngzarrDeadLetter's transport arm, dead_letter.proto), whose type implies
this key, and alerted (C-0447). (Decisions 14.51 and 14.107, DRAFT.)

### 12.4 `DISTRIBUTED_REASON_DEAD_LETTER_STORE_UNAVAILABLE`

DlqAdminService ([dlq-admin.md](dlq-admin.md) §1): the admin store of dead letters could
not be reached or failed to answer (`cause`, the store's failure, a
third-party driver's text as `cause.ext_err_txt`). Bug, retryable
(decision 14.37): the caller resends; nothing was changed by a failed
Delete or Replay. (Decision 14.106, DRAFT, replacing the degraded
envelope.)

### 12.5 `DISTRIBUTED_REASON_DEAD_LETTER_NOT_FOUND`

DlqAdminService.GetDeadLetter or ReplayDeadLetter given an id (`id`) with
no entry. Business, fatal (decision 14.37). DeleteDeadLetter never answers
it: its no_entry arm says so. (Decision 14.106, DRAFT.)

### 12.6 `DISTRIBUTED_REASON_DEAD_LETTER_QUERY_INVALID`

DlqAdminService.ListDeadLetters given a filter or a page token that does
not parse (`field`: `filter` or `page_token`). Business, fatal (decision
14.37): the caller fixes the request. (Decision 14.106, DRAFT.)
