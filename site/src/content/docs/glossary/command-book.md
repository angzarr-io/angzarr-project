---
title: CommandBook
---
# CommandBook

Exactly one command, addressed to one aggregate stream, with how it is to be
handled. A CommandBook is the request itself: the coordinator's `Handle`,
`HandleAsync` and `HandleSync` take it directly. Policies and process managers
emit CommandBooks too, one per command.

## Structure

```protobuf
message CommandBook {
  Cover cover = 1;        // The target stream (domain, edition, root)
  CommandPage page = 3;   // The one command
  Handling handling = 6;  // Expected sequence and conflict resolution; never persisted
}
```

A book never carries several commands: deduplication, the expected-sequence
check and the outcome are all per command, so there is no wire batching
(decision 1.4). A client that has several commands sends several books.

## CommandPage

The page is the one command:
- **Body:** a `Command` (decide, may be rejected) or a `Fact` (ingest, never
  rejected), each wrapping its payload as an `Any`.
- **Identity:** `command_id`, `correlation_id`, and for reaction commands
  `causation_id`; for facts, `fact_origin`.

## Handling

`expected_sequence` (optional; the coordinator stamps the head when absent)
and `conflict_resolution` (`STRICT`, `AGGREGATE_HANDLES` or `COMMUTATIVE`;
unspecified means the configured default). Reaction commands and facts carry
no Handling.
