# CloudEvents publishing

**Status:** normative (decision 14.108). Moved from the comments of `proto/io/angzarr/transport/distributed/v1/cloudevents.proto` (decision 14.109). The message is `io.angzarr.transport.distributed.v1.CloudEventsResponse`, a list of the official CloudEvents Protobuf Format's `io.cloudevents.v1.CloudEvent` (vendored at `proto/io/cloudevents/v1/cloudevents.proto`).

What a projector returns, in Projection.projection, to publish
CloudEvents to the configured sinks (HTTP webhook, Kafka): the official
CloudEvents Protobuf Format's events (decision 14.108; angzarr
defines no CloudEvent of its own).

## 1. The exact type match

External publishing triggers only when projection.type_url names exactly
the message io.angzarr.transport.distributed.v1.CloudEventsResponse: its
full name after the last "/", as every type URL is read
([identity-and-streams.md](identity-and-streams.md) §1). A bare "CloudEventsResponse", or the same name in another
package, never triggers it.

## 2. How many events, and what goes in them

A projector may return 0 events (skip), 1 (typical) or N (fan-out, e.g.
multi-tenant notifications). It should pack a "public" message in each
event's data, omitting sensitive fields.

## 3. The attributes the framework fills

The framework fills these attributes when the projector leaves them
empty, from the projected event:

```text
  id                 {domain}:{root}:{sequence} on the main timeline
                     (Cover.edition unset: no edition segment), and
                     {domain}:{edition}:{root}:{sequence} on a named
                     edition. The shapes cannot collide: domains, roots
                     and sequences never contain ':', so a main id has
                     exactly three segments and an edition id at least
                     four. root is the root's canonical UUID text
                     (lowercase, hyphenated). The id is a string, as the
                     CloudEvents spec makes it; it is not a UUID.
  source             angzarr/{domain} on the main timeline, and
                     angzarr/{domain}/editions/{edition} on a named
                     edition.
  subject            the stream's root, as canonical UUID text (an
                     optional attribute, so in attributes, as ce_string).
  type               the projected event's fully-qualified message name
                     (the text after the last "/" of its type URL).
  spec_version       "1.0".
  correlationid      an extension attribute (in attributes, ce_string):
                     the event's EventMeta.correlation_id, always set,
                     as canonical UUID text (36 lowercase characters,
                     hyphenated; [identity-and-streams.md](identity-and-streams.md) §2).
  time               EventMeta.recorded_at (in attributes, ce_timestamp).
```

## 4. Editions

A named edition is part of the default id and source, so a CloudEvent's
identity never collides across timelines; an edition's CloudEvents
publish to the configured sinks like main's.
