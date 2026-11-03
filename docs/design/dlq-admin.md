# Dead-letter administration

**Status:** normative (decisions 14.37, 14.47, 14.64, 14.79; as amended by the DRAFT decisions 14.91, 14.101, 14.106 and 14.107 pending review). Moved from the comments of `proto/io/angzarr/transport/distributed/v1/dlq_admin.proto` (decision 14.109). The service is `io.angzarr.transport.distributed.v1.DlqAdminService`; the messages are `dlq_admin.proto`'s (`StoredDeadLetter`, `DeadLetterReplay`, `ReplayOutcome` and the requests and responses).

The Dead Letter Queue admin service serves the `angzarr-status`
operations console. It reads, replays and deletes the dead letters the
distributed transport's DLQ publishers persist: each a
DeadLetterEnvelope (dead_letter.proto; docs/design/distributed-transport.md
§5) around core's AngzarrDeadLetter (io/angzarr/v1/types.proto;
[dead-letters.md](dead-letters.md), its replay §7).

## 1. The service and its failures

DlqAdminService is part of the distributed transport (decision 14.64):
only a distributed deployment runs an admin store of dead letters, and a
transport's package holds its own services.

The surface follows Google AIPs for resource naming, pagination and
filtering. Every method returns its plain result (decision 14.106,
DRAFT). A failure is a gRPC status with a google.rpc.ErrorInfo key
(decision 14.37):

```text
  UNAVAILABLE       DISTRIBUTED_REASON_DEAD_LETTER_STORE_UNAVAILABLE
                    the admin store unreachable
  NOT_FOUND         DISTRIBUTED_REASON_DEAD_LETTER_NOT_FOUND
                    an id with no entry (GetDeadLetter, ReplayDeadLetter)
  INVALID_ARGUMENT  DISTRIBUTED_REASON_DEAD_LETTER_QUERY_INVALID
                    a filter or page token that does not parse
```

(transport/distributed/v1/reasons.proto; [reason-keys.md](reason-keys.md)
§12.4 to §12.6). A console renders a failed
call as that panel's error. An HTTP gateway may map gRPC statuses to
`application/problem+json` (RFC 9457) at the edge; that is the gateway's
concern, and no proto message carries it.

## 2. Stored entries

A StoredDeadLetter is one row from `dlq_entries`, surfaced via the API.
Its `payload` bytes are the proto-encoded `DeadLetterEnvelope` exactly as
the publisher wrote it; ReplayDeadLetter reuses these bytes. A console
decodes `payload`, and the Anys inside it, with descriptors (decision
14.106, DRAFT: there is no server-rendered view). What kind of failure a
dead letter is, is its reason's key.

`payload` itself never changes; replays are recorded beside it, in
StoredDeadLetter.replays: every replay of the entry, oldest first, the
record of when it was replayed and with what result (who replayed it is
in the security log, not here). A DeadLetterReplay is recorded in the
entry when the replay is requested and updated when its result is known;
its outcome is PENDING until the replayed delivery is decided.

## 3. Listing: the filter and pagination

ListDeadLetters lists dead letters matching `filter`, paginated.

The filter is an AIP-160 filter string. Grammar (simple AND-only for v1):

```text
  field "=" string-literal { "AND" field "=" string-literal }
```

Recognised fields: domain, correlation_id, reason_code (the reason's
key, StoredDeadLetter.reason.code; for a refusal entry its implied key,
ANGZARR_REASON_COMMAND_REFUSED; for a transport why, its type's implied
key), refusal_type (a refusal entry's type, its Any's fully-qualified
type name), source_component, occurred_after, occurred_before. The
filter is text, so it is an input boundary: a correlation_id literal is
the UUID's canonical text (hyphenated 8-4-4-4-12 hex, either case),
parsed by the server; a filter that does not parse is INVALID_ARGUMENT
DISTRIBUTED_REASON_DEAD_LETTER_QUERY_INVALID.

Example:

```text
  domain = "player" AND reason_code = "ANGZARR_REASON_RETRY_CAP_EXHAUSTED"
```

Pagination is AIP-158. `page_size = 0` means the server picks the
default; values above the server cap are silently clamped (no error).
`next_page_token` is empty on the last page.

GetDeadLetter fetches a single entry by primary key (AIP-131: the
resource itself).

## 4. Replay semantics

Same message, same ids. A replay is a redelivery, never a new command: it
keeps the original command_id, correlation_id and causation (the dead
letter stores the command, or the reaction, with its ids assigned). If
the original did apply after all, deduplication answers the replay
DUPLICATE, so a replay can never apply a command twice (except one whose
original decision produced no events, which is decided again;
[identity-and-streams.md](identity-and-streams.md) §7 and §7.5). The replayer
delivers as a framework component (mTLS identity;
docs/design/distributed-transport.md §1): a reaction
(AngzarrDeadLetter.rejected_reaction) is replayed through Deliver,
keeping its causation (decision 14.79). The replay itself (time,
outcome) is recorded in the entry (StoredDeadLetter.replays), not on the
replayed message; who asked for it goes to the security log.

One replay, as-is (decision 14.101, DRAFT): the entry is re-sent exactly
as it was dead-lettered, Handling included. A replayed stale command is
refused again, which is correct; there is no mode that clears its
expected sequence.

Command entries. Published to the command bus and processed as an ASYNC
command (the coordinator's HandleAsync): the call returns once the
command is enqueued, not when it is decided; the recorded replay's
outcome is PENDING until then. There is no hardcoded or per-replay sync
mode. A replayed command that fails again is retried or dead-lettered
like any asynchronous command.

There is no age limit: deduplication by command_id is permanent, so an
entry of any age replays safely.

Event entries (rejected_events). Re-delivered to the one component that
failed (AngzarrDeadLetter.source_component), never re-published to every
subscriber.

What ReplayDeadLetter answers: a replay was requested. The dead-letter
row stays in `dlq_entries` (the operator can `Delete` it explicitly once
the outcome is confirmed; operators delete explicitly after confirming
the outcome), and the replay is recorded in it
(StoredDeadLetter.replays). The replayed message keeps its original
correlation_id; follow that, or re-read the entry, for the outcome. The
response's replay is the replay as recorded in the entry (outcome
PENDING for a command); its replayed_at is when the replay was
published.

## 5. Deleting

DeleteDeadLetter deletes a single entry and is idempotent: a row was
removed, or none matched; either is a success, and the response's arm
says which (decision 14.91, DRAFT: no flag).
