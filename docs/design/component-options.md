# Component options: declaring components, and the generator's rules

**Status:** normative (decisions 2.2, 14.24, 14.31, 14.34, 14.37, 14.42, 14.50, 14.52, 14.69, 14.74 to 14.76, 14.78; as amended by decisions 14.82, 14.87, 14.89, 14.91 and 14.93 to 14.99). Moved from `proto/io/angzarr/v1/options.proto`'s comments (decision 14.109). The options are that file's: `(io.angzarr.v1.component)` (ComponentOptions and its kind arms), `(io.angzarr.v1.command)` (CommandOptions), `(io.angzarr.v1.fact)` (FactOptions), `(io.angzarr.v1.event)` (EventConsumer) and `(io.angzarr.v1.refusal_status)` (RefusalStatus).

What the component options declare, and the rules angzarr-cli's code
generator holds a descriptor set to. The refusal path a policy takes at
runtime is `docs/design/policies.md` §3; a process manager's inputs and
outputs are `docs/design/process-managers.md`.

## 1. The annotations are the declaration

A component (aggregate, policy, process manager, projector) is declared by
annotating a MESSAGE — its state message for the stateful kinds, or a marker
message for the stateless policy — with (io.angzarr.v1.component). Its commands
and events are other messages carrying (io.angzarr.v1.command) /
(io.angzarr.v1.event) that point back at the anchor. There are no services
and no rpcs: the annotations ARE the declaration. Code generators read these
from descriptors and emit a strict per-component handler interface plus a
local dispatch table; they do NOT emit gRPC service code — transport stays on
the generic framework services and the Any envelope so the coordinator
remains domain-blind.

The annotated message is the component's anchor: for an aggregate or a
process manager it is the event-sourced state the rebuilder folds into, for
a projector its per-delivery projection message, and for the stateless
policy an empty marker message naming the policy.

```text
  option (io.angzarr.v1.component) = {
    component_name: "table" aggregate: { domain: "table" } };
  option (io.angzarr.v1.component) = {
    component_name: "policy-table-wallet" policy: { output_domain: "wallet" } };
  option (io.angzarr.v1.component) = {
    component_name: "projector-table-ledger" projector: {} };
```

## 2. Type references are strings

Type references are strings, deliberately (decision 14.99):
protobuf options cannot hold a type reference, so an option names a
message by its fully-qualified name (component, emits, refuses, an
(event) entry's component, starting_types). Generation resolves every
one against the descriptor set and fails on a name that names no
message (an (event) entry's out-of-set component excepted: a reference,
warned; §8).

## 3. Kinds and the component name

The kind is a oneof (decision 14.78, from the owner's ruling #2): each arm
holds exactly what that kind declares, so nothing can be set on a kind
that may not have it, and there is no per-kind validity table.

```text
  aggregate        its domain: the stream it OWNS (writes its events to)
  process_manager  its domain: its own workflow stream (decision 14.31)
  policy           its output_domain: the one domain it SENDS commands
                   and facts to
  projector        nothing
```

The component's ONE name, ComponentOptions.component_name (decision
14.87; the owner's ruling F8 of 2026-11-02, amending 14.50), is what
the host config's [[component]] entry, the generated registration,
hand-written code and the derived reaction ids (a policy's name seeds
them) call it. REQUIRED: a declaration with an empty one fails generation.
There is no default and no per-kind formula. A name is lower-case ASCII
letters, digits and "-", starting with a letter; anything else fails
generation. Two components of one application with one name is a lint
(`angzarr lint app`). Generated code is named after the anchor message.

Each kind's required field:

```text
  AggregateDecl.domain             the domain of the event stream it owns.
                                   Required. Deployment discovery
                                   advertises it: an aggregate's
                                   angzarr.io/domain label carries it.
  ProcessManagerDecl.domain        the domain of its own workflow stream:
                                   its events are persisted there and its
                                   state is rebuilt from it. Required. Its
                                   angzarr.io/pm label carries it.
  PolicyDecl.output_domain         the one domain it sends commands and
                                   facts to (decision 14.24). Required: a
                                   policy declaring none fails generation.
```

## 4. Sources are derived from the events named

A component's SOURCES are never declared: they are derived from the
events it names (decision 14.78, from the owner's ruling #3). The owner
of an event is the one aggregate or process manager in the descriptor
set with an (event) entry folding it, and the event's domain is its
owner's domain. A policy's source is the one domain of the events its
(event) entries name; a projector's sources are the domains of the
events its entries name. An event whose owner is outside the descriptor
set names its domain on the consumer's entry (EventConsumer.domain, an
override for that case alone; §8). The aggregate (or process manager) that
owns an event's domain folds the events it receives; that is what makes it
the event's owner for source derivation.

Generation fails for:

```text
  - a policy or projector naming no event (one strict check, whether
    reached from the lint, the descriptor path or the build entry point);
  - a policy whose events come from more than one domain;
  - a consumed event with no owner in the set and no override;
  - an override on an event that has an owner in the set (a folding
    entry included);
  - an event folded by two stateful components (a process manager
    subscribing, which 14.31 forbids).
```

## 5. Streams, subscriptions and the policy pair

An aggregate owns its domain's stream and subscribes to nothing. A
process manager is a domain too (decision 14.31): it owns its own
workflow stream, subscribes to nothing, takes commands (most from
policies of other domains) and facts, and sends no commands (its
decisions reach other domains through policies from its domain).
Policies and projectors own no stream.

Each declaration is one component, served by its own business process
behind its own coordinator
([component-registration.md](component-registration.md) §1). A policy is a translator between exactly
two domains: one source and one destination (output_domain). There is one
policy per (source domain, destination domain) pair: every reaction that
translates events of one domain into commands and facts for another
belongs to that pair's one policy, however many event types it reacts to;
its destination may be an aggregate's domain or a process manager's.
Anything that needs several destinations is a process manager, whose
events the policies for (the PM's domain, each destination) translate. A
policy's outputs name only a root (io.angzarr.handler.v1.Output): the
coordinator addresses every one to PolicyDescriptor.output_domain
(decision 14.42). The rest of a policy's outputs is
`docs/design/policies.md` §2.

A projector's one handler serves all its sources, dispatching each event
by its type and receiving its source domain with it (decision 14.50). Each
stream's run arrives independently, in any order across streams: there is
no cross-stream order (decision 14.96). Multi-domain projectors
should be rare. They are not substitutes for process managers or business
logic: the capability exists for system capabilities such as the
timekeeping module, global logging and the like (the owner, 2026-11-02;
decision 14.96).

There are no compensation declarations: a process manager pairs each
step with its undo in code, with its client library's compensation
tooling (decision 14.74). A refusal in a choreographed flow is a rejection
plus a fact: the target refuses a policy's command and records nothing,
the policy translates the refusal into one fact of its own source domain,
and that domain's fact handler decides what it means (decision 2.2, as
amended by 14.31 and 14.78; PolicyService in `docs/design/policies.md`
§3). The typed refusal objects a command's handler may return are named by
the command's annotation, CommandOptions.refuses, as its events are by
emits (§11). A process manager's inputs are declared like an aggregate's,
as (command) and (fact) entries whose component is the PM's state
message; its declaration lists which may start an instance
(ProcessManagerDecl.starting_types; §9).

## 6. Commands

(io.angzarr.v1.command) marks a message as a COMMAND: a request its
component decides and may refuse (decision 14.91, amending 14.34).
It generates one strict handler method on the component that owns it,
taking the typed message as input (the scaffold writes #[handles_cmd];
decision 14.110) and returning `Result<Emit<S>, Refuses<..>>`. It is owned by exactly
one component, an aggregate or a process manager (a domain too; decision
14.31). A FACT is declared by its own option, (io.angzarr.v1.fact) (§7): a
message carries one of the two, never both (generation fails on both), and
nothing flags which.

CommandOptions.component, the anchor message of the component that
handles the command, is resolved against the compiled descriptor set;
generation fails on an unknown or ambiguous reference.

emits. A handling returns a list of its component's events, empty, one or
many (decision 14.75): when emits is set, of these types (the generated
list is typed by them, or by the component's event choice where a language
types a list by one type); when empty, of any of the component's events.
Either way business output is payloads, plus the post-command state the
client library adds to every response, nothing more: the framework builds
the EventBook, uses the command's cover, and stamps sequences and
EventMeta. A handler answers payloads only
(io.angzarr.handler.v1.HandleResponse), so it cannot choose a cover, a
sequence or meta.

refuses. The typed REFUSAL objects the command's handler may refuse with
are messages of the command's own domain (e.g. InsufficientFunds {
available, requested }), business-specific, never events. refuses is the
parallel of emits, in the same form (decision 14.31, the owner's ruling). A
command may name several (decision 14.50), e.g. a refusal several commands
share beside a command's own (one message per refusal, decision 14.82).
When set, the generated handler returns its typed events or one of these
typed refusals; when empty, it cannot refuse (decision 14.95: typed
refusals only). The client library answers the chosen refusal object (the
concrete message, e.g. InsufficientFunds) as a gRPC status: the message's
declared refusal_status, its ErrorInfo, and the object packed in the
status details; the refused policy receives it in
TranslateRequest.refusal. Generation fails on a refuses type that does not
resolve, or that is not a message of the command's own domain (§11). A
fact (FactOptions) has no refuses: a fact cannot be refused. An empty
refuses means the command structurally cannot refuse (typed refusals only,
decision 14.95), so every command a policy sends has a refusal path by
construction: its refusals, or none (decision 14.99, dropping
14.76's rule that a policy-targeted command name at least one).

## 7. Facts

(io.angzarr.v1.fact) marks a message as a FACT: something that already
happened, which its component records and cannot refuse (decision 14.91,
ruled 2026-11-02, replacing CommandOptions.fact; decision 14.34). It generates one
handler on the component that owns it, under its own attribute,
#[handles_fact] (decision 14.110), returning `Result<FactEmit<S>, Bug>`:
a fact's handling cannot refuse, because `Bug` holds no refusal, no typed
refusal and no re-run. Converting a message between (command) and (fact)
changes its option, its attribute and its signature, and the generator
writes the attribute and signature that the option calls for; a (fact)
message handled by #[handles_cmd], or a (command) message handled by
#[handles_fact], fails generation. A fact
is delivered in the Fact arm of a CommandPage, or the fact arm of a
ReactionDelivery (types.proto). A policy sends what its destination
declares (decision 14.69): a fact for a type carrying (fact), a command
for one carrying (command), so a policy's fact is never refused, and only
its commands have a refusal path (`docs/design/policies.md` §2).

FactOptions.component and FactOptions.emits mean what CommandOptions'
do (§6).

Why its own option, not one message with a kind (a oneof of
CommandOptions and FactOptions under one extension): the two share only
`component` and `emits`, and a command alone has `refuses`. Separate
options put each field only where it means something, and read as the
declaration they are: `option (io.angzarr.v1.command) = {...}` or
`option (io.angzarr.v1.fact) = {...}`.

## 8. Event consumers

(io.angzarr.v1.event) marks a message as an EVENT consumed by ONE
component. The extension is repeated, so an event consumed by several
components (e.g. folded into its aggregate AND triggering a policy)
carries one (event) entry per consumer. For an AGGREGATE or a
PROCESS_MANAGER an entry generates a state applier (folded during
rebuild): a PM consumes only its own events, never another domain's
(decision 14.31). For a POLICY / PROJECTOR it generates a reaction
handler. The component's kind selects which.

EventConsumer.component, the consumer's anchor message: a component
outside the descriptor set being generated is a REFERENCE, not an error
(decision 14.50): the generator skips the entry, so one domain's protos
generate alone. But it WARNS for each skipped entry, by the component's
name (decision 14.99): "consumer <component> of <event> is outside
this generation and was skipped; cross-domain references, which generally
should not exist, are flagged this way: check it". `angzarr lint app`
reports a consumer an application lists but does not have.

EventConsumer.domain is an OVERRIDE ONLY (decision 14.78): the event's
source domain, for an event whose owner is outside the descriptor set (a
contract-only proto, a remote domain's events). A consumer's sources are
otherwise derived from the owner's domain (§4). Set on an event that has
an owner in the set (a folding entry included), generation fails.

## 9. Starting a process manager

ProcessManagerDecl.starting_types lists the fully-qualified names of the
commands and facts that may START an instance (decision 14.91,
replacing the per-input CommandOptions.starts switch). What happens to an
input for a root with no instance whose type is not listed (a fact
dead-lettered, decision 14.69; a command refused, ruling B1, adapted;
decision 14.31) is `docs/design/process-managers.md` §4. The generator's
rules: each listed type must be one of this PM's own commands or facts
(generation fails otherwise); the generator copies the list into the PM's
descriptor (ProcessManagerDescriptor.starting_types); a PM listing none
can never start an instance, so the generator warns.

## 10. Refusal status

The status a typed refusal is refused with (decision 14.52, as amended by
14.82). Each refusal is its own message (§11), a business
rejection, fatal (decision 14.37); which of the six business statuses it
travels as is a property of the message, marked on it:

```text
  message SeatTaken {
    option (io.angzarr.v1.refusal_status) = REFUSAL_STATUS_FAILED_PRECONDITION;
    int32 seat = 1;
  }
  message BetNotEven {
    option (io.angzarr.v1.refusal_status) = REFUSAL_STATUS_INVALID_ARGUMENT;
  }
```

Every refusal message DECLARES its status (decision 14.95): there
is no default, and generation fails for a message some command's refuses
names that sets no refusal_status, or sets REFUSAL_STATUS_UNSPECIFIED.
The generated refusal is refused under the declared status, and a
hand-written handler's helper reads the same option, so the two agree.
Generation fails when the option is set on a message no command's
refuses names (the framework's ExpectedSequenceMismatch, which the
coordinator raises, excepted).

RefusalStatus holds the business statuses only, so a bug's or a
retryable status (INTERNAL, UNAVAILABLE, ABORTED, ...) cannot be marked:
a refusal reaches the issuing policy's Translate, which those never may
(`docs/design/command-handling.md` §3). It is also the type of a
handler's refusal status (io.angzarr.handler.v1.Refusal.status), so an
answer cannot refuse under any other. Each value's number is its
google.rpc.Code number, so the status on the wire is the value's number,
read without a table.

## 11. Refusals: the refusing side

Refusals (decision 14.31, amending 2.2; plan ruling 7, "REFUSAL
WIRING"; `docs/design/policies.md` §3).

A command handler refuses with a business rejection, a gRPC status
(decision 14.95, reversing decision 46's Q2) under the status its
refusal message declares (§10), carrying a TYPED refusal object of its own
domain (typed only; decision 14.95), named by the command's annotation,
exactly as emits names its events (the owner's ruling, for consistency):

```text
  message HoldFunds {
    option (io.angzarr.v1.command) = {
      component: "examples.v1.WalletState"
      refuses: "examples.v1.InsufficientFunds"
    };
    ...
  }
```

The generated handler returns its events (a list, decision 14.75) or one
of the refuses types (a typed choice the generator builds in each
language). The client library packs the chosen refusal object, the
concrete message, as a google.protobuf.Any into the status details, and
the coordinator hands it, with its status, to the policy's Translate
(TranslateRequest.refusal). The refusing domain records nothing.
Generator diagnostics, mirroring emits': a refuses type that does not
resolve, or that is not a message of the command's own domain, fails
generation. A command may name several refuses types (decision 14.50).

The framework's one refusal, io.angzarr.v1.ExpectedSequenceMismatch
(types.proto; decisions 14.93 and 14.94), is the coordinator's: it
refuses a command whose set expected sequence is not the head it loaded,
before the handler runs (`docs/design/command-handling.md` §5). No command
lists it in its refuses.

One message per refusal (decision 14.82; the owner's ruling F3 of
2026-11-02, amending 14.50). A domain whose commands refuse for several
reasons declares one message per reason, its args its fields, and names
each in the refuses of every command that refuses with it:

```text
  message PlaceBet {
    option (io.angzarr.v1.command) = {
      component: "examples.v1.TableState"
      refuses: "examples.v1.AlreadyBet"
      refuses: "examples.v1.BetNotEven"
    };
    ...
  }
  message AlreadyBet { int32 seat = 1; }
```

Every typed refusal travels under one wire key:
ANGZARR_REASON_COMMAND_REFUSED, its refusal_type the message's
fully-qualified name, the object in the status details
([diagnostics.md](diagnostics.md) §2; `docs/design/reason-keys.md` §8.1). Its status is the
message's declared (io.angzarr.v1.refusal_status) (§10). There is no
nested code enum and no second keying by a code's name.

## 12. Refusals: the policy's side

The policy's side is ONE path (decision 46 #5, amending 14.31, 14.42,
14.73 and 14.76), specified in `docs/design/policies.md` §3: when a
policy's command is refused, the policy's coordinator calls
PolicyService.Translate, whose ONE callback (decision 14.89),

```text
    refused(command, refusal, ctx)
      -> <a fact of the source domain>, or a Bug,
```

takes the refused command and the refusal as a choice of the target's
refusal messages (one arm per refusal message the target's commands name;
typed only), reads it and returns a DOMESTIC fact, so the source never
refers to the foreign protos (the policy already does). The coordinator
delivers it to the trigger's exact stream. There is no pass-through: no
standard refusal fact, no source-domain dispatch by the refused command's
type, and no policy that declines.

What the generator holds to it. A generated policy has the one callback
(decision 14.76, the owner's ruling of 2026-11-02: "all commands must
declare a refusal path"; "the compensation *must* execute to tell the
source domain of the business failure"; amended by 14.89: "it only needs
the reversal/compensation for the commands its sending, not every possible
command"), required in every language the generator writes (a missing one
does not compile in Rust, and is an abstract method of the Python base
class). Its author handles the refusals of the commands the policy sends
and answers every other arm with a Bug; it answers one of its source's
facts or a Bug, and cannot decline. Its choice holds one arm per refusal
its target's commands name; a target command naming none adds none (it
cannot refuse; decision 14.99). Generation fails, as does lint, for
a policy that may send a command that can refuse whose source takes no
fact to translate the refusal into. A policy written by hand whose router
has no refusal callback answers ANGZARR_REASON_NO_REFUSAL_HANDLER
(decision 46, Q6; `docs/design/reason-keys.md` §8.10).

No declaration of what a policy sends ("declaring commands it may send is
a mistake, period": the owner, 2026-10-28). What the generator checks: the
refuses diagnostics (§11) and, for a policy whose target has a command
that can refuse, its source's facts. angzarr-cli selects no refusal mode:
there is one (decision 14.78).

## 13. Generation failures, warnings and lints

Every rule above that the generator or `angzarr lint app` enforces,
gathered; each is stated in its section.

```text
  Generation fails:
    - a type reference that names no message (§2), an (event) entry's
      out-of-set component excepted;
    - an empty or ill-formed component_name (§3);
    - a policy declaring no output_domain (§3);
    - a policy or projector naming no event; a policy whose events come
      from more than one domain; a consumed event with no owner in the
      set and no override; an override on an event with an owner in the
      set; an event folded by two stateful components (§4, §8);
    - a message carrying both (command) and (fact) (§6);
    - a command's component unknown or ambiguous (§6);
    - a refuses type that does not resolve, or is not a message of the
      command's own domain (§6, §11);
    - a starting_types entry that is not one of the PM's own commands
      or facts (§9);
    - a refusal message some command's refuses names that sets no
      refusal_status or sets REFUSAL_STATUS_UNSPECIFIED; refusal_status
      set on a message no command's refuses names,
      ExpectedSequenceMismatch excepted (§10);
    - a policy that may send a command that can refuse whose source takes
      no fact to translate the refusal into (§12; lint too).
  The order in which several applicable errors are reported is
  unspecified: a test must not depend on which of them is reported first
  when more than one applies.
  The generator warns:
    - for each (event) entry skipped as out of this generation (§8);
    - for a PM listing no starting_types (§9).
  `angzarr lint app` reports:
    - two components of one application with one name (§3);
    - a consumer an application lists but does not have (§8);
    - the policy whose refusals have no source fact (§12).
```
