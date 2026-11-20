---
title: CommandBook
---
# CommandBook

Exactly one client command or fact, addressed to one stream. A CommandBook is
the request itself: the coordinator's `Handle` and `HandleAsync` take it
directly, and `HandleSync` takes it inside a `HandleSyncRequest` beside the
projectors to wait for. A policy's outputs are not CommandBooks: its
coordinator delivers each as a `ReactionDelivery` (decision 14.79). A process
manager sends no commands at all.

## Structure

```protobuf file=proto/io/angzarr/v1/types.proto region=command_book
```

A book never carries several commands: deduplication, the expected-sequence
check and the outcome are all per command, so there is no wire batching
(decision 1.4). A client that has several commands sends several books. The
rules are `docs/design/pipeline.md` §9.

## CommandPage

```protobuf file=proto/io/angzarr/v1/types.proto region=command_page
```

The page is the one command:
- **Body:** a `Command` (decided, may be refused) carrying its payload and its
  `Handling`, or a `Fact` (recorded, never refused) carrying its payload and
  its `origin`.
- **Identity:** `command_id` (client-supplied or minted for a command,
  derived from the origin for a fact) and `correlation_id` (set by the
  coordinator when absent).

## Handling

`Handling` is the Command arm's alone: one field, `expected_sequence`
(optional; set and not the head the coordinator loaded, the command is
refused `ExpectedSequenceMismatch`; the coordinator never stamps it). There is
no conflict resolution (decision 14.92). Facts and reactions carry no
Handling.
