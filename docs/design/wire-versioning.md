# Wire versioning: a package per break, a stamp per store

Decision 14.113 (owner ruling, 2026-11-26; its open questions ruled
2026-11-27: the legacy package is `v0` and the current stays `v1`; a legacy
store with pending outbox or dead-letter rows refuses to open; a per-row
`wire` column, no eager re-encode). This is the behaviour; the decision log
has the ruling and its cost. Built: the frozen `proto/io/angzarr/v0`,
`proto/FROZEN`, `scripts/check_frozen_protos.py`, `proto/WIRE_BASELINE` and
their gates in this repository; `angzarr_proto::wire`, migration 0009 and the
store's stamp in angzarr (`crates/angzarr-store-sqlite`). The scenarios are
`features/coordinator-contract/wire_versioning.feature`.

## 0. The problem, as it happened

`io.angzarr.v1` was renumbered in place between angzarr 4d7ef35
(angzarr-project 9999733) and 3c301452 (angzarr-project c4b87ed). A store
keeps each event page and snapshot as the protobuf bytes its writer made, so
a store written before the renumbering decodes under the new schema
*wrongly or not at all*: `Cover`'s `domain` and `root` swapped numbers and
both are length-delimited, so a Cover decodes without error into the wrong
fields; `EventPage.sequence` moved from a varint at 9 to a varint at 3, where
the old payload (length-delimited) now sits, which fails decode
(`invalid wire type: LengthDelimited (expected Varint)`, the red tests'
failure today). Twenty-seven taskloom stores were written before it.

The reservation policy in `proto/buf.yaml` (D6: removed numbers are
reserved, "an incompatible change is a new message version plus an
upcaster") already says what should have happened. It did not hold because
nothing made a *package* the unit of a break and nothing recorded which
version wrote a store.

## 1. Packages: one per break, old ones frozen

- A package is `io.angzarr.v<N>`; `<N>` is its **ordinal**, the number a
  store records. Today: `v0` (the 4d7ef35 envelope, **frozen**) and `v1`
  (the current one, **released**, not yet frozen).
- **Every wire break gets a new package.** A break is anything `buf breaking
  --use WIRE_JSON` reports (a number or type changed, a field or value
  removed, a name changed) in the **stored set**.
- **The stored set** is every message a store persists as a page or a
  snapshot, with the messages they contain: `EventPage` (`EventMeta`,
  `CommandCause`, `FactCause`, `FactOrigin`, `MetaEvent`, `EditionCreated`,
  `UUID`) and `Snapshot`. (Dead letters and the outbox hold whole transient
  messages of a package and are not in it: §4, "Transient rows".) `google.protobuf.Any` payloads are the
  domain's own, opaque here, and versioned by upcasting (upcasting.md).
  A new package is a **complete copy of the stored set** with the change
  applied, never a diff: a version's decoder is self-contained.
- **Freezing.** The commit that creates `v<N+1>` adds `v<N>` to
  `proto/FROZEN` (format in §5) in the same commit, so `v<N>` is immutable
  from the moment it stops being current. A frozen package is never edited,
  never deleted, never renamed and never gains a file, whatever the change
  (a comment included: the files are compiled byte for byte into
  `angzarr-proto`, and the digest is the proof).
- **Released, not frozen.** The current package accepts non-breaking
  additions (a new optional field, a new message). Anything `buf breaking`
  reports is refused with no exception (14.88); the way through is the next
  package.
- **`v0`** is created by this decision: `proto/io/angzarr/v0/stored.proto`,
  package `io.angzarr.v0`, holding the stored set exactly as angzarr-project
  9999733 had it (§2's table), frozen at once. It is the *only* old shape a
  store can hold: nothing older was ever written to a store.
- Other layers (`handler`, `transport.*`, `component`) are transient RPC
  surfaces, not stored, and keep their own `v1`; a break there is the same
  rule (new package) but needs no stamp or decoder.

## 2. The mapping, old to new

`io.angzarr.v0` -> `io.angzarr.v1`, field by field (values copied; a field
absent stays absent). Source: angzarr-project 9999733 `types.proto` against
c4b87ed.

| Message | v0 (4d7ef35) | v1 (3c301452) | Mapping |
|---|---|---|---|
| `Cover` | `root`=1, `domain`=2, `edition`=4 | `domain`=1, `root`=2, `edition`=4 | swap 1/2; `edition` same |
| `UUID` | `value`=1 | `value`=1 | same |
| `FactOrigin` | `external_id`=1, `description`=2 | same | same |
| `EventPage` | `payload`=3 (Any), `meta`=8, `sequence`=9 | `body`: `event`=1 (Any) / `meta_event`=4; `meta`=2; `sequence`=3 | `payload` -> `body.event`; `meta` 8 -> 2; `sequence` 9 -> 3; `meta_event` never set |
| `EventMeta` | `causation.command_id`=17 (UUID, always set), `fact`=16 (FactOrigin, set iff the producer was a Fact), `correlation_id`=14, `recorded_at`=5, `rules_version`=7 | `causation`: `command`=1 (`CommandCause{command_id}`) / `fact`=2 (`FactCause{command_id, origin}`); `correlation_id`=3; `recorded_at`=4; `rules_version`=5 | `fact` unset: `causation.command = CommandCause{command_id}`; `fact` set: `causation.fact = FactCause{command_id, origin: fact}`; 14 -> 3; 5 -> 4; 7 -> 5 |
| `Snapshot` | `sequence`=2, `state`=3 (Any), `rules_version`=5 | `sequence`=1, `state`=2, `rules_version`=3 | 2 -> 1; 3 -> 2; 5 -> 3 |
| `AngzarrDeadLetter`, `CommandBook`, `ReactionDelivery` | whole-message rewrites (oneofs, `Handling` moved, `CommandPage` renumbered) | | **not mapped**: transient; see §4 "Transient rows" |
| `Any`, `Timestamp` | well-known | | unchanged |

(`EventBook` and `Projection` are never stored; the store keeps pages and
snapshots separately, and the `events.command_id`, `correlation_id`,
`recorded_at` columns are copies the store makes itself.)

**Where it lives.** In `angzarr-proto` (the crate generated from this
repository's `proto/`), because the mapping is pure and every consumer of a
stored page needs the same one:

- `angzarr_proto::wire::v0`, the frozen messages as prost structs spelled by
  hand, field for field as `stored.proto` has them (a frozen package cannot
  drift, and the crate builds against a spec pin that predates the file; once
  every pin carries it, build.rs may generate them from it instead), and the
  generated `v1`;
- `angzarr_proto::wire`: `WireVersion`, `WIRE_CURRENT`, the shape detector
  (§6), and `decode_page(wire, bytes)`, `decode_snapshot(wire, bytes)`,
  which decode as the package the ordinal names and return the **current**
  type, applying each package's step to its successor in order
  (`upgrade::v0_to_v1`, `v1_to_v2`, ...); a package defines only its step to
  the next, so adding `v2` never touches `v0`'s mapping.
- encoding is only ever current: `EventPage::encode` is v1's. There is no
  way to ask the library to write an old package.

**"Deserialize to the old version, write the new"** is then literal: a
reader decodes with the old package's types (exactly what the old writer
meant), maps to the current types, and every write, by anyone, is current.
A store therefore holds, over its life, rows of several versions; each row
says which (§4). Nothing rewrites an old row unless asked (`rewrite_to_
current`, §7).

**Shipping.** Every package a store could hold stays compiled in
(`angzarr-proto` ships `v0` and `v1`). Dropping a decoder is a later
decision and requires every supported store to have been rewritten; it is
not done by deleting a frozen file, which the gate refuses.

## 3. How a reader picks a decoder

In order, at the store's open and then per row:

1. **The stamp.** If the store has a `wire_stamp` row, `newest` greater than
   this build's `WIRE_CURRENT` -> **refuse the open**,
   `angzarr-ports-store-wire-newer-than-build{stamped, build}`, store
   untouched (no migration, no write). This is checked before any row is
   read, and complements the migration ledger's own newer-than-build check
   (a build that knows migration 0009 but not `v2`).
2. **The row.** Each `events` and `snapshots` row carries `wire`, the ordinal
   of the package that wrote it. The decoder is that package's; an ordinal
   this build has no decoder for (and was not refused by 1, i.e. a store
   hand-edited) is `...wire-unknown-version{wire}`; an unstamped row
   (`wire = 255`, §4) after the backfill is a bug and is refused the same
   way.
3. **No stamp: shape detection, once.** A store whose migration 0009 is
   being applied now has no stamp. The one-time backfill classifies every
   row by its bytes (§6), writes each row's `wire` and the stamp, and is
   recorded done (`backfills` row `wire-stamp`), so no later open scans.
4. **Neither shape: refuse.** A row that is no recognisable shape, or a legacy
   row after a current row in one stream, refuses the open
   (`...wire-unrecognised{table, stream, sequence}`), and the open, being
   one `BEGIN IMMEDIATE` transaction (the existing `run_to`), rolls back
   whole: no stamp, no column, the file as it was (the pre-migration backup
   exists as well, as for every migration).

## 4. The stamp

```sql
-- 0009_wire_stamp.sql
CREATE TABLE wire_stamp (
    id     INTEGER PRIMARY KEY CHECK (id = 1),   -- one row
    oldest INTEGER NOT NULL,                      -- lowest ordinal a row may hold
    newest INTEGER NOT NULL,                      -- highest ordinal ever written
    CHECK (oldest <= newest)
);
ALTER TABLE events    ADD COLUMN wire INTEGER NOT NULL DEFAULT 255;  -- 255: not yet stamped
ALTER TABLE snapshots ADD COLUMN wire INTEGER NOT NULL DEFAULT 255;
```

- **Per row, not per store only**, because "write the new" over a legacy
  store makes a store of two versions; one number per store cannot say which
  rows are which, and the detector cannot be re-run safely once rows of both
  shapes coexist in one stream.
- **Who writes it: the store adapter, in the write's own transaction.** Every
  row inserted carries `wire = WIRE_CURRENT` and the same transaction runs
  `UPDATE wire_stamp SET newest = max(newest, WIRE_CURRENT)`. A read-only
  open writes nothing. `oldest` is a lower bound: set once by the backfill
  to the lowest ordinal found (`WIRE_CURRENT` for an empty store), moved up
  only by `rewrite_to_current` (to `WIRE_CURRENT`); a purge does not
  recompute it.
- **When, for each kind of store.**
  - *New store:* migration 0009 plus the backfill see no rows and insert
    `(CURRENT, CURRENT)`.
  - *Existing unstamped store (a pre-0009 build's, including the 27 taskloom
    stores):* the first open by a 0009 build backs it up (existing
    `Backup`, `state.db.pre-8-<time>`), applies 0009, runs the backfill: all
    rows classified by shape; verdicts stamped. A store of only 4d7ef35 rows
    is `(0, 0)`; of only current rows `(1, 1)`; of both `(0, 1)`.
  - *Existing stamped store, newer build:* nothing on open; `newest` rises
    with the first write.
- **Transient rows.** `outbox` and `dead_letters` hold whole transient
  messages (`Any` of `CommandBook`/`ReactionDelivery`, `AngzarrDeadLetter`),
  rewritten wholesale between v0 and v1. The backfill refuses a legacy store
  (any row classified v0) with a non-empty `outbox` or `dead_letters`:
  `...wire-legacy-transient{outbox, dead_letters}` counts, untouched. This is
  deliberately loud: the angzarr export already refuses a pending outbox
  (D5 (a)). Whether to relax it is open question 2.

## 5. The buf gate

Two checks, both in `just contracts`, CI and the pre-push hook.

**(a) Breaking change in the current (non-frozen) packages: refused, no
exception.** The existing `proto-breaking` (`buf breaking`, WIRE_JSON,
against the merge base with the spec draft) stays. It is *relative*: a
break committed straight onto the draft has no earlier base to be compared
with, which is how an in-place renumber can pass (the reading of how
3c301452 landed; not verified against the draft's history). So the
baseline becomes absolute: `proto/WIRE_BASELINE` holds one full commit SHA,
the last released protos; `proto-breaking` also runs `buf breaking
--against <WIRE_BASELINE>`. `WIRE_BASELINE` may only move to a commit that
is itself `buf breaking`-clean against the previous baseline, so moving it
cannot launder a break; a human moves it when cutting a release. What it
guards, exactly: a wire-breaking edit to any package (frozen or not) that is
committed where there is no earlier base to differ from, such as straight
onto the draft, or after a history reset, is refused against the released
commit it names. It guards nothing the baseline itself already contains: a human who
moves it to a clean successor accepts that successor as released; a break inside a branch
that is repaired before it merges is not seen.

**(b) Any change to a frozen package: refused.** `proto/FROZEN` is a
manifest, `sha256sum`'s format with a package header:

```
package io.angzarr.v0 dir=io/angzarr/v0
<64 hex>  io/angzarr/v0/stored.proto
```

`scripts/check_frozen_protos.py --proto-dir proto --base-manifest <FROZEN at
the merge base>` fails if: a listed file's digest differs or the file is
gone; a file exists under a frozen `dir` that is not listed (a new file);
an entry present in the base manifest is missing or differs in this one (a
package cannot be unfrozen, nor its manifest edited to match an edited
file); a listed `package` line's package name is not what the files declare.
A new `package` block with matching digests is allowed (that is freezing).
Unit tests: `scripts/test_check_frozen_protos.py`, run by `test-check-
frozen-protos` (in `just test`); the recipe `proto-frozen` runs it for real
and joins `contracts`. angzarr's `angzarr-proto` build script repeats the
digest check over the files it embeds, so a stale pin cannot compile a
changed frozen file.

`buf lint`'s `PACKAGE_VERSION_SUFFIX` is already excepted; nothing in lint
changes. `buf breaking` is not used for (b): it cannot forbid an additive
change, and a frozen package must refuse even those.

## 6. The legacy shape detector (4d7ef35)

A pure function of the stored bytes, in `angzarr_proto::wire`, no schema and
no prost: it reads the top-level tags (varint `field << 3 | wire type`) of a
page or snapshot and nothing deeper.

**Page** (the `events.page` blob). Let `S` be the set of `(field, wire type)`
at the top level.

| Evidence | Meaning |
|---|---|
| `(3, LEN)`, `(8, LEN)`, `(9, VARINT)` | v0 only (`payload`, `meta`, `sequence`) |
| `(1, LEN)`, `(2, LEN)`, `(4, LEN)`, `(3, VARINT)` | v1 only (`event`, `meta`, `meta_event`, `sequence`) |
| any other field or wire type | neither |

Verdict: **V0** iff `S` holds v0 evidence and no v1 evidence and no other
field; **V1** iff the reverse; otherwise **Unrecognised**. It is decisive
because field 3 is a message in v0 and the sequence varint in v1 (different
wire types), and every persisted page carries the `payload`/`event` and
`meta`, so even a sequence-0 page (sequence omitted) has evidence. The
decoded page's `sequence` must equal the row's `sequence` column, or the row
is Unrecognised (a cross-check against a coincidence).

**Snapshot** (`snapshots.snapshot`). Field 2 is the sequence varint in v0
and the state message in v1: `(2, VARINT)` -> V0; `(2, LEN)` -> V1; field 2
absent -> V0 iff `(3, LEN)` is present (a v0 snapshot at sequence 0) else
Unrecognised. Fields outside `{1,2,3}` (v1) or `{2,3,5}` (v0) -> Unrecognised.

**Store verdict**, per row. The store is stamped from its rows: any
Unrecognised row, or a V0 row after a V1 row in the same stream, refuses the
open (§3.4). An empty store is current.

**Runs once.** The backfill is under the migration's lock and recorded done
in `backfills` (`wire-stamp`); afterwards every row says `wire`, and the
detector is never run on a stamped store (and `detect_wire_at` is a read-only
diagnostic, not part of the open). A refused store is not marked done.

## 7. The API the taskloom migration calls

taskloom upgrades its pin, then opens each store as it opens any. The open
does the one-time work (backup, 0009, detection, stamping). What it adds to
call, and may log:

```rust
// angzarr-ports
pub struct WireVersion(pub u8);            // the ordinal; WireVersion::V0, V1
impl WireVersion { pub const CURRENT: WireVersion; pub fn package(self) -> &'static str; }
pub struct WireStamp { pub oldest: WireVersion, pub newest: WireVersion }

// angzarr-store-sqlite, beside ledger_at
impl SqliteStore {
    /// Read-only; migrates nothing. None: no file, or pre-0009 (unstamped).
    pub async fn wire_stamp_at(path: &Path) -> Result<Option<WireStamp>, StoreError>;
    /// Read-only dry run of the backfill: counts rows per shape, and what
    /// the open would refuse, without writing. For a pre-flight over many stores.
    pub async fn detect_wire_at(path: &Path) -> Result<WireDetected, StoreError>;
    pub async fn wire_stamp(&self) -> Result<WireStamp, StoreError>;
    /// Optional. Re-encodes every old row (and snapshot) as the current
    /// package in one transaction, then `oldest = CURRENT`. Not needed to
    /// read; needed only before a decoder is dropped.
    pub async fn rewrite_to_current(&self) -> Result<WireRewritten, StoreError>;
}
pub struct WireDetected { pub pages: ShapeCounts, pub snapshots: ShapeCounts, pub refusal: Option<StoreError> }
pub struct ShapeCounts { pub v0: u64, pub v1: u64, pub unrecognised: u64 }
```

New `StoreError` variants, each with a code (crate-prefixed `angzarr-ports-
store-...`), args and an en-US message, as every store error has:

| Variant | Code | When |
|---|---|---|
| `WireNewerThanBuild { stamped, build }` | `...-wire-newer-than-build` | stamp `newest` above this build |
| `WireUnrecognised { table, stream, sequence }` | `...-wire-unrecognised` | a row fits no shape, or is out of order |
| `WireUnknownVersion { wire }` | `...-wire-unknown-version` | a row's ordinal has no decoder |
| `WireLegacyTransient { outbox, dead_letters }` | `...-wire-legacy-transient` | §4 |

A taskloom run over its 27 stores: `detect_wire_at` for each (the report),
then `open` each (stamps), then `wire_stamp()` equals `(V0, V0)` for an
untouched legacy store. The red tests in `wire.test.rs` are this contract at
the SQL level.

## 8. What this does not do

- It does not version `Any` payloads (upcasting.md does).
- It does not make the transient messages (`CommandBook`, RPC types)
  survive a break; they are not stored.
- It does not decide when a decoder may be dropped.
- `angzarr-store-transfer`'s JSON export carries a `generation` header for
  an importer to pick a mapping by; with the stamp, that header becomes the
  stamp's `newest` ordinal, and its importer maps through
  `angzarr_proto::wire` instead of a mapping of its own. Not done here.
