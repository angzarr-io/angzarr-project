# English for the distributed transport's reason keys
# (io/angzarr/transport/distributed/v1/reasons.proto; decisions 14.60 and
# 14.64). Each message id is a live key, verbatim: DistributedReason's
# values but the zero. Its variables are that key's args, from the value's
# (reason) option, and only args every answer of the key gives. A wrapped
# `cause` renders as its own key's message, so no message names it.
# Messages are lowercase fragments, so a key reads well inside another
# message. `just check-reason-keys` holds this file to its reasons.proto;
# every runtime of the transport embeds it.

## Raised by a distributed coordinator.

DISTRIBUTED_REASON_COMPONENT_NOT_REGISTERED = no component of domain { $domain } is registered yet: send it again
DISTRIBUTED_REASON_COMMANDS_NOT_SERVED = the query server of domain { $domain } takes no commands: send it to the domain's coordinator
DISTRIBUTED_REASON_PAYLOAD_UNAVAILABLE = the payload at { $uri } could not be retrieved: send it again
