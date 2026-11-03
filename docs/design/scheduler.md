# The scheduler: alarms and time facts

**Status:** DRAFT (decision 14.90), for the owner's review. Moved from `proto/io/angzarr/scheduler/v1/scheduler.proto`'s comments (decision 14.109). The messages are `io/angzarr/scheduler/v1/scheduler.proto`'s (`ArmAlarm`, `CancelAlarm`, `AlarmReached`): the time facts of the scheduler, and nothing else.

## 1. The owner's direction

The owner's direction, 2026-11-02: "It'll need to be external, firing
facts (datetime reached) into the domains that asked for them, in
accordance with their alarms", and "we'll want proto for those time
facts".

## 2. The scheduler is a domain

The scheduler is its own component, a DOMAIN (ctxloom-rs-port D12: built in
ctxloom first, lifted into angzarr-embedded later). It keeps ONE stream per
target stream (D5 Q5): the target stream's alarms and nothing else, rooted
compute_root("scheduler", <the target stream's text>)
([identity-and-streams.md](identity-and-streams.md) §3.1; the stream text
of a reason key's `stream` arg, [reason-keys.md](reason-keys.md) §4). The
target
re-checks every alarm it is told of against its own arming (D5 Q5).

This supersedes FUTURE.md's "Timers and deadlines" sketch where they
differ: no "after a duration" form (a domain asks for an instant), and the
fact delivered is AlarmReached, not a payload the domain hands over.

## 3. Why its own package

These are a domain's payloads (layer L0 of decision 46), the scheduler's:
not core (io.angzarr.v1 holds the coordinator's records and imports
nothing angzarr), not the handler layer (what any handler kind takes and
returns), not a component service or a transport. Like any domain's
package it imports only core (for Cover). The scheduler's own state,
events and (component) declaration are its implementation's, not this
contract's.

## 4. Arming and cancelling

A domain asks for an alarm on its own stream with ArmAlarm: tell `target`
AlarmReached once `at` is reached. It is addressed to the scheduler's
stream for `target`. Arming an alarm_id that is armed already moves it to
the new `at`; the old instant is never reached. An `at` already past is
reached at once.

A domain withdraws an alarm it armed with CancelAlarm: it is never
reached. Cancelling an alarm that is not armed (never armed, reached, or
cancelled already) records nothing.

## 5. AlarmReached: the time fact

AlarmReached says `at` is reached for the alarm the target armed as
`alarm_id`. It is delivered to the target stream as a FACT, so it is never
refused; the target re-checks it against its own arming and records
nothing when the alarm was re-armed to another instant or cancelled
meanwhile (a reached alarm and a cancel can cross).

## 6. AlarmReached's identity

Its id is deterministic, so a delivery repeated across restarts is
deduplicated by the target
([identity-and-streams.md](identity-and-streams.md) §7): its
fact_origin.external_id is

```text
  "alarm:" <the target stream's text> "/" alarm_id "@" at
```

with `at` as RFC 3339 in UTC with nanoseconds and a trailing `Z`, and its
command_id the usual fact derivation from it. The same alarm re-armed to
another instant is another fact.
