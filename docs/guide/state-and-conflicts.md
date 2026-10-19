# State options and conflict units: a developer guide

This guide is for anyone writing an aggregate or process manager on
angzarr (or annals). It explains how you declare your **state message**
in proto so that stale commands are resolved for you, and how to do that
without merging something you should not. Its last section covers
re-running sagas and process managers after a bug fix.

The normative text lives in the protos:
- `proto/io/angzarr/v1/options.proto`, the `conflict_units` region (the
  options, units, overlap rule and diagnostics);
- `proto/io/angzarr/v1/types.proto`, the `conflict_resolution` region
  (`ConflictResolution`, `StateOptions`) and `StateDescriptor`.

Where this guide and the protos disagree, the protos win. Report the
disagreement.

**Status.** This describes the pass 13 protos (decision log entries 12.7,
12.8, 12.11 and 13.4, in `docs/design/audit-meta/decision-log.md`). The generators described below (`angzarr_build::compile` and
`protoc-gen-angzarr`) are specified but not yet built (backlog CR-1). The
options compile today, and `rust/angzarr-proto` reads them back from
descriptors in its tests.

## Contents

1. [The problem: stale commands](#1-the-problem-stale-commands)
2. [Protobuf custom options in five minutes](#2-protobuf-custom-options-in-five-minutes)
3. [The `state` option and its implicit base](#3-the-state-option-and-its-implicit-base)
4. [Marking fields](#4-marking-fields)
5. [What "changed" means, and how COMMUTATIVE resolves](#5-what-changed-means-and-how-commutative-resolves)
6. [The risk of COMMUTATIVE](#6-the-risk-of-commutative)
7. [Build warnings and errors](#7-build-warnings-and-errors)
8. [Build setup](#8-build-setup)
9. [Registration fills `StateDescriptor`](#9-registration-fills-statedescriptor)
10. [Versioning commands](#10-versioning-commands)
11. [Re-running reactors](#11-re-running-reactors)

## 1. The problem: stale commands

A client reads a stream at sequence 12, and sends a command saying so
(`Handling.expected_sequence = 12`). By the time the command arrives, two
other commands have appended events 12 and 13. The command is **stale**,
and events 12..13 are its **concurrency window**.

angzarr has three answers (`ConflictResolution`):

| Resolution | What happens to a stale command | Who writes conflict logic |
|---|---|---|
| `STRICT` | refused `ABORTED` before business code; the caller re-reads and retries | nobody |
| `AGGREGATE_HANDLES` | `decide` receives the window and must call `resolve_conflicts(window, nonce)` | you, in `decide` |
| `COMMUTATIVE` | the client library compares what the window changed with what the command changes; disjoint means accepted, overlapping means `ABORTED` | nobody: you declare conflict units in proto |

**COMMUTATIVE is the default** for any state that declares conflict units,
and STRICT is the default otherwise. Configuration or `Handling` can pick
another resolution the state supports.

## 2. Protobuf custom options in five minutes

Protobuf lets a schema carry **annotations** on its own elements. These are
*custom options*:

- An option is a field added to one of protobuf's own descriptor messages.
  `google.protobuf.MessageOptions` annotates messages and
  `google.protobuf.FieldOptions` annotates fields. You add a field to them
  with `extend`:

  ```proto
  extend google.protobuf.MessageOptions {
    StateOptions state = 50106;      // usable as option (io.angzarr.v1.state)
  }
  extend google.protobuf.FieldOptions {
    ConflictUnit conflict = 50107;   // usable as [(io.angzarr.v1.conflict) = ...]
  }
  ```

- **Extension numbers** identify the option on the wire, exactly as field
  numbers identify fields. angzarr uses 50100–50107 (in the range protobuf
  reserves for private use): `component` 50100, `command` 50104, `event`
  50105, `state` 50106 and `conflict` 50107. Never reuse one.

- **Values are written in text format**, protobuf's human-readable syntax:
  `{}` is an empty message, `{descend: true}` sets one field, and a
  repeated field is a list, `[A, B]`. The parentheses in
  `(io.angzarr.v1.state)` mark a custom option, and name it by its full
  name.

- **Options are compiled into the descriptors**, the binary description of
  your `.proto` files that `protoc` produces. They do nothing at runtime on
  their own. A **code generator reads them at build time** and emits code,
  here `changed()` and the `StateDescriptor`. Nothing reads options at
  runtime. prost, for one, does not even keep unknown options in its
  `prost_types::MessageOptions`, so a Rust program could not read them at
  runtime if it wanted to. That is why angzarr generates code from them.

## 3. The `state` option and its implicit base

Put the option on your aggregate's (or process manager's) state message:

```proto
import "io/angzarr/v1/options.proto";

message ListState {
  option (io.angzarr.v1.state) = {
    conflict_resolutions: [CONFLICT_RESOLUTION_COMMUTATIVE]
  };
  map<string, Item> items = 1 [(io.angzarr.v1.conflict) = {}];
  repeated Column columns = 2 [(io.angzarr.v1.conflict) = {}];
  Settings settings = 3 [(io.angzarr.v1.conflict) = {}];
}
```

The list **adds** to an implicit base:

| What you write | Supported resolutions | Default |
|---|---|---|
| no `(state)` option | STRICT, AGGREGATE_HANDLES | STRICT |
| `conflict_resolutions: [CONFLICT_RESOLUTION_COMMUTATIVE]` | STRICT, AGGREGATE_HANDLES, COMMUTATIVE | COMMUTATIVE |

Every state supports STRICT and AGGREGATE_HANDLES, because neither needs
anything from your schema. In practice COMMUTATIVE is the only value worth
listing. Listing a base value is redundant but harmless.

Listing COMMUTATIVE is a promise that your fields are marked (section 4).
The generator holds you to it (section 7).

## 4. Marking fields

In a COMMUTATIVE state, every field should carry `(io.angzarr.v1.conflict)`.
The `ConflictUnit` value refines how the field is split into **units**.
Every unit has a **path**, which is what `changed()` reports.

| Field kind | Marker | Unit(s) | Example path |
|---|---|---|---|
| scalar, string, bytes, enum | `{}` | the field | `title` |
| `optional` scalar | `{}` | the field; set and unset differ | `deadline` |
| message | `{}` | the whole message (deep equality) | `settings` |
| message | `{descend: true}` | each inner field, by its own marker | `settings.cooldown_days` |
| map | `{}` | one unit per key | `items[42]` |
| map of messages | `{descend: true}` | per key, then per inner field | `items[42].weight` |
| repeated message | `{element_key: "id"}` | one unit per element key | `columns[due]` |
| repeated message | `{element_key: "id", ordered: true}` | per key, plus the order | `columns[due]`, `columns[#order]` |
| repeated message | `{}` | the whole list | `columns` |
| repeated scalar | `{}` | the whole list | `tags` |
| oneof | `{}` on every member | the whole oneof | `payment` |
| any field | `{whole_state: true}` | the wildcard: conflicts with everything | `*notes` |

One example per marker:

```proto
message Item {
  string title = 1 [(io.angzarr.v1.conflict) = {}];     // unit: items[k].title (when descended)
  uint32 weight = 2 [(io.angzarr.v1.conflict) = {}];    // unit: items[k].weight
}

message Column {
  string id = 1;
  string name = 2;
}

message Settings {
  uint32 cooldown_days = 1 [(io.angzarr.v1.conflict) = {}];
}

message BoardState {
  option (io.angzarr.v1.state) = {
    conflict_resolutions: [CONFLICT_RESOLUTION_COMMUTATIVE]
  };

  // {}: a scalar is one unit.
  string title = 1 [(io.angzarr.v1.conflict) = {}];

  // descend: each item key, then each marked field of Item.
  map<string, Item> items = 2 [(io.angzarr.v1.conflict) = {descend: true}];

  // element_key + ordered: one unit per column id, plus columns[#order].
  repeated Column columns = 3 [(io.angzarr.v1.conflict) = {element_key: "id", ordered: true}];

  // descend into a message: settings.cooldown_days.
  Settings settings = 4 [(io.angzarr.v1.conflict) = {descend: true}];

  // whole_state: conflicts with any change, on purpose, with no warning.
  string notes = 5 [(io.angzarr.v1.conflict) = {whole_state: true}];

  // oneof: every member marked {}, one unit named "assignee".
  oneof assignee {
    string user = 6 [(io.angzarr.v1.conflict) = {}];
    string team = 7 [(io.angzarr.v1.conflict) = {}];
  }
}
```

Rules worth remembering:

- **An unmarked field conflicts with everything.** It reports the wildcard
  (`*settings`) when it changes, so COMMUTATIVE behaves like STRICT
  whenever that field moves. This is fail-safe, never a blind merge, and
  the generator warns about it (section 7).
- **`whole_state`** gives you that same behaviour, deliberately, and with
  no warning. Use it for a field that genuinely depends on the rest of the
  state.
- **Floats compare bitwise**, so `NaN` equals only an identical `NaN`, and
  `+0.0 ≠ -0.0`. Every language agrees.
- **A coarser unit overlaps the finer units inside it**: `items[42]`
  overlaps `items[42].weight`. Fallbacks are therefore always safe. A
  non-unique `element_key` falls back to the whole list, and `descend`
  stops at depth 32.
- Markers are read from **the code that runs `decide`**. They are never
  stored with events, so changing a marker affects resolutions from that
  deployment on, never history.

## 5. What "changed" means, and how COMMUTATIVE resolves

The generator emits one pure function per COMMUTATIVE state:

```
changed(before, after) -> set of unit paths
```

It returns the path of every unit whose value differs between the two
states. Two sets **overlap** when one contains a wildcard and the other is
non-empty, or when a path in one equals, or is a `.`/`[`-bounded prefix of,
a path in the other.

When a stale command arrives under COMMUTATIVE, the client library:

1. folds the state to `expected_sequence` (*expected*) and folds the window
   on top of it (*head*);
2. computes `window = changed(expected, head)`;
3. **runs `decide` on head**, never on expected;
4. computes `mine = changed(head, head + the command's events)`;
5. if `window` and `mine` are disjoint, keeps the events (acknowledging the
   conflict nonce for you). Otherwise the command fails `ABORTED`, exactly
   as under STRICT.

Step 3 is the important one. **Every invariant that `decide` checks is
checked against the current state**, including everything the window
changed. COMMUTATIVE never lets a command break a rule `decide` enforces.
What it cannot see is described in the next section.

Example with `ListState` (section 3), where the stale command and the window
each edit one item:

| | Paths | |
|---|---|---|
| window: Bob renamed item `b` | `{items[b]}` | |
| mine: Alice set item `a`'s weight | `{items[a]}` | disjoint: accepted |
| mine: Alice renamed item `b` too | `{items[b]}` | overlap: `ABORTED` |
| mine: Alice changed the settings | `{settings}` | disjoint: accepted |

## 6. The risk of COMMUTATIVE

**COMMUTATIVE compares structure, not meaning.** The diff sees which fields
changed. It cannot see that two fields in different units mean something
*together*: a value derived from another, two values that must change in
step, or a value whose meaning is relative to another. When your model has
such a dependency split across units, a stale command can merge when it
should not.

`decide` still runs on head, so a rule `decide` *checks* still holds. The
risk is **stale caller intent**: the caller looked at unit A, decided to
change unit B, and the window changed A.

Treat this as a **modelling failure**, and a likely one. It is easy to mark
fields one by one without asking which of them belong together. Whenever you
mark a state, ask of every pair of units: *can a change to one make an
earlier decision about the other wrong?* If the answer is yes, apply one of
these fixes:

1. **Put the dependent data in one unit.** Mark the containing message `{}`
   (without `descend`), or wrap a map or list in a message and mark that, so
   any change to the group conflicts with any other change to it.
2. **Derive rather than store.** Compute the dependent value in `decide`, or
   in a projection, from the data it depends on. A value nobody stores
   cannot go stale.
3. **Opt out for that command.** Configure the command type (or send
   `Handling.conflict_resolution`) as `STRICT`, or as `AGGREGATE_HANDLES`
   and write the conflict rule yourself.

### Failure 1: a derived value stored in its own unit

Suppose hatpick's settings also store a human-readable label that the
client computes from `cooldown_days`, and `settings` is descended:

```proto
message Settings {
  uint32 cooldown_days = 1 [(io.angzarr.v1.conflict) = {}];
  string cooldown_label = 2 [(io.angzarr.v1.conflict) = {}];   // "a week", computed by the client
}

message ListState {
  option (io.angzarr.v1.state) = { conflict_resolutions: [CONFLICT_RESOLUTION_COMMUTATIVE] };
  map<string, Item> items = 1 [(io.angzarr.v1.conflict) = {}];
  repeated Column columns = 2 [(io.angzarr.v1.conflict) = {}];
  Settings settings = 3 [(io.angzarr.v1.conflict) = {descend: true}];
}
```

1. Alice reads `cooldown_days = 7` at sequence 12, and sends
   `SetCooldownLabel { label: "a week" }` with `expected_sequence = 12`.
2. Meanwhile Bob's `SetCooldownDays { days: 30 }` appends event 12.
3. `window = {settings.cooldown_days}`, and
   `mine = {settings.cooldown_label}`. They are disjoint, so Alice's command
   is **accepted**.
4. The state now reads 30 days, labelled "a week".

The fixes:
- **One unit:** mark `settings` with `{}` rather than `{descend: true}`.
  Both commands then report `{settings}`, overlap, and Alice gets `ABORTED`.
- **Derive rather than store (the best fix):** delete `cooldown_label`.
  Render the label from `cooldown_days` in the client or a projection.
- **Opt out:** configure `SetCooldownLabel` as `STRICT`.

### Failure 2: values that are meaningful only relative to each other

hatpick draws an item with probability proportional to its weight. With
per-item units, `items[a]` and `items[b]` are disjoint:

1. Alice sees `a.weight = 1` and `b.weight = 1`, and wants `a` to be twice
   as likely as `b`. She sends `SetWeight { item: a, weight: 2 }` against
   that view.
2. Meanwhile Bob sets `b.weight = 4`.
3. `window = {items[b]}` and `mine = {items[a]}`. They are disjoint, so
   Alice's command is **accepted**.
4. `a` is now half as likely as `b`, the opposite of Alice's intent.

No invariant was broken: every weight is valid. Alice's *reason* was
relative to `b`, and the structure cannot express that. The fixes:
- **One unit:** group the weights.

  ```proto
  message Weights {
    map<string, uint32> by_item = 1;
  }

  message ListState {
    option (io.angzarr.v1.state) = { conflict_resolutions: [CONFLICT_RESOLUTION_COMMUTATIVE] };
    map<string, Item> items = 1 [(io.angzarr.v1.conflict) = {}];   // titles etc., per item
    Weights weights = 4 [(io.angzarr.v1.conflict) = {}];           // all weights: one unit
    repeated Column columns = 2 [(io.angzarr.v1.conflict) = {}];
    Settings settings = 3 [(io.angzarr.v1.conflict) = {}];
  }
  ```

  Any two weight changes now conflict. Item renames still commute.
- **Derive in decide:** make the intent explicit. Use
  `SetRelativeWeight { item: a, factor: 2, relative_to: b }`, and let
  `decide` compute `a`'s weight from `b`'s weight **on head**.
- **Opt out:** configure `SetWeight` as `STRICT`, or as `AGGREGATE_HANDLES`
  with a rule that refuses when another weight in the window changed.

### When COMMUTATIVE is the right default

COMMUTATIVE fits units that are **independent pieces of data that different
people edit**, such as list items, cards on a board or per-user
preferences. Before you mark a field, ask whether a reasonable caller would
decide its value by looking at another unit. If one would, the field
belongs in that unit, or should not be stored at all.

## 7. Build warnings and errors

The generator checks your markers when it reads the descriptors. Every
diagnostic names the file, line and element. The exact texts follow, with
`{…}` as placeholders. `{state}` and `{field}` are full proto names, such as
`hatpick.v1.ListState` and `hatpick.v1.ListState.settings`.

### Warning

**`unmarked-field`**
```
warning[unmarked-field]: {file}:{line}: field {field} has no (io.angzarr.v1.conflict) marker; in COMMUTATIVE state {state} it conflicts with every change
  = help: mark it, e.g. [(io.angzarr.v1.conflict) = {}], or keep this behaviour explicitly with [(io.angzarr.v1.conflict) = {whole_state: true}]
```
*Why:* the field is fail-safe (it reports the wildcard), but it is probably
a field that was added later and forgotten. It quietly turns COMMUTATIVE
into STRICT whenever the field changes.
*Fix:* mark it at the right granularity, or with `whole_state: true` if
conflicting with everything is what you want.

### Errors

**`no-marked-fields`**
```
error[no-marked-fields]: {file}:{line}: state {state} lists CONFLICT_RESOLUTION_COMMUTATIVE but marks no field with (io.angzarr.v1.conflict)
  = help: mark its fields, or remove COMMUTATIVE from its (io.angzarr.v1.state) option
```
*Why:* every change would conflict with every other change, which is
STRICT with extra work.
*Fix:* mark the fields, or drop the option.

**`unspecified-resolution`**
```
error[unspecified-resolution]: {file}:{line}: state {state} lists CONFLICT_RESOLUTION_UNSPECIFIED in (io.angzarr.v1.state)
  = help: list only CONFLICT_RESOLUTION_COMMUTATIVE (STRICT and AGGREGATE_HANDLES are always supported)
```

**`marker-outside-state`**
```
error[marker-outside-state]: {file}:{line}: field {field} carries (io.angzarr.v1.conflict), but {message} is neither a COMMUTATIVE state nor reachable from one by descend
  = help: add CONFLICT_RESOLUTION_COMMUTATIVE to the state's (io.angzarr.v1.state) option, mark the path to this message with {descend: true}, or remove the marker
```

**`descend-non-message`**
```
error[descend-non-message]: {file}:{line}: field {field} has descend, but it is not a message, a map of messages, or a repeated message with element_key
  = help: remove descend; scalars, scalar maps and scalar lists are compared whole
```

**`bad-element-key`**
```
error[bad-element-key]: {file}:{line}: field {field}: element_key "{key}" {reason}
  = help: element_key goes on a repeated message field and names a singular scalar, string, bytes or enum field of the element
```
`{reason}` is one of the following:
- `is set on a field that is not a repeated message`
- `names no field of {element}`
- `names {element}.{key}, which is not a singular scalar, string, bytes or enum field`

**`ordered-without-key`**
```
error[ordered-without-key]: {file}:{line}: field {field} has ordered but no element_key
  = help: add element_key; an unkeyed list is compared whole, order included
```

**`whole-state-combined`**
```
error[whole-state-combined]: {file}:{line}: field {field} combines whole_state with descend, element_key or ordered
  = help: whole_state is the whole marker: use {whole_state: true} alone
```

**`oneof-member-refined`**
```
error[oneof-member-refined]: {file}:{line}: oneof {oneof} member {field} {reason}
  = help: oneof members carry {} (one unit for the oneof) or, all of them, {whole_state: true}
```
`{reason}` is one of the following:
- `carries descend, element_key or ordered`
- `carries whole_state, but not every member does`

**`oneof-partially-marked`**
```
error[oneof-partially-marked]: {file}:{line}: oneof {oneof} has some members marked with (io.angzarr.v1.conflict) and some not
  = help: mark every member, or none
```

## 8. Build setup

The generator is one implementation of these rules. It ships in two
wrappers:

**Rust** (planned: backlog CR-1). Use `angzarr_build::compile` in
`build.rs`. It runs prost-build (with angzarr's settings: `bytes` as
`bytes::Bytes`, type names enabled) and then the generator over the same
descriptors:

```rust
// build.rs
fn main() {
    angzarr_build::compile(&["proto/hatpick/v1/list.proto"], &["proto"])
        .expect("compile protos");
}
```

For each COMMUTATIVE state it emits a `State` implementation beside the
prost type: the `StateDescriptor` constant and `changed(before, after)`.
Warnings are printed as `cargo:warning=` lines, and an error fails the
build.

**Every other language** (planned: backlog CR-1). Run `protoc-gen-angzarr`
next to your language's protobuf plugin:

```sh
protoc -I proto -I "$ANGZARR_PROTO" \
  --go_out=gen --angzarr_out=lang=go:gen \
  proto/hatpick/v1/list.proto
```

`buf generate` works the same way, with `protoc-gen-angzarr` as a local
plugin. Warnings go to stderr, and an error fails the generation.

One golden fixture suite (`parity/`) holds every language's output to the
same unit sets, and annals generates from the same markers.

## 9. Registration fills `StateDescriptor`

When your component registers with its coordinator, the client library
sends a `ComponentDescriptor`. Its `state` field is filled from the
generated descriptor. Do not write it by hand:

```rust
registry.register::<ListAggregate>();   // fills ComponentDescriptor.state from ListState's generated State impl
```

```proto
message StateDescriptor {
  string type_url = 1;        // "/hatpick.v1.ListState"
  StateOptions options = 2;   // the FULL resolved list: [COMMUTATIVE, STRICT, AGGREGATE_HANDLES]
}
```

The coordinator stays **domain-blind**. It never sees your schema, only this
list of enum values. From the list it takes the default (COMMUTATIVE if
listed, otherwise STRICT), and it refuses a command or a configuration that
names a resolution the list lacks (`INVALID_ARGUMENT`).

## 10. Versioning commands

Commands **can** be upcast. The client library runs an incoming command's
payload through the same upcaster chain as events, by type URL, before
dispatch. A command type URL with no handler and no upcaster path to one is
refused `INVALID_ARGUMENT`, naming the type URL.

**Prefer not to.** In order of preference:

1. **Evolve the command compatibly.** Add fields. In proto3 an absent field
   reads as its default, so old clients keep working. Never renumber or
   retype a field.
2. **Handle both versions in the domain during a transition.** Register a
   handler for the old type URL beside the new one, decide what the old
   command means (a business decision, not a schema one), and delete the
   old handler once the old clients are gone.
3. **Upcast, only as a migration aid with a planned removal.** Command
   upcasting hides stale clients: they keep working, so nothing tells anyone
   to upgrade them. It also adds machinery for data that is never stored.
   When you add one, record the date or release by which it is deleted.

Event upcasting has none of these caveats. Stored events never go away, so
their upcasters are permanent.

## 11. Re-running reactors

You shipped a saga or process manager with a bug, fixed it, and released a
new build (so a new `rules_version`, which is the build's version). The
events it caused are wrong. Re-running the reactor
will **not** fix them, by design. The normative text is the
`command_identity` region of `types.proto` (Reactor re-runs); the
reasoning is decision 13.4 and `docs/design/audit-meta/idempotency.md`.

**What deduplicates.** Each command a reactor emits gets a derived id:
UUIDv5 of the trigger event, the reactor's registered name and the
command's position in its output. Nothing about the reactor's code or
`rules_version` goes in. So if you reset the reactor's checkpoint and let
it run over triggers it already handled, it emits the same ids, and every
destination answers DUPLICATE with the events the first, buggy run
produced. A process manager's own process events dedupe the same way, on
the trigger they name (`EventMeta.causation.triggering_event`). Even if
the fixed code would now emit different commands, the re-run changes
nothing.

**History is never lost.** Nothing in angzarr overwrites, deletes or
re-sequences an event. The buggy-era events stay in their streams, and
stay readable, with the `rules_version` that produced them.

**Checkpoint resets are for recovery only**: re-delivering triggers whose
output never made it into the outbox (for example after restoring a
position store). Do not use them to repair.

**How to repair: issue new commands.**
1. Find what to fix. `GetCorrelatedEvents` gives you each affected
   workflow; `EventMeta.rules_version` tells you which events the buggy
   version decided. (Which trigger led to which reaction command is in the
   coordinators' traces, not on the events; see `CorrelationQuery`.)
2. Decide the correction as a business question. Often it is a
   compensating command ("reverse charge", "reissue reminder"), not "do it
   again": downstream readers may already have acted on the wrong events.
3. Send it as NEW commands, each with a fresh `command_id` (let the SDK or
   coordinator mint it). New ids apply; their events append after the old
   ones, with later sequence numbers, and projections see the correction.
4. Where the fix is "run the corrected reactor over these triggers", use a
   re-drive: a new command whose events the fixed reactor reacts to.
   angzarr will ship standard re-drive commands for this (backlog RD-1);
   until then, define one in your domain.

**Risks.**
- **Assuming a reset repairs.** It does not, silently: every command is
  answered DUPLICATE and the dashboards look healthy. Check that your fix
  produced new events.
- **Repairing twice.** A repair command is an ordinary command: give each
  correction one id and reuse it on retry, or a retried repair applies
  twice.
- **Readers of the old events.** Projections, external sinks and other
  reactors have already seen the buggy events. A correction must make sense
  to them as a new fact, which is why compensating commands are usually
  better than replays.
- **Reaction ids are frozen.** Never rename a reactor's registered name to
  "force" new ids: renaming changes every id it derives from then on, so
  any trigger it handles again (a reset, a redelivery not yet in the
  outbox) applies a second time, with no record of why.
