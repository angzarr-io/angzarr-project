# Diagnostics: reason keys, arguments and typed refusals

**Status:** normative (decisions 14.37, 14.42, 14.44; as amended by the DRAFT decisions 14.95 and 14.104 pending review; C-0669). Moved from `proto/io/angzarr/v1/types.proto`'s comments (decision 14.109). Covers how every error travels: a key and an argument map, never rendered English, on a gRPC status and in a message; typed business refusals on the wire; handler aborts and bugs; the framework's reason keys; and how a wrapped cause is flattened. The message is `types.proto`'s `diagnostic` region (`Diagnostic`); the keys are each layer's `reasons.proto`.

## 1. A key and an argument map

Errors carry a KEY and an ARGUMENT MAP, never rendered English (decision
14.37). Text is rendered only where it is displayed (a console, a UI, a
client's message()), from a Fluent catalog keyed by the code; logs show
the code and its args as they are. No free text crosses any boundary:
not a gRPC status message, not a dead letter, not a response field.

```text
  On a gRPC status   the status message IS the reason key; the
                     google.rpc.ErrorInfo (domain "angzarr.io") carries
                     the same key as its reason and the args as its
                     metadata. Every distinct condition has its own key:
                     two conditions never share one and differ only by
                     text.
  In a message       a Diagnostic.
```

A Diagnostic's code is a stable identifier, never reused for another
meaning, and a valid Fluent message id. Framework codes are
SCREAMING_SNAKE (`ANGZARR_REASON_NO_COMPONENT_OF_KIND`) or the ports'
kebab-case (angzarr-ports-...); a domain's codes are its own. Its args
are data (ids, counts, type URLs, a domain), never a sentence, and the
same names every time for a given code.

## 2. Typed business refusals

A business rejection is TYPED, always (decision 14.95, DRAFT): its
refusal object (one of the command's CommandOptions.refuses types, packed
as an Any) is the key, by its type, and the map, by its fields, so it
carries no Diagnostic. On the wire it is a gRPC status under the
message's declared refusal_status, its reason (and so its status message)
`ANGZARR_REASON_COMMAND_REFUSED`, its ErrorInfo metadata refusal_type the
object's fully-qualified type, and the object packed in the status
details.

## 3. Handler aborts and bugs

A handler's ABORTED and every handler bug carry a diagnostic code and its
args: an ABORTED's reason is the handler's own code; a handler bug's
reason is `ANGZARR_REASON_UNHANDLED_HANDLER_ERROR`, with the handler's own
code and args as its cause (flattened as in §5; a panic's cause is
`ANGZARR_REASON_HANDLER_PANICKED`), and what escaped stays in the
handler's log. A handler that fails with the language's unclassified
error has no cause. In a language with only exceptions (Python), the
client library exports a named unclassified exception for that
(angzarr_client.UnclassifiedError): raising it is a bug with no cause,
and any other exception is a panic, cause
`ANGZARR_REASON_HANDLER_PANICKED` (decision 14.42; C-0669).

## 4. The framework's reason keys

Every framework key, the component that answers it (the router, the
component host or the coordinator, in its comment), the gRPC status it
travels with and its arg names are listed once, as the enum of its layer
(reasons.proto: core's AngzarrReason and each transport's;
[reason-keys.md](reason-keys.md) §1; decisions 14.44 and 14.104, DRAFT);
a key travels as its value's full name, prefix included
(`ANGZARR_REASON_DUPLICATE_COMPONENT`). Which class a status is
(decision 14.37's four classes) is the coordinator's to decide, never the
router's. A Fluent catalog keys a typed refusal by its fully-qualified
type name with each "." replaced by "-" (a Fluent id has no dots).

## 5. Flattening a cause

A cause wrapped inside a diagnostic is flattened into the args: the
cause's code under the arg's name, and each of its args under
"<name>.<arg>" (so "cause" = "angzarr-embedded-store-sql-io",
"cause.errno" = "10"). The same flattening serves ErrorInfo metadata.

## 6. Third-party text: ext_err_txt

The one text an arg may hold: where angzarr converts a third-party
library's error (a store driver's, an I/O error, a transport or decode
error), that library's own text, verbatim, as the arg "ext_err_txt",
beside its numeric code where it has one ("cause.errno" = "5",
"cause.ext_err_txt" = "database is locked"). angzarr's own errors and a
handler's text never travel (decision 14.37).
