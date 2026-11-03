# The distributed transport: entry points, coordinators, the bus and dead letters

**Status:** normative (decisions 14.37, 14.64; as amended by decisions 14.79, 14.105, 14.107; decision 46, Q3 and Q4). Moved from the comments of `proto/io/angzarr/transport/distributed/v1/command_handler.proto` (the `entry_points` region), `policy.proto`, `projector.proto`, `bus.proto` and `dead_letter.proto` (decision 14.109). The services are `CommandHandlerCoordinatorService`, `PolicyCoordinatorService` and `ProjectorCoordinatorService`; the messages are `bus.proto`'s (`BusEnvelope`, `ClaimCheck`, `PayloadReference`) and `dead_letter.proto`'s (`DeadLetterEnvelope`, `PayloadRetrievalFailed`), all in `io.angzarr.transport.distributed.v1`.

What only the distributed transport adds around the core books: who may
call which coordinator RPC, what the policy and projector coordinators do
per call, how the message bus carries books (and oversized payloads), and
how a dead letter is published and stored. The command RPCs' per-RPC
behaviour is docs/design/command-handling.md §10; queries and
subscriptions are docs/design/queries-and-subscriptions.md; the DLQ admin
service is docs/design/dlq-admin.md; CloudEvents publishing is
docs/design/cloudevents.md.

## 1. Entry points and framework identity

Clients use Handle, HandleAsync and HandleSync; framework components use
them too, and alone use Deliver (decision 14.79).

A framework component (a policy coordinator delivering reaction
commands and refusal facts, the outbox dispatcher, the DLQ replayer, a
coordinator delivering triggers) authenticates with its mTLS identity,
issued to framework components only. Only such a caller may call:

```text
  - Deliver, with a ReactionDelivery (its derived command_id, or the
    refused command's id on a refusal fact, and its causation; the
    receiving coordinator trusts them from this caller);
  - PolicyCoordinatorService.Execute, with a caller-supplied
    trigger EventBook (whose stamping copies the trigger's correlation
    and EventRef onto the policy's commands and refusal facts).
```

Any other caller is a client. A client's CommandBook has no field for a
causation (decision 14.79). A client call to Deliver or to a trigger
entry point is refused PERMISSION_DENIED: the request is well formed,
but the caller is not allowed to make it
(INVALID_ARGUMENT would wrongly tell the caller to fix the message).
Deployments may still expose the trigger routes over HTTP; the gateway
forwards the caller's identity, so a client reaching them is refused the
same way.

Who called, framework or client, goes to the security log, never into
the data ([identity-and-streams.md](identity-and-streams.md) §8).

## 2. The policy coordinator: Execute

PolicyCoordinatorService orchestrates policy execution. It calls the
policy's PolicyService.React once per source event it handles (decision
46, Q3), checks each answer's outputs (a root, not the trigger's own
stream, a routable destination, the chain depth; docs/design/policies.md),
and addresses and stamps each one: the destination
(PolicyDescriptor.output_domain), the trigger's edition, causation
(the triggering event's EventRef), command_id (UUIDv5 of the trigger,
the policy's registered name and the output's index within its
reaction, commands and facts in one index space;
[identity-and-streams.md](identity-and-streams.md) §3.2), correlation_id (the trigger's) and the policy's name, as a
ReactionDelivery (decision 14.79). It records them in the transient outbox
(docs/design/policies.md §5), delivers them through the destination's
coordinator (CommandHandlerCoordinatorService.Deliver) as a framework
component, and retries retryable failures. On a business rejection it
calls PolicyService.Translate and delivers the fact it answers, through
the outbox, to the policy's own source stream (the one refusal path,
docs/design/policies.md §3).

Execute executes the policy over source events: React per event, then
deliver the stamped outputs to their destinations. The request is the
source EventBook, and every output is delivered the one way, through the
transient outbox and Deliver. It is a trigger entry point: callers
authenticated as framework components only; a client is refused
PERMISSION_DENIED (§1).

Execute answers the outputs as the coordinator addressed and stamped
them, in trigger order and, per trigger, in the policy's order
(ExecuteResponse, never persisted).

## 3. The projector coordinator

ProjectorCoordinatorService orchestrates projection processing.

- HandleSync: synchronous processing: project the events and return the
  projection. "Sync" is in the name; the request is the EventBook itself,
  with no mode wrapper. The command coordinator's HandleSync (SIMPLE)
  calls this for each projector its caller named; an error status here
  fails that HandleSync with UNAVAILABLE
  ANGZARR_REASON_SYNC_PROJECTION_FAILED, this status's key its cause
  (decision 14.105).
- HandleAsync: asynchronous processing: accept the events for projection
  and return without waiting (fire and forget). Named for the mode, as on
  the command coordinator (HandleAsync / HandleSync).

## 4. The bus envelope and the claim check

The message bus's envelope (BusEnvelope), and its claim check (decision
14.64), are what the distributed transport carries between its
coordinators, wrapping the core books unchanged. Nothing here is ever
part of a persisted page: EventPage and CommandPage payloads are always a
plain google.protobuf.Any, and the event store records the resolved
payload. The angzarr-embedded kernel has no bus and never sees an
envelope.

Claim check. A page whose payload exceeds the bus's size limit travels
with its payload unset and a ClaimCheck naming it in its place; the
receiving side resolves every claim check back into its page's payload
(and checks its content_hash) before anything else sees the book. A
payload that cannot be retrieved, after the retry cap, is
dead-lettered with a PayloadRetrievalFailed as its why
(dead_letter.proto; key DISTRIBUTED_REASON_PAYLOAD_UNAVAILABLE).

A PayloadReference (the claim check pattern's reference to an externally
stored payload) is carried only by a bus envelope, never by a persisted
page. Its URI's scheme names the storage backend (decision 14.107,
ruled 2026-11-02: there is no separate storage type), for example:

```text
  file:///var/angzarr/payloads/{hash}.bin
  gs://bucket/prefix/{hash}.bin
  s3://bucket/prefix/{hash}.bin
```

## 5. The dead-letter envelope

A dead letter as the distributed transport publishes and stores it is a
DeadLetterEnvelope: core's AngzarrDeadLetter, whole and unchanged,
wrapped with what only this transport knows (decision 14.64). Topics are
per domain: angzarr.dlq.{domain}. The DLQ admin store keeps the
envelope's bytes (dlq_admin.proto, StoredDeadLetter.payload;
docs/design/dlq-admin.md). The angzarr-embedded kernel stores the core
entry bare and never builds one.

The envelope's stack_trace is the failure's cause chain, when one was
captured: a flat array of captured errors (most-causal-first; the
originating caught error is the LAST element), matching Sentry's
`exception.values` shape; linkage via each entry's
`mechanism.exception_id` / `mechanism.parent_id`. It is empty when no
capture was attempted. See sererr.fyi/spec/proto for the schema
rationale.
