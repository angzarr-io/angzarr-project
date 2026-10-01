---
title: Notification
---
# Notification

A compensation signal addressed to one aggregate. It is never written to the aggregate's event stream; only the events its compensation handler emits in response are. Delivery is durable: the coordinator records the notification in its compensation outbox before acknowledging the trigger and delivers it at least once, deduplicated by the notification kind plus the compensated command's provenance tuple, dead-lettering it once the configured outbox retry budget is exhausted. See [Graceful Failure](/features/compensation#delivery-guarantees).

## Event vs Notification

| Aspect | Event | Notification |
|--------|-------|--------------|
| In the event stream | Yes | Never |
| Sequenced | Yes | No |
| Delivery | Bus, from the stream | Coordinator outbox, at least once, deduplicated by the target |
| Use case | State changes | Compensation |

## Types of Notifications

### RejectionNotification
Delivered to the source aggregate (`angzarr_deferred.source`) when a saga/PM command is rejected by its target. Contains:
- The rejected command, whose deferred header carries its provenance
- Rejection reason

### Compensate
Delivered to the target of each reaction command that already executed when a `CASCADE` request with `CASCADE_ERROR_COMPENSATE` fails. Contains the sequences of the events the command produced and the failure reason; the target is the envelope's cover.

## When to Use

Use **Events** for:
- Business state changes that need audit trail
- Facts that might need replay
- Cross-domain communication via sagas

**Notifications** are raised by the framework, not by application code:
- A rejected saga/PM command (RejectionNotification)
- A failed `CASCADE` request in `COMPENSATE` mode (Compensate)
