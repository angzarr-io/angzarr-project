# Upcasting

**Status:** normative (decision 14.39; DRAFT decisions 14.96, 14.97 pending review). Moved from `proto/docs/design/upcasting.md`, which defined no message (decision 14.103, DRAFT). The service is `io.angzarr.component.v1.UpcasterService`; the messages are `io/angzarr/handler/v1/upcaster.proto`'s.

The upcaster's service is the component contract's
(io.angzarr.component.v1.UpcasterService,
io/angzarr/component/v1/upcaster.proto) and its messages the handler
layer's (io/angzarr/handler/v1/upcaster.proto; decision 14.78, DRAFT);
what follows is core's (decision 14.64). 

UpcasterService: transforms old event versions to current versions.
An upcaster is PART of the component whose streams it upcasts, never a
component of its own: it has no ComponentKind, no descriptor and no
coordinator, and its one caller is that component's coordinator.

## 1. Where it runs

Where it runs: the upcaster SIDECAR (decision 14.39). An upcaster is
deployed as a separate binary, its own process serving UpcasterService
(and gRPC health), never the business process:
```text
  - in the distributed runtime, a container beside the component's
    business process and coordinator, its address in the coordinator's
    configuration;
  - in angzarr-embedded, a child process the host launches as it
    launches a remote domain, or a Rust upcaster registered with the
    kernel in-process, called directly under this same contract.
```
With no sidecar configured, nothing is upcast.

## 2. Who calls it

The coordinator of the component that owns a stream
upcasts that stream's events on EVERY read and publish path, by calling
the sidecar: loading the stream for Handle (an aggregate's events, a
process manager's state), answering queries (EventQueryService, see
transport/distributed/v1/query.proto), and wherever stored events reach a subscriber: live
publishing and every read of stored history (catch-up, gap fill,
rebuild) alike. (Live publishing carries only what was just appended,
which business code wrote in the current shape; old shapes reach
subscribers through stored history.) Consumers of another component's
stream (policies, process managers, projectors) therefore only ever see
current event shapes and have no upcasters of their own. Stored events
are never rewritten: upcasting happens on the way out.

## 3. Commands and facts

The same coordinator upcasts an incoming Command's or
Fact's payload through the SAME chain, by type URL, before it judges the
input by its type (a process manager's start rule) and before dispatch.
It sends the payload as the request's lone_payload (it has no stream
sequence) and takes the answer entry keyed no_sequence (decision 14.97,
DRAFT). An upcaster answers payloads keyed by sequence, or no_sequence
(UpcastResponse, decision 14.96): a page's sequence and EventMeta stay as
stored. The business process (the client library's router) never
upcasts and never sees an old shape. A payload whose type URL, after
upcasting, reaches no handler is refused by the router INTERNAL (a bug:
decision 14.37) with reason ROUTER_REASON_UNKNOWN_COMMAND_TYPE (ROUTER_REASON_NO_FACT_HANDLER for a
fact), which is also the status message, naming the type it was given as
ErrorInfo metadata "type_url". The coordinator answers its caller with
that status, its ErrorInfo metadata "type_url" holding the type URL as
sent and "upcast_type_url" the type URL the sidecar returned (the sent
one when no rule applies). Commands are never stored, so a command
upcaster only translates what an out-of-date client sends.

## 4. Prefer, in order

Prefer, in order:
```text
  1. evolving the command compatibly: add fields (proto3 makes an absent
     field its default), never renumber or retype;
  2. having the domain handle both versions for a transition: register a
     handler for the old type URL beside the new one, and remove it when
     the old clients are gone. The domain decides what an old command
     means, which is a business decision, not a schema one.
```
Command upcasting hides stale clients (they keep working, so nothing
tells anyone to upgrade them) and adds machinery for data that is never
stored. Use it sparingly, as a migration aid with a planned removal (a
date or release by which the old clients are gone and the upcaster is
deleted). Event upcasting has no such caveat: stored events never go
away, so their upcasters are permanent.

## 5. Failure

A sidecar that is configured but unreachable stalls what needs
it: the coordinator delivers nothing it would have to upcast and
reports NOT_SERVING; a synchronous caller and a query are answered
UNAVAILABLE COORDINATOR_REASON_UPCASTER_UNAVAILABLE (retryable; args
domain, cause; decision 14.51); queued and reaction deliveries stay
queued. A
rule that fails (an error status from Upcast, or an answer whose
sequences are not exactly the requested pages') is a handler bug.
