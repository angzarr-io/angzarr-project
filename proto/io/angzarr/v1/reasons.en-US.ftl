# English for the framework's reason keys (reasons.proto; decision 14.60).
# Each message id is a live key of core's reasons.proto, verbatim:
# RouterReason's, HostReason's and CoordinatorReason's values but the zeros.
# Each transport's keys have a catalog of their own, beside its reasons.proto
# (decision 14.64), so a runtime embeds only its packages' English. Its variables are that key's
# args, from the value's (reason) option, and only args every answer of the
# key gives: where answerers give different args (the comment on the value
# says which), or an arg may be absent (a fold's page or range, a
# relayed upcast type), the message uses none of them. A wrapped `cause`
# renders as its own key's message, so no message names it. Messages are
# lowercase fragments, so a key reads well inside another message.
# `just check-reason-keys` holds this file to reasons.proto; every runtime
# embeds it.

## RouterReason: the client library's router.

ROUTER_REASON_UNHANDLED_HANDLER_ERROR = a handler failed with an error it does not classify: a bug in the handler
ROUTER_REASON_HANDLER_PANICKED = a handler panicked: a bug in the handler
ROUTER_REASON_COMMAND_REFUSED = the command was refused with a typed refusal, a { $refusal_type }
ROUTER_REASON_FOLD_FAILED = a stored event could not be folded into a { $state_type_url }: a bug, or a missing upcaster
ROUTER_REASON_FOLD_FAILED_EMITTED = an event the command emitted could not be folded into a { $state_type_url }: a bug in the domain
ROUTER_REASON_PERSISTED_EVENT_CORRUPT = a stored event or snapshot of type { $type_url } does not decode: restore it, or add the upcaster it needs
ROUTER_REASON_ANY_DECODE_FAILED = a payload did not decode as a { $message_type } ({ $ext_err_txt }): send a payload of its type
ROUTER_REASON_UNKNOWN_COMMAND_TYPE = no handler takes the command type { $type_url }, after upcasting: a bug in the sender
ROUTER_REASON_NO_FACT_HANDLER = no handler takes the fact type { $type_url }: register one, or stop sending it
ROUTER_REASON_NO_REFUSAL_HANDLER = the policy has no refusal callback for a { $command_type }: give it one
ROUTER_REASON_NO_COMPONENT_OF_KIND = the business process hosts no component of the kind dispatched to
ROUTER_REASON_NO_HANDLERS_REGISTERED = no component is registered: register one
ROUTER_REASON_DUPLICATE_COMPONENT = a router hosts one component: register the other in its own
ROUTER_REASON_TOO_MANY_STEPS = a decision ran more than its limit of { $limit } continuation steps: a step that always continues, a bug in the domain

## HostReason: the client library's component host.

HOST_REASON_UPCASTER_WITH_COMPONENT = component "{ $component }" is hosted beside an upcaster: an upcaster is its own sidecar
HOST_REASON_NO_COMPONENTS_REGISTERED = no component is registered with the host: register one
HOST_REASON_DESCRIPTOR_RULES_VERSION_MISMATCH = component "{ $component }" describes rules version "{ $described }" but answers as "{ $reported }": nothing was registered
HOST_REASON_PROJECTOR_NO_INPUT_DOMAIN = projector "{ $component }" names no domain it reads: name one
HOST_REASON_UPCASTER_UNKNOWN_DOMAIN = an upcaster is given for domain { $domain }, which no component here handles
HOST_REASON_UPCASTER_OTHER_DOMAIN = the upcaster registered for domain { $domain } upcasts { $upcaster }'s payloads
HOST_REASON_REMOTE_SOURCE = { $component } reads the events of domain { $domain }, which a coordinator elsewhere handles: they are never written or read here
HOST_REASON_STATE_TYPE_MISMATCH = component { $component }'s state descriptor names { $type_url }, but its snapshots are { $state_type_url }: they would never be offered back

## CoordinatorReason: core's coordinator and the angzarr-embedded kernel.

COORDINATOR_REASON_PM_NO_INSTANCE = the process manager has no instance at { $stream }, and a { $type_url } does not start one: start it first
COORDINATOR_REASON_POLICY_COMMAND_NO_ROOT = a policy sent a { $command_type } to domain { $domain } naming no root: a bug in the policy, which names the root of every command
COORDINATOR_REASON_MISSING_RULES_VERSION = component "{ $component }": its descriptor has no rules version
COORDINATOR_REASON_MISSING_STATE_TYPE = component "{ $component }": a { $component_kind } has no state type
COORDINATOR_REASON_POLICY_NO_OUTPUT_DOMAIN = component "{ $component }": a policy has no output domain
COORDINATOR_REASON_RETRY_CAP_EXHAUSTED = gave up after { $attempts ->
        [one] one run
       *[other] { $attempts } runs
    }, each losing its write to another write to stream { $stream }, at the cap of { $cap }: dead-lettered, nothing persisted
COORDINATOR_REASON_EDITION_REMOVAL_FAILED = the rows of { $stream } in deleted edition "{ $edition }" could not be removed, after { $attempts ->
        [one] one attempt
       *[other] { $attempts } attempts
    }: dead-lettered
COORDINATOR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN = a policy sent a { $command_type } to domain { $domain }, which this coordinator cannot route: a bug in the deployment
COORDINATOR_REASON_HANDLER_UNAVAILABLE = the handler of domain { $domain } could not be reached for { $stream }: run it again
COORDINATOR_REASON_CHAIN_TOO_DEEP = the command chain went deeper than its limit of { $limit }
COORDINATOR_REASON_STORE_UNAVAILABLE = the event store did not answer: send it again
COORDINATOR_REASON_UPCASTER_UNAVAILABLE = the upcaster sidecar of domain { $domain } is not serving: send it again
COORDINATOR_REASON_RULES_VERSION_MISMATCH = component "{ $component }" answered as rules version "{ $reported }", not "{ $registered }", the version it is registered at, for { $stream }: a bug in the component; nothing was kept
COORDINATOR_REASON_EDITION_NOT_FORKED = { $stream } is not forked into edition "{ $edition }": fork it, or let a policy propagate into it, then send it again
COORDINATOR_REASON_POLICY_TARGETS_ITS_TRIGGER = a policy sent a { $command_type } to { $stream }, the stream whose event triggered it: a bug in the policy
COORDINATOR_REASON_POLICY_NO_INPUT_DOMAIN = component "{ $component }": a policy has no input domain
COORDINATOR_REASON_DESCRIPTOR_NO_KIND = component "{ $component }": its descriptor names no kind
COORDINATOR_REASON_RULES_VERSION_NOT_SEMVER = component "{ $component }": its rules version "{ $rules_version }" is not a SemVer version
