# English for the local-process transport's reason keys
# (io/angzarr/transport/embedded/v1/reasons.proto; decisions 14.60 and
# 14.64). Each message id is a live key, verbatim: EmbeddedReason's
# values but the zero. Its variables are that key's args, from the value's
# (reason) option, and only args every answer of the key gives. A wrapped
# `cause` renders as its own key's message, so no message names it.
# Messages are lowercase fragments, so a key reads well inside another
# message. `just check-reason-keys` holds this file to its reasons.proto;
# every runtime of the transport embeds it.

## Raised by whatever runs a child process.

EMBEDDED_REASON_CHILD_NOT_SERVING = component "{ $component }" did not report its health SERVING within { $timeout_ms } ms (last { $status })
EMBEDDED_REASON_CHILD_EXIT_STATUS = component "{ $component }" exited on its stdin's end with status { $exit_code }, not 0
EMBEDDED_REASON_CHILD_NOT_EXITED = component "{ $component }" did not exit by itself on its stdin's end within its grace ({ $ended })
EMBEDDED_REASON_PROBE_INPUT = the probe's input for component "{ $component }" is not one a { $kind } handles
