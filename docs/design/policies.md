# Policies: translation, refusals and the transient outbox

**Status:** normative (decisions 14.31, 14.42, 14.69, 14.71, 14.76; as amended by decisions 14.78 to 14.102). Moved from `proto/io/angzarr/v1/policy.proto`, which defined no message (decision 14.103); §6 moved from `proto/io/angzarr/component/v1/policy.proto`'s and `proto/io/angzarr/handler/v1/policy.proto`'s comments (decision 14.109). The services are `io.angzarr.component.v1.PolicyService` and `io.angzarr.transport.distributed.v1.PolicyCoordinatorService`; the messages are `io/angzarr/handler/v1/policy.proto`'s.

Policies: stateless translation from source events to the commands and
facts their destination declares. The business logic's service is the
component contract's (io.angzarr.component.v1.PolicyService,
io/angzarr/component/v1/policy.proto), its messages the handler layer's
(io/angzarr/handler/v1/policy.proto; decision 14.78), and the
coordinator's the distributed transport's (PolicyCoordinatorService,
io/angzarr/transport/distributed/v1/policy.proto); what follows is every
runtime's (decision 14.64). 

A policy translates between exactly two domains: events of its one source
domain into commands and facts for its one destination domain. Its source
is derived from the events it names (PolicyDescriptor.input_domain;
[component-options.md](component-options.md) §4, decision 14.78) and its
destination declared
(PolicyDecl.output_domain). One policy per (source domain, destination
domain) pair: every reaction from one domain's events to another domain's
inputs is part of that pair's single policy, and anything needing several
destinations is a process manager
([component-options.md](component-options.md) §5).

The destination may be an aggregate's domain or a process manager's: a
process manager is a domain (decision 14.31), so a policy's commands and
facts reach it like any other domain's. The destination may be the
policy's own source domain, at another root than its trigger's (decision
14.69). Policies are how other domains' events reach a
process manager (a PM subscribes to nothing), and how a PM's decisions
reach other domains (a PM sends no commands: it records events carrying
the data each input needs, and the policy for (the PM's domain, the
target domain) builds the commands and facts from those events).

## 1. One event per call

One event per call (decision 46, Q3). The policy's coordinator calls
React once for each source event whose type the policy names, in stream
order, with that one event; the answer is that event's outputs.

## 2. What a policy emits

A policy emits what its destination declares (decision 14.69): for a type
the destination declares a command, a command, which it may refuse
(Refusals, below); for one it declares a fact (its (fact) option,
options.proto; decision 14.91), a fact, which it records and never
refuses. The arm (Output's command or fact) is the declaration's, which the policy's generated code
reads; business code never picks it. An Output carries a root and a
payload and nothing else, so its coordinator addresses and stamps every
one alike: the destination domain (PolicyDescriptor.output_domain), the
trigger's edition, the derived command_id (commands and facts counted in
one index space), the trigger's correlation_id,
the causation (the event being reacted to), and the policy's name, as a
ReactionDelivery ([pipeline.md](pipeline.md) §10; decision 14.79); a fact's origin is
derived from them at the destination, external_id the command_id's
canonical text and description naming the type and the policy. So a type its destination turns from a command
into a fact keeps its id, and a re-run across the change is answered
DUPLICATE. It carries no Handling ([pipeline.md](pipeline.md) §1): the destination appends
at the head it loaded, as for any input. It is delivered through the one framework-only RPC, Deliver
(decision 14.79).
```text
  - A fact is never refused. One whose handler fails at its destination,
    or whose business process answers it with an error (decision 14.72),
    is dead-lettered and alerted there and its sender answered INTERNAL
    ANGZARR_REASON_FACT_DEAD_LETTERED (docs/design/command-handling.md §3;
    decision 14.100): to the policy that is its step done, never
    retried or dead-lettered again, and its position moves on.
  - The descriptor names no fact types, so the policy's coordinator
    cannot check the arm: one its destination does not declare (a fact
    of a command type, a command of a fact type: deployed versions
    skewed) is a bug, refused INTERNAL by the destination's router
    (ANGZARR_REASON_NO_FACT_HANDLER, ANGZARR_REASON_UNKNOWN_COMMAND_TYPE),
    dead-lettered and alerted.
  - What the coordinator still checks, each a value a type cannot hold
    to: a root that is unset or not 16 bytes
    (ANGZARR_REASON_POLICY_COMMAND_NO_ROOT, args domain and
    command_type); an output to the trigger's own stream, the same
    domain and root in the trigger's edition
    (ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER, args stream and
    command_type; decision 14.71); a destination it cannot route
    (ANGZARR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN); a chain too deep
    (ANGZARR_REASON_CHAIN_TOO_DEEP). Any failed check is a policy
    bug: the whole answer is refused INTERNAL, nothing is delivered, and
    the trigger is dead-lettered and alerted (decisions 14.24, 14.36).
```

## 3. Refusals: one path

Refusals: ONE path (decision 46 #5, amending 2.2, 14.31, 14.42, 14.73 and
14.76). A target, an aggregate or a process manager alike, refuses a
policy's command the way it refuses any command: a business rejection,
a gRPC business status carrying a TYPED refusal object of its own domain
(one of the command's CommandOptions.refuses types, options.proto; e.g.
InsufficientFunds { available, requested }) in its details (decisions
14.37 and 14.95; typed only), and it records NOTHING. The refusal then yields the one unrefusable fact of it for the
policy's OWN source: the exact stream of its triggering event.
```text
  - The policy's coordinator calls PolicyService.Translate with the
    triggering event, the command as delivered and the target's refusal
    (TranslateRequest). The policy's ONE refusal callback (decision
    14.89),
      refused(command, refusal, ctx)
        -> <a fact type of the source domain>, or a Bug,
    takes the refused command (its target's command choice) and the
    refusal as a choice of its target's refusal messages (one arm per
    refusal message its target's commands name; typed only, decision
    14.95), reads it and returns a DOMESTIC fact,
    which the business process answers as the fact's payload alone
    (TranslateResponse), so the source never refers to the foreign
    protos (the policy already does). The author handles the refusals of
    the commands it sends; every other arm answers a Bug (the owner,
    2026-11-02: "it only needs the reversal/compensation for the commands
    its sending, not every possible command").
  - A policy angzarr-cli generates has that one callback, required
    (decision 14.76, as amended by 14.89 and 14.99), when its target has
    a command that can refuse; then a source taking no fact fails
    generation ([component-options.md](component-options.md) §12). A policy written by
    hand whose router has no callback answers
    ANGZARR_REASON_NO_REFUSAL_HANDLER (metadata command_type; decision
    46, Q6), and the step is dead-lettered and alerted at the policy.
  - There is no other path: no standard refusal fact built by the
    coordinator, no source-domain dispatch by the refused command's type,
    and no policy that declines to translate (decision 46 #5).
```
## 4. Mechanics

Mechanics:
```text
  - The coordinator addresses and stamps the fact (decision 14.42). The
    fact's identity is the REFUSED COMMAND'S: its command_id is the
    refused command's command_id (no prefix, no derivation), and the
    coordinator stamps the causation (the refused command's, the
    triggering event) and the trigger's correlation_id, and addresses it
    as a ReactionDelivery (its origin's external_id, derived at the
    source, that command_id's canonical text) to the exact stream the trigger names (domain, root and
    edition). One id therefore appears in two streams by design: never
    applied in the foreign (target) stream, which recorded nothing, and
    recorded as the refusal fact in the domestic (source) stream. The
    answer is a payload and nothing else, so it cannot be misaddressed or
    misidentified.
  - Distributed: the coordinator calls Translate when the outbox relay
    receives the refusal, and writes the fact as a new outbox entry in
    the same transaction that clears the command's entry. A crash before
    that commit retries the step; deduplication is by the command's id
    at the target and by the same id at the source, so a retry records
    nothing twice. The angzarr-embedded kernel makes the same calls
    directly, in the chain.
  - The fact is unrefusable, so compensation cannot loop.
  - Only a business rejection reaches Translate: a business status
    (RefusalStatus's set) carrying a typed refusal. It is never retried.
    ABORTED (re-read and re-decide) makes the runtime
    reload and re-run the policy step under the capped backoff, then
    dead-letter it and alert. A fatal bug (INTERNAL, UNKNOWN, DATA_LOSS)
    is dead-lettered and alerted at once; any other failure is a
    retryable bug, retried with exponential backoff and jitter up to a
    configured cap, then dead-lettered and alerted. Past the cap, or on a
    fatal bug, the policy's position follows its bug setting
    (on_policy_bug).
  - Owner's rulings (decision 14.31): a translating callback that FAILS
    (an error status) is a policy bug, dead-lettered and alerted; a fact
    whose handler fails at the source is dead-lettered and alerted there.
  - A refusal fact is the one output a policy delivers to its own
    source's stream; what its business code emits goes to its
    destination. Only a command is refused, so only a command takes
    this path.
```

## 5. Transient outbox

A policy's commands and facts, and its refusal facts,
go through the transient outbox (decision 5.6, as amended by 14.31). The
outbox is not a policy mechanism: it is ONE transactional outbox, a
capability that names no component kind. Any component whose output
leaves its own stream (output that is not an append to a stream the
component owns) uses it, under the same rules. Today the policy is the
only such kind, so it is the only user; a process manager needs none
today, because its only output is its own events (a PM is a domain; see
docs/design/process-managers.md). A kind that later emits output leaving its
stream uses this outbox, with no new design. The rules, for whichever
component uses it: the coordinator stores the output, addressed and
stamped, atomically with the component's source checkpoint (its position
past the triggering event), then dispatches it, then clears it. A crash
before dispatch completes re-sends the stored output verbatim; the
component is never re-run for a trigger whose output is stored, so the
command ids re-sent are the ones first stamped and the destinations
deduplicate them. Components using it therefore carry NO purity or
determinism requirement: one run's output is recorded once and re-sent as
recorded. A refusal fact is put into the outbox, as a new entry, in the
same transaction that clears its refused command's entry (Refusals,
above), and dispatched and retried the same way.

## 6. React and Translate

A policy's business logic has two calls: React to one event of its
source, and Translate one refusal of a command it sent (decision 14.78,
ruled 2026-11-02). The handler layer's rule holds for both: a request carries the
books, read-only; a response carries only what business code decides
(docs/design/handler-contract.md §2).

**React.** React reacts to one source event (decision 46, Q3: a policy is
a function of one event, and is called once per trigger): it answers the
commands and facts the destination domain declares (an aggregate's or a
process manager's; decision 14.69), in the order business code returned
them. Output i's index is i in the reaction's output
([identity-and-streams.md](identity-and-streams.md) §3.2), commands and
facts in one index space (decision
14.69). An empty answer: the policy does nothing for this event.

An Output names only the destination stream's root and the payload, in
the arm of its kind. Everything else is the coordinator's, so a policy
cannot set it:

```text
  - domain: the policy's one destination, PolicyDescriptor.output_domain;
  - edition: the trigger's;
  - command_id: derived from (trigger, policy, index)
    ([identity-and-streams.md](identity-and-streams.md) §3.2);
  - correlation_id: the trigger's;
  - causation: the trigger's EventRef;
  - a fact's origin: external_id the command_id's canonical text,
    description naming the type and the policy;
  - Handling: none; the destination appends at the head it loaded, as
    for any input (decision 14.92).
```

The root is required for every destination, an aggregate's or a process
manager's alike: nothing fills one in. The arm is the kind (decision
14.91: no flag). The policy's generated code picks it from the
destination's declaration, (command) or (fact) (options.proto; decision
14.73), never business code. A skewed arm (a fact sent as a command, or
the reverse) is refused by the destination's router, as before (decision
14.69; §2).

What the coordinator still checks of an answer, and what a failed check
does, are §2.

**Translate.** Translate turns one refusal of the policy's command into
one fact of its own source (the one refusal path, decision 46 #5; §3). It
is called by the policy's coordinator only, for every business rejection
of one of its commands: every business refusal the target answered (a
gRPC business status carrying a typed refusal; decision 14.95), and
for nothing else: an ABORTED re-runs the step, and a bug is
dead-lettered. The business process runs the policy's one refusal
callback (decision 14.89) and answers the fact's payload. An error status
is a policy bug (dead-lettered and alerted).

Translate is handed the triggering event (a book of the source stream
holding the one event the policy reacted to, the refused command's
causation; its cover is also where the translated fact goes), the refused
command exactly as it was delivered (decision 14.79: its cover, the
identity the coordinator stamped, and its payload, which the policy's one
refusal callback receives as its target's command choice; decision 14.89),
and the target's refusal, read off the target's gRPC status
(io.angzarr.handler.v1.Refusal; docs/design/handler-contract.md §8).

It answers one fact of the policy's own source domain, payload only. The
coordinator builds the rest: a ReactionDelivery addressed to the
trigger's exact stream, a fact holding this payload, with the refused
command's command_id, the trigger's correlation_id and causation the
trigger (decision 14.79; §4). It is never refused, so compensation cannot
loop.

A fact with no payload (no type URL) is delivered like any other, and the
source's router refuses it ANGZARR_REASON_NO_FACT_HANDLER: dead-lettered
and alerted at the source. A policy's router with no refusal callback
answers ANGZARR_REASON_NO_REFUSAL_HANDLER (a policy written by hand: a
generated one has its one callback, decisions 14.76 and 14.89).
