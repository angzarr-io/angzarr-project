# Identity: type URLs, UUIDs, streams, events and commands

**Status:** normative (decisions 9.1, 12.2 to 12.4, 13.3, 13.4, 14.31, 14.36, 14.42, 14.64, 14.69; as amended by decisions 14.78, 14.79, 14.102 and 14.106). Moved from `proto/io/angzarr/v1/types.proto`'s comments (decision 14.109). Covers type URLs, UUIDs, derived and minted identifiers, stream identity (`Cover`), events and their identity (`EventPage`, `EventRef`, `EventMeta`), command identity (command id, correlation, causation, fact origin), deduplication and the security log. The messages are `types.proto`'s: the `uuid`, `derived_ids`, `minted_ids`, `cover`, `event_page`, `event_ref`, `command_identity`, `security_logs` and `event_meta` regions, and `FactOrigin`. Editions are [edition-meta-events.md](edition-meta-events.md); the pipeline and concurrency are [pipeline.md](pipeline.md).

## 1. Type URLs

Every google.protobuf.Any an Angzarr implementation emits uses the type
URL "/" + the message's fully-qualified name (TYPE_URL_PREFIX = "/"),
e.g. "/io.angzarr.v1.EventPage", "/orders.OrderCreated". Readers accept
any prefix: a type URL identifies the message whose fully-qualified name
is the text after its last "/", so
"type.googleapis.com/orders.OrderCreated", "/orders.OrderCreated" and
"orders.OrderCreated" all name the same message.

Matching compares full names exactly: "orders.OrderCreated" never matches
"OrderCreated" or "orders.v2.OrderCreated".

## 2. UUIDs

A UUID is its 16 bytes, most significant first (RFC 9562 byte order). It
is the ONE type for every UUID on the wire: roots, command ids and
correlation ids. 16 bytes, not 36 characters of text, because every
stored event carries several of them (pass 9, decision 9.1).

Where a UUID comes from:

- caller-chosen roots are any 16 bytes, never inspected;
- framework-derived ids are UUIDv5 (RFC 9562, SHA-1 name-based) under a
  fixed angzarr namespace (§3): roots from compute_root, and the command
  id of every reaction command and every fact;
- minted ids are UUIDv7 (§4).

Client-supplied command and correlation ids must be UUIDs too, of any
version: a set UUID whose value is not exactly 16 bytes (an empty value
included) is malformed and refused INVALID_ARGUMENT wherever it is
accepted. An unset UUID field means "not supplied". The framework checks
only the length, never the version or variant bits.

Operations use UUID objects. Code compares, stores, hashes and passes the
16 bytes; it never round-trips through text. Conversion to and from the
canonical text form (36 characters, lowercase hex, hyphenated
8-4-4-4-12, RFC 9562) happens only at display and input boundaries (logs,
consoles, CLI arguments, URLs a human types), through per-language
helpers (Rust: angzarr-core's angzarr-proto crate, its Display and
FromStr; the other client libraries: backlog UU-1). Input helpers accept
the hyphenated form in either case and output helpers always write
lowercase.

Protobuf JSON (and so REST transcoding) renders the bytes as base64, e.g.
`{"value": "1HQbGlLNQ8+t0T27lhVRCw=="}`. That is accepted: storage cost
wins over JSON readability, and the display helpers are for humans.

## 3. Derived identifiers

Framework-derived identifiers are UUIDv5 (RFC 9562 section 5.5, SHA-1
name-based) under fixed angzarr namespace UUIDs. Every runtime (core,
each client library, angzarr-embedded) derives the same 16 bytes from the
same name. The name is always the UTF-8 encoding of the text shown, with
no normalisation.

### 3.1 Derived roots

```text
  compute_root(domain, key) =
    UUIDv5(ANGZARR_ROOT_NAMESPACE, "{domain}:{key}")
  ANGZARR_ROOT_NAMESPACE = d4741b1a-52cd-43cf-add1-3dbb9615510b
```

The domain never contains ':' (§5.1), so the first ':' splits
the name unambiguously whatever the key holds. Example:

```text
  compute_root("player", "alice@example.com")
    = cfe936c0-2912-5ca9-96e6-f37c0b441759
```

### 3.2 Reaction command ids

(See §6.) The command or fact a policy emits as the index-th output
(0-based, in emission order, commands and facts counted together;
decision 14.69) of its reaction to the trigger event T has (a process
manager emits no commands; decision 14.31)

```text
  command_id = UUIDv5(ANGZARR_COMMAND_NAMESPACE, name)
  ANGZARR_COMMAND_NAMESPACE = e2c9f744-9fe1-4b4b-bfee-ae514dde293b
```

where name is six netstrings, concatenated:

```text
  ns(T.stream.domain) ns(T.stream.edition, "" when unset)
  ns(T.stream.root as canonical lowercase text)
  ns(T.sequence in decimal) ns(component) ns(index in decimal)
```

and ns(s) is a netstring: the byte length of the UTF-8 s in decimal, ':',
s itself, ','. component is the reacting component's registered name.
Netstrings make the split unambiguous whatever the strings hold (a
component or edition may contain ':' or ','), and a set edition is never
empty, so "0:," always means main.

Worked example: the trigger {domain "list", main, root
01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f, sequence 7}, component "reminders",
index 0 has the 70-byte name

```text
  4:list,0:,36:01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f,1:7,9:reminders,1:0,
```

and the command id 45764676-e6e4-56fe-8c80-d782423577ee. Index 1 gives
e45bdfdf-d722-56c8-a4bd-35340c9c3c06; the same trigger in edition
"what-if" (name 4:list,7:what-if,36:...) gives
e2321e9e-d55a-5f48-bbe1-b09081c2e445; component "a,b:c" (name
...,1:7,5:a,b:c,1:0,) gives 27ccb6bf-e37e-54bd-b0f0-9eac56ff5f93.

The name never includes the reactor's rules_version or anything else
about its code, so a re-run reproduces the same ids (see Reactor re-runs,
§7.4).

### 3.3 Fact command ids and correlations

```text
  UUIDv5(ANGZARR_FACT_CORRELATION_NAMESPACE, external_id)
  ANGZARR_FACT_CORRELATION_NAMESPACE = e9ef0ae2-6fc6-4c14-b713-ef03971dd867
```

is a fact's command id, and a fact whose correlation_id is unset gets the
same value as its correlation (as a client command's absent correlation
is its command id; see §6.2). The namespace keeps its pass-9 name and
value, so pass-9 fact correlations are unchanged. Example: external_id
"pi_1234" = 917f26ae-ea2e-58af-86de-77013a69617e.

A policy's fact for its destination takes the reaction command id (§3.2),
not the fact derivation, so a type its destination turns from a command
into a fact keeps its id (decision 14.69).

Refusal facts take no derivation (decision 14.31): a refusal fact's
command_id IS the refused command's command_id, which is already a
reaction command id derived as in §3.2 ([policies.md](policies.md) §3;
§6).

### 3.4 Three namespaces

Three namespaces, not one: "{domain}:{key}" is also a valid external_id,
so under one namespace a fact's command id could equal a stream's root;
and a reaction's name could equal some external_id. Separate namespaces
keep the id spaces unrelated by construction. All three values were
generated once as random UUIDv4s, as RFC 9562 suggests for a new
namespace, and never change: changing one changes every derived id, and
with it every stored command id that deduplication looks up.

## 4. Minted identifiers

Every identifier the framework mints is a UUIDv7 (RFC 9562):
time-ordered, so minted ids sort by creation time and index well, with 74
random bits. This holds in angzarr (coordinator and client libraries) and
in angzarr-embedded alike. On the wire a minted id is a UUID message (16
bytes). Today the framework mints:

- CommandPage.command_id of a client Command that arrives without one;
- correlation, only indirectly: an absent correlation on a client Command
  is its command id verbatim (§6.2), which may be a minted one;
- ids an SDK mints on its caller's behalf (a command helper's command_id,
  a new aggregate root); these count as client-supplied.

Client-supplied identifiers are never inspected beyond their shape: a
command_id, correlation_id or root is any 16 bytes (§2); an external_id
is an opaque string the framework never parses or reformats.

Not identifiers, so not covered: store-assigned row numbers (e.g. the
DLQ's int64 entry ids).

## 5. Streams and events

### 5.1 Stream identity: the Cover

A Cover is stream identity, and nothing else: one stream is (domain,
edition, root). Everything that varies per write or per page (command id,
correlation, causation, fact source) lives on the page, the delivery and
the meta (CommandPage, ReactionDelivery, EventMeta), and how a command is
handled (the client's expected sequence) lives on Command.handling; never
on the Cover. Parent/child relationships between aggregates are carried
in domain event payloads, not in the Cover.

The domain never contains ':' (the root-derivation separator, §3.1).

The stream's root is caller-chosen (any 16 bytes), derived by
compute_root (UUIDv5; §3.1) or minted (UUIDv7). A process manager's
stream is no exception: a command or fact addressed to it names its root,
whatever its correlation_id; by convention a policy may set it to its
trigger's correlation_id ([process-managers.md](process-managers.md) §3;
decisions 14.30 and 14.36).

The edition is the name of the timeline the stream belongs to; unset is
main. What an edition is and how it behaves:
[edition-meta-events.md](edition-meta-events.md).

### 5.2 Events and sequences

An EventPage is one persisted event. Sequences are uint64 wherever they
appear (pages, snapshots, next_sequence, query ranges, DLQ details): a
stream's sequence space is not bounded at 2^32.

An event has no business-time field of its own: when it was recorded is
EventMeta.recorded_at, and any business time (e.g. when an external fact
originally occurred) belongs in the event payload.

An event's body is a domain's event or the framework's meta-event
(decision 14.106); the client library hands business code only the
event arm.

An event's sequence is its position in its stream (domain, edition,
root). It is always definite: assigned by the framework when the event is
persisted, never deferred. Together with the stream it is the event's
identity (EventRef).

### 5.3 Event identity: EventRef

An EventRef identifies one event: the page at `sequence` in the stream
`stream`. This is an event's identity — no separate event id is minted —
and is how a reaction names the event it reacted to
(ReactionDelivery.causation).

### 5.4 Event provenance: EventMeta

EventMeta is the provenance of one persisted event, stamped by the
framework. Every persisted event carries meta. Business code cannot set
meta: a handler answers payloads only (io.angzarr.handler.v1, decision
14.78), and reads meta on the pages it is handed.

causation, correlation_id and recorded_at are always recorded. causation
is the event's DIRECT cause (§6): its command arm or its fact arm (with
the fact's origin), by the producing input's kind, every event's (a
process manager's included; a PM is a domain, with no trigger-caused
events; decision 14.31; the arm as CommandPage's body, decision 14.102,
ruled 2026-11-02). Its command_id, read from whichever arm is set, is the
deduplication key on the stream (§7). rules_version is always recorded
from the business logic's report (empty only if the business logic
reports none). A reaction command's causation (its trigger) is NOT
recorded: an event names its own cause, not its cause's cause (decision
13.3; the trigger edge is in traces).

The event's own identity is the EventRef of its page (its stream plus
EventPage.sequence); EventMeta does not repeat it.

One write is the events one command or fact produced. All pages of one
write share one EventMeta, so the events of one command are exactly the
pages with its command_id; the deduplication index (§7) is on that
field. The head the decision saw is not recorded: it is the sequence of
the write's first event (decision 12.4).

correlation_id is the producing command's correlation (§6.2), never
unset on a persisted event.

recorded_at is when the event was durably recorded, stamped by the server
that persisted it. It is the only timestamp an event carries;
TemporalQuery.as_of_time selects by it. It is non-decreasing per stream:
the coordinator stamps max(previous event's recorded_at, now), so a clock
step backwards never makes a later event look older. Events of one write
share one recorded_at. Because of this, the events recorded at or before
any time T are always a prefix of the stream
([queries-and-subscriptions.md](queries-and-subscriptions.md) §3).

rules_version is the full version of the business binary that decided
(or ingested) the event (e.g. "1.4.2+build.7"): baked in when the binary
is built (e.g. by versionator), never a label chosen by hand. It is
reported by the business logic with every answer
(io.angzarr.handler.v1.HandleResponse.rules_version, a process manager's
included) and stamped in full by the coordinator from that response, so
during a rolling deployment each event names the build that decided it.
Business code never sets it on an event. The framework reads it only to
choose which snapshots to offer ([snapshots.md](snapshots.md) §3);
otherwise it explains a historical decision.

## 6. Command identity

Why a command exists, and how it is deduplicated. Every command carries
one command_id; reaction commands also carry the triggering event
(causation); facts carry their source (Fact.origin). A client's command
rides a CommandPage; a policy's, a ReactionDelivery (decision 14.79,
ruled 2026-11-02). This follows the established message-metadata convention
(KurrentDB's $correlationId / $causationId, NServiceBus, Marten and
Wolverine): one message id, a correlation id, and a causation id naming
the message's DIRECT cause. A command's direct cause is its trigger (its
causation); an event's direct cause is the command (or fact) that
produced it (EventMeta.causation). Every event has one: a process
manager's events too, since its only input is facts (decision 14.31).
Each event records only its own direct cause, never its command's
causation (decision 13.3).

### 6.1 command_id

One per command, a UUID, assigned before deduplication:

```text
  client Command  the caller's CommandPage.command_id (any UUID version,
                  reused verbatim on every retry of that command; an SDK
                  mints a v7), or, when the caller supplied none, a
                  UUIDv7 the coordinator mints (§4). A caller that sends
                  several commands (several CommandBooks, e.g. one API
                  call fanning out) uses one command id per command and
                  may group them by a shared correlation_id it sets
                  itself.
  reaction        a policy's Command or Fact (decision 14.69): derived,
                  UUIDv5 of (trigger EventRef, reacting component, index
                  in the reaction's output, commands and facts in one
                  index space); the exact name encoding and worked values
                  are in §3.2. Stamped by the reactor's coordinator,
                  never by the reactor. Its fact's origin is not sent:
                  the destination derives it (external_id that id's
                  canonical text, description naming the type and
                  ReactionDelivery.component).
  Fact            from outside: derived,
                  UUIDv5(ANGZARR_FACT_CORRELATION_NAMESPACE,
                  Fact.origin.external_id) (§3.3). A sender may set it
                  only to that value (an SDK may compute it); any other
                  value is malformed.
```

Every event the command produces records it as its causation
(EventMeta.causation's command_id). Unset on arrival from a client means
"mint one".

### 6.2 correlation_id

The workflow. The caller's when supplied (verbatim; a UUID of any
version). When absent, the coordinator sets it, before business code: a
client Command's correlation is its command_id (client or minted), so
every retry of a client-keyed command lands in one correlation; a Fact's
is its derived command_id. A reaction's (a policy's command or fact) is
its trigger's correlation, stamped by the coordinator: a policy's answer
has no correlation to set (io.angzarr.handler.v1.Output). A refusal fact
takes the refused command's correlation (its trigger's) the same way:
every command or fact a policy sends, to any target, carries its
trigger's correlation unchanged, so correlation traces the causal chain
(decision 14.36).

A command or Fact addressed to a process manager's stream with no
correlation_id is given its cover's root; a set one is kept, whatever the
root. Nothing fills in a root: a policy names its command's root for
every target, and an unset one is a policy bug
(`ANGZARR_REASON_POLICY_COMMAND_NO_ROOT`; io.angzarr.handler.v1.Output.root).
A process manager's events carry their command's or fact's correlation,
like any domain's.

Correlation is never unset on a persisted event, and the framework never
mints one of its own. It groups a workflow and is not an identity: two
sources' external ids can coincide, and a sender that must keep them
apart supplies correlation_id itself. Correlation is recorded per page
only (covers carry none); Query.correlation_id, CorrelationQuery and
EventStreamService.Subscribe (CorrelationFrom) select by it. Every event
carries it (EventMeta.correlation_id).

### 6.3 causation

ReactionDelivery.causation is the command message's own causation, as
the standard defines it: the EventRef of the event a policy reacted to,
always the triggering event (a process manager emits nothing but its own
events, so it stamps none; decision 14.31). It is set by a policy's
coordinator only: on reaction commands and facts, where it is the input
the reaction command_id is derived from, and on refusal facts, where it
is the refused command's own causation, so it names the very stream the
fact is addressed to ([policies.md](policies.md) §3).

It is transport and trace metadata, NOT persisted on the events the
command produces: their causation is the command itself
(EventMeta.causation's command_id). The coordinators record the trigger
edge in the command's trace and logs (OpenTelemetry), as Marten and
Wolverine do, so "which event led to these events" is answered from
traces, not from the event store (decision 13.3;
[queries-and-subscriptions.md](queries-and-subscriptions.md) §4 for what
the store still answers). It is set by the runtime that delivers a
policy's output: core's coordinator, or the angzarr-embedded kernel,
whose checks read it (a refusal fact's address, a reaction's derived id)
in process. Over the distributed transport only the framework-only
Deliver RPC takes a ReactionDelivery
([distributed-transport.md](distributed-transport.md) §1); a client's CommandBook has no field for it (decision 14.79).

### 6.4 origin

Fact.origin is where a Fact came from (FactOrigin): something that
already happened outside the system (a webhook, an integration), kept for
audit and copied onto every event the fact produces (EventMeta's fact
cause). Only the Fact arm has one, so a Command cannot carry one.

Its external_id is the external system's id for the fact (e.g. "pi_1234"
from Stripe). It is required: a Fact whose external_id is empty is
refused INVALID_ARGUMENT. It is a string, not a UUID: it is the external
system's id, in that system's format. The fact's command_id is derived
from it (§3.3), so redeliveries of one external_id to one stream are
deduplicated; a redelivery with a different payload is NOT detected (it
is answered DUPLICATE with the first delivery's events). When the fact's
command supplies no correlation_id, its correlation is the same derived
value. external_id must be unique across all sources that address one
stream; prefix it with the source when two might collide.

Its description is a human-readable origin (e.g. "Stripe webhook"):
audit only, not part of the derivation.

For a policy's fact the destination derives the origin (ReactionDelivery;
§6.1).

### 6.5 Validation of identity

Refused before deduplication (the full list is [pipeline.md](pipeline.md)
§3):

```text
  Fact      requires origin with a non-empty external_id; a set
            command_id must equal the derivation. A policy's output is
            the exception (decision 14.69): a fact delivered as a
            ReactionDelivery, its command_id taken as stamped, not
            re-derived, and its origin's external_id that command_id's
            canonical text. It is one of two kinds, told apart by
            payload alone, with no marker:
              - a policy's fact for its destination (14.69): its
                command_id the reaction command id, accepted by the
                stream it is addressed to;
              - a refusal fact (decision 14.31): its command_id the
                refused command's, for the exact stream of the policy's
                triggering event, which its issuing coordinator
                addresses (decision 14.42): the policy answers a payload
                only (io.angzarr.handler.v1.TranslateResponse). The same
                id is thus in two streams by design: never applied in
                the refusing (target) stream, and recorded as the
                refusal in the source stream.
```

A client's malformed command is answered INVALID_ARGUMENT; a reaction
command has no caller to answer, so it is dead-lettered and alerted as a
reactor bug.

## 7. Deduplication

Deduplication is by command_id, ON THE EVENTS. There is no separate key
store. "Already applied?" means: the addressed stream (CommandBook.cover)
already holds events whose EventMeta.causation's command_id (either arm)
is this command's. Every backend keeps an index on (stream, command_id)
for that lookup; it is not unique, since one command may produce several
events. On a hit the coordinator does not run business code: it answers
with those events, in sequence order, and delivery DUPLICATE
(DeliveryOutcome; [pipeline.md](pipeline.md) §8). Deduplication is per
addressed stream, the same command_id sent to two streams is two
commands, and because the id is written with the events it is atomic
with the append on every backend. (KurrentDB deduplicates appends by
event id the same way, and Equinox keeps processed ids in the stream.)

### 7.1 Concurrent deliveries

Concurrent deliveries of one command race on the append's optimistic
sequence check: exactly one commits. The losing append writes nothing,
and the coordinator runs the losing delivery again from the
deduplication lookup, which now finds the winner's events and answers
DUPLICATE (or, if the winner produced no events, decides again; see the
costs in §7.5).

### 7.2 Process managers

A process manager is a domain (decision 14.31): its events are the
events of the commands and facts addressed to it, with
causation.command_id, and are deduplicated by command_id like any
domain's. There is no trigger and no separate trigger lookup.

### 7.3 Facts

A fact's redeliveries are deduplicated on the command_id derived from
origin.external_id, per addressed stream, before the handler runs (§6.4).

### 7.4 Reactor re-runs

A reaction command_id depends only on (trigger, component, index), never
on the reactor's rules_version or code, so a reactor run again over a
trigger it already handled (a checkpoint reset) emits the same ids, which
every destination answers DUPLICATE, a process manager included (and a
command refused again yields a refusal fact with the same id, which its
source answers DUPLICATE). A re-run never changes history: it adds
nothing where the first run applied, even if the reactor's code has
changed since. Checkpoint resets are for recovery only (output that was
lost before it reached the outbox). Repairing what a buggy reactor did is
done with NEW commands, with new ids, which append new events after the
old ones; the buggy-era events remain, append-only (decision 13.4).

### 7.5 Accepted costs

Accepted costs (decision 12.2):

- A decision that produced NO events leaves nothing to find, so a
  redelivery of that command is decided again, against the stream as it
  is then (Equinox-style). It is answered APPLIED (with the events that
  decision produces, possibly none).
- A command_id reused for a DIFFERENT command goes undetected: it is
  answered DUPLICATE with the first command's events. Payloads are not
  fingerprinted. A client must mint a new id for every new command. The
  same holds for a reactor re-run whose new code would emit different
  commands (§7.4).
- Deduplication is FOREVER: the events are permanent, so a command_id
  that applied on a stream can never apply on it again. There is no
  expiry, purge or retention window.

### 7.6 Rejections leave nothing

A rejected command (a gRPC error status) writes no event, so a retry with
the same command_id runs business code again. The same holds for a
dead-lettered Fact: it wrote nothing, and a DLQ replay runs its handler
again (its sender does not resend it; decision 14.100).

## 8. Who did it: the security log

Who did it is not data. No message in these protos records an actor,
operator or principal: not events, not commands, not the edition or
dead-letter records. Every coordinator authenticates its caller (a client
principal, or a framework component by its mTLS identity) and writes who
called what, and when, with the command_id, to a separate security log
owned by the deployment. Events record why and under which rules
(EventMeta); the security log records who. Keeping identity out of the
event store keeps personal data out of immutable history, so erasing or
rotating it never rewrites an event (decision 12.3).
