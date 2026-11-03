# Component registration: Describe, the descriptor and readiness

**Status:** normative (decisions 14.39, 14.42 as amended, 14.51). Moved from `proto/io/angzarr/component/v1/component.proto`'s comments (decision 14.109). The service is `io.angzarr.component.v1.ComponentService` (`Describe`, `DescribeRequest`); the descriptor is `io/angzarr/v1/types.proto`'s `ComponentDescriptor`, whose validation by the coordinator is [component-descriptors.md](component-descriptors.md) §4.

How a coordinator learns which component its business process is, and
what "registered" means.

## 1. One coordinator, one component, one business process

A component is one aggregate, one policy, one process manager or one
projector, and a business process hosts exactly one. (A projector may
react to several input domains, and a process manager may take commands
from policies of several domains; that is still one component.)

A component's upcasters are part of it, not components of their own: they
run in the component's upcaster sidecar, which serves UpcasterService to
the component's coordinator and is not a business process (see
docs/design/upcasting.md; decision 14.39).

## 2. ComponentService and the descriptor

Every business process serves ComponentService beside its kind service
(CommandHandlerService for an aggregate or a process manager,
PolicyService or ProjectorService). It never serves UpcasterService.

It answers Describe with its component's descriptor, unchanged: the one
angzarr-cli generated at build time, or one business code wrote by hand to
the documented schema in its place (generated code is hand-replaceable).
The client library's component host serves the RPC, so business code never
implements it, and the router never builds or checks the descriptor. The
coordinator validates it, a hand-written one exactly as a generated one
([component-descriptors.md](component-descriptors.md) §2 and §4;
decision 14.42, amended).

## 3. The coordinator pulls

The coordinator PULLS the descriptor: it already dials the business
process for every delivery, and it calls Describe over that same channel.
The business process never calls its coordinator and needs no coordinator
address.

## 4. Registration

The component is registered with its coordinator while the coordinator
holds its descriptor from the business process's last successful Describe.
"Registered", "the registration" and "the registered version" elsewhere in
the protos mean exactly that.

**When.** The coordinator calls Describe when it first connects to the
business process, and again every time its channel to the business
process comes back up after a disconnect. Each successful answer replaces
the descriptor the coordinator held, so a business process restarted on a
new build is re-described before it is delivered to.

## 5. No descriptor, no delivery

The coordinator delivers nothing to its component while it holds no
descriptor (no command, fact, trigger or event). Until it holds one,
deliveries wait: a synchronous caller is answered UNAVAILABLE
DISTRIBUTED_REASON_COMPONENT_NOT_REGISTERED (retryable, arg domain; see
docs/design/command-handling.md §3; decision 14.51), and queued and
reaction deliveries stay queued.

## 6. Refusal

A descriptor that fails the coordinator's validation (see
[component-descriptors.md](component-descriptors.md) §4: an empty
rules_version, no kind, an aggregate or process manager with no state, a
policy with no input or no output domain) is refused. The coordinator
does not hold it, delivers nothing, logs an error naming the business
process and the component, and raises an alert.
It answers the business process nothing (the coordinator is the caller):
the refusal is visible as the coordinator's readiness (§8).

## 7. Failure

A failed Describe call (the business process unreachable, or an error
status) leaves the coordinator holding no descriptor, delivering nothing
and NOT_SERVING, until a later Describe on a re-established channel
succeeds. Every failed call is logged. An alert is raised only once
Describe has kept failing for longer than the coordinator's
describe_alert_grace_period (configuration; default 2 minutes), so a
business process that is merely restarting does not page anyone.

## 8. Readiness

The coordinator reports itself SERVING (gRPC health checking,
grpc.health.v1, and its readiness probe) only after a successful
Describe, and NOT_SERVING while it holds no descriptor.
