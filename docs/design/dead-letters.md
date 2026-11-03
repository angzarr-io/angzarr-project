# Dead letters: payload, why, and replay

**Status:** normative (decisions 14.37, 14.46 to 14.48, 14.51, 14.64, 14.95; as amended by the DRAFT decisions 14.78, 14.79, 14.100, 14.101 and 14.105 to 14.107 pending review). Moved from `proto/io/angzarr/v1/types.proto`'s comments (decision 14.109). Covers what a dead letter holds (its payload and its one statement of why), which reason each failure records, which keys are never a dead letter's reason, retry_count, and how each payload is replayed. The message is `types.proto`'s `dead_letter` region (`AngzarrDeadLetter`); the admin RPCs are `transport/distributed/v1/dlq_admin.proto`'s, and the distributed transport's envelope is `transport/distributed/v1/dead_letter.proto`'s.

## 1. What a dead letter is

A dead letter is a dead letter queue entry for a failed message requiring
manual intervention. Per-domain topics: angzarr.dlq.{domain}.

Among other failures, a fact whose ingest handler fails lands here: a
failing fact handler is a bug, never a business rejection
([pipeline.md](pipeline.md) §7.2).

A dead letter is its payload and why: a typed refusal, or a reason
(decisions 14.78 and 14.101, DRAFT). Everything else about why is read
from it: a refusal's type and fields, or a reason's key, args and the
key's declared status (its (reason) option;
[reason-keys.md](reason-keys.md) §5). Stores from before the rewrite
cross it by export and import (decision 14.100, DRAFT).

The stream concerned is the payload's own cover (rejected_command.cover,
rejected_reaction.cover, rejected_events.cover or
failed_edition_removal.cover); the entry does not repeat it.

A transport may wrap the entry with what only it knows: the distributed
transport's DeadLetterEnvelope adds the captured stack trace, metadata
and a claim-checked payload's retrieval details (decision 14.64). The
entry itself is whole without it: the angzarr-embedded kernel stores it
bare.

## 2. The payload

```text
  rejected_command        a client's command or fact that failed, stored
                          with its ids assigned (command_id and
                          correlation_id as minted, derived or supplied;
                          pipeline step 2) and a command's Handling as
                          sent, before the coordinator resolved it.
  rejected_reaction       a policy's output or refusal fact that failed at
                          its destination, as delivered (decision 14.79).
  rejected_events         events that failed (policy/projector failures).
  failed_edition_removal  an edition removal that failed (DeleteEdition):
                          the stream whose rows of the edition could not
                          be removed (decision 14.107, DRAFT: a cover,
                          since deletion records no event). Reason
                          ANGZARR_REASON_EDITION_REMOVAL_FAILED (decision
                          14.48, amended).
```

A command refused at validation never reaches the DLQ with a minted id:
it has none.

## 3. Why

Why it was dead-lettered is exactly one of a typed refusal, a reason or a
transport's own why, never text (decision 14.37); the one statement of
why (decisions 14.78, 14.101 and 14.107, DRAFT).

- **refusal**: a typed business refusal of an asynchronous command (every
  refusal is typed, decision 14.95): the refusal object, packed. Its key
  is implied (`ANGZARR_REASON_COMMAND_REFUSED`, as on the wire), its type
  is the Any's own type URL, and its args are its fields.
- **reason**: every other failure the framework's packages share: a key
  and its args (a Diagnostic; [diagnostics.md](diagnostics.md)).
- **transport**: a transport's own why: a message of the transport's
  package, packed, its key implied by its type, as a refusal's is
  (decision 14.107, DRAFT). Core cannot name a transport's types, so it
  holds them as an Any. Today the one such type is the distributed
  transport's PayloadRetrievalFailed
  (transport/distributed/v1/dead_letter.proto), key
  `DISTRIBUTED_REASON_PAYLOAD_UNAVAILABLE`. The angzarr-embedded kernel
  never sets it.

## 4. The reason, by failure

- A command with no caller waiting (HandleAsync, a reaction), or a fact,
  the coordinator gave up on after losing write races at the race re-run
  cap, is `ANGZARR_REASON_RETRY_CAP_EXHAUSTED` with args attempts and cap,
  as answered to a waiting caller (decision 14.46); that key is for write
  races only.
- A retryable bug dead-lettered at its cap records the bug's own key and
  args, as last answered, never `ANGZARR_REASON_RETRY_CAP_EXHAUSTED`
  (decision 14.48, amended).
- An asynchronous command (HandleAsync) answered with its handler's own
  abort records that key and its args (decision 14.47); one refused is
  the refusal arm.
- A policy step's trigger (rejected_events) records the policy bug's key:
  `ANGZARR_REASON_POLICY_COMMAND_NO_ROOT`,
  `ANGZARR_REASON_POLICY_TARGETS_ITS_TRIGGER`,
  `ANGZARR_REASON_POLICY_COMMAND_UNKNOWN_DOMAIN`,
  `ANGZARR_REASON_CHAIN_TOO_DEEP`, `ANGZARR_REASON_NO_REFUSAL_HANDLER` or
  a handler's bug.

Whether the failure was transient is the key's declared status
(ReasonOptions' grpc_status): UNAVAILABLE and the other retryable
statuses are transient, every other status is not.

## 5. Never a dead letter's reason

- the readiness keys, the component host's keys,
  `ANGZARR_REASON_NO_HANDLERS_REGISTERED`,
  `ANGZARR_REASON_DUPLICATE_COMPONENT` and
  `ANGZARR_REASON_HANDLER_PANICKED` (only ever a cause);
- the retryable keys the coordinator only answers, never dead-letters:
  `ANGZARR_REASON_UPCASTER_UNAVAILABLE` and the distributed transport's
  `DISTRIBUTED_REASON_COMPONENT_NOT_REGISTERED` (queued work waits) and
  `DISTRIBUTED_REASON_COMMANDS_NOT_SERVED` (decision 14.51);
- `ANGZARR_REASON_SYNC_PROJECTION_FAILED`, whose decision committed and
  whose caller retries (decision 14.105, DRAFT);
- the dead-letter admin's own keys (`DISTRIBUTED_REASON_DEAD_LETTER_*`;
  decision 14.106, DRAFT).

## 6. retry_count

The retries after the first attempt (0 when it was tried once): of a
retryable bug, or a policy step's ABORTED re-run, at its cap, and of an
edition removal (`ANGZARR_REASON_EDITION_REMOVAL_FAILED`).

## 7. Replay

Replay is the DLQ admin's ([dlq-admin.md](dlq-admin.md) §4). An entry is
immutable once written; replays of it are recorded beside it in the
admin store (StoredDeadLetter.replays). A replay keeps the original
command_id, correlation_id and causation: it is a redelivery of the same
message, never a new command, so deduplication answers it DUPLICATE if
the original did apply after all. Replays are delivered by a framework
component (the DLQ replayer, mTLS identity), so a reaction keeps its
causation.

```text
  rejected_command        re-sent to the coordinator as an asynchronous
                          command (HandleAsync), carrying its original
                          ids. It is re-sent as it was, Handling
                          included: a stale command is refused again
                          (decision 14.101, DRAFT).
  rejected_reaction       re-delivered through Deliver, as it was
                          delivered, keeping its ids and causation.
  rejected_events         re-delivered to the one component that failed
                          (source_component), never re-published to every
                          subscriber.
  failed_edition_removal  the removal of that stream's rows of the
                          edition attempted again (DeleteEdition,
                          edition-meta-events.md §5).
```

A dead-lettered Fact wrote nothing, so a DLQ replay runs its handler
again (its sender does not resend it; decision 14.100;
[identity-and-streams.md](identity-and-streams.md) §7.6).
