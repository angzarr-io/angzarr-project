# Acceptance Test Remediation Plan

**Created**: 2026-05-06 — companion to `WIP_TRIAGE.md`. Captures the
architectural fixes uncovered while landing batch 16 cluster
acceptance scenarios EA-0011/0012/0013.

## Trigger

EA-0013 surfaced a sequence-mismatch race: the test step manually
fanned `EnterTableHandForHand` to each table while the deployed
`saga-h4h-fanout` was doing the same, two writers competing for the
same per-aggregate sequence. Walking back from "race" to root cause
revealed that:

1. **No production PM owns the H4H workflow.** Orchestration was
   split awkwardly across (a) tournament aggregate's pending-tables
   arithmetic, (b) two stateless sagas, (c) the test step itself
   acting as an ad-hoc orchestrator.
2. **Every assertion is a bookkeeping mirror, not an aggregate read.**
   `Then tournament X has status Y` reads `context.tournaments[X]
   ["status"]` — a value the corresponding `When` step assigned
   locally. The test would pass even if the deployed coordinator
   silently dropped every command.
3. **Polling-with-timeout is the cross-aggregate observation
   primitive.** `within N seconds` loops with `time.sleep(0.1)`
   simulate eventually-consistent waits with implicit deadlines.
4. **The test sometimes acts as a process manager.** Subscribing to
   downstream effects, firing follow-on commands — that's PM-shaped
   behavior in a place that should be a thin observer.

## Part 1 — `pmg-hand-for-hand` (immediate)

Move H4H lifecycle orchestration into a real PM.

### 1a. Proto

* New PM-domain `pmg-hand-for-hand` (parallels `pmg-reservation`).
* State: `correlation_id` (= bubble entry, derived from
  `tournament_root` + `started_at`), `active_tables: repeated bytes`,
  `pending_tables: repeated bytes`, `round_number: int32`,
  `status: enum { ACTIVE, ENDED }`.
* No new commands needed beyond what already exists
  (`EnterTableHandForHand`, `EndTableHandForHand`,
  `RecordHandForHandRoundComplete`).

### 1b. Tournament aggregate strip-down

* Remove `state.hand_for_hand_pending_tables`,
  `hand_for_hand_active_tables`, `hand_for_hand_round`.
* Remove `RecordTableHandComplete` + `RecordHandForHandRoundComplete`
  handlers (move to PM).
* `EnterHandForHand` simply emits
  `HandForHandStarted{active_table_roots}`. PM picks it up.
* `EliminatePlayer` no longer emits `HandForHandEnded` directly —
  the PM detects the bubble break and emits it via tournament cmd.
* `state.hand_for_hand: bool` stays as a marker (read by other
  aggregate logic), but driven by `HandForHandStarted` /
  `HandForHandEnded` apply only.

### 1c. PM handlers

| Source event | PM action |
|---|---|
| `HandForHandStarted` (tournament) | seed PM state with `active_tables` + `pending_tables`; send `EnterTableHandForHand{tournament_root}` to each table |
| `TableHandForHandRoundComplete` (table) | discard `table_root` from `pending_tables`. If empty → send `RecordHandForHandRoundComplete` to tournament |
| `HandForHandRoundComplete` (tournament) | re-seed `pending_tables = active_tables`, increment `round_number`, send `EndTableHandForHand` + `EnterTableHandForHand` to each table |
| `PlayerEliminated` (tournament, while `state.status==ACTIVE`) | send `RecordHandForHandEnded` to tournament; fan `EndTableHandForHand` to each table; mark PM lifecycle complete |

### 1d. Saga removal

* Delete `saga-h4h-fanout` + `saga-tournament-h4h` Python source,
  Containerfile targets, k8s manifests.
* The proto fields they relied on stay — the PM uses them
  (`active_table_roots` on events, `tournament_root` on table
  events, `RecordTableHandComplete` cmd).

### 1e. Containerfile + k8s

* Add `pmg-hand-for-hand` Containerfile target (mirrors
  `pmg-reservation`).
* Add deployment manifest under `deploy/k8s/`.

### 1f. PM unit tests

Mirror the existing batch-10 unit tests but in PM-shaped form (state
rebuilt per dispatch from prior events; handlers tested against
fixture event books).

## Part 2 — `BusListener` test infrastructure

### 2a. AMQP exposure

Add `NodePort` service for `angzarr-mq:5672` (mirrors the per-
aggregate debug NodePorts). Production cluster manifest concern; on-
cluster traffic still uses `ClusterIP`.

### 2b. `BusListener` class

* Subscribes to `angzarr.events` exchange via `aio-pika` (or `pika`
  in a thread).
* Per-`(domain, root, type_url)` registration:
  `await_terminal_events(specs, timeout)` blocks on a `queue.get`
  until each spec has matched at least one delivery.
* Shared per-test-suite (started in `before_all`, drained between
  scenarios in `before_scenario`).

### 2c. Step-def shape

* New helper:
  `expect_terminal(context, command_response, *terminal_specs)`.
  Sends the command (ASYNC), reads immediate events from
  `response.events.pages`, awaits the rest from the bus.
* Each Gherkin `When` step → one command + a list of terminal
  events.
* Each `Then …emitted` step → assertion on the just-received
  deliveries (no separate query, no polling).
* `Then X has status Y` style steps → query event store once (or
  read PM state directly), never in-test bookkeeping.

## Part 3 — Systemic broken patterns (scan results)

### Pattern A — Bookkeeping mirrors instead of aggregate reads

**~30 occurrences across all 5 step files.** Every `Then …` assertion
reads from `context.{players,tables,tournaments,reservations}[name]
[field]` that the corresponding `When …` step assigned locally. None
verify aggregate state. Verbatim comment in `tournament_steps.py:347`:

> Assert tracked status — the cluster-side assertion is the command
> succeeding at each step, which this mirrors.

Specifically:

* `tournament has status Y`, `has N registered players`,
  `has players_remaining N`, `has current_level K`,
  `has total_prize_pool P`, `winner is P` — read
  `context.tournaments[name][...]`.
* `player has bankroll/available balance/reserved funds N` — read
  `context.players[name][...]`.
* `table has N seated players` / `hand_count N` — read
  `context.tables[name][...]`.

Affected: every cluster acceptance scenario (EA-0006 through
EA-0013). The test passes because the When step writes the same
value the Then step reads. If the deployed coordinator silently
dropped commands, the test would still pass.

### Pattern B — `within N seconds` polling

3+ occurrences in `cluster_steps.py` + `common_steps.py`. Hot loops
with `time.sleep(0.1–0.25)` inside
`while time.time() < deadline`:

* `step_then_within_player_reachable` — pings player coordinator
* `step_then_within_player_projection_bankroll` — re-reads
  bookkeeping
* `step_then_within_seconds_event` — polls for an event
* `hand_steps.py:836` deadline loop

### Pattern C — Sequence-mismatch retry workaround

`tournament_steps.py` `_send_table_command` catches
`Sequence mismatch`, parses the aggregate's actual position from the
error string, retries. Symptom of test + saga both writing.

### Pattern D — Test ad-hoc orchestrating saga/PM work

`step_when_enter_bubble` directly fans `EnterTableHandForHand` to
each table; `step_then_both_can_start` sends `EndTable` +
`EnterTable` per table. The test is acting as the H4H process
manager. Same shape as Pattern C — duplicate writers.

### Pattern E — Stub `When` step

`step_when_a_hand_completes` is a stub — fast-forward only, doesn't
verify a hand played. Acceptable for non-betting H4H scenarios but
worth flagging.

## Part 4 — Remediation pattern (apply uniformly)

**Every Gherkin step that follows the `When … Then …` shape
becomes:**

1. **`When`** — single command, ASYNC. Capture `response`.
2. **`Then`** — one of three forms, none of which touch in-test
   bookkeeping:
   * **Direct**: read from `response.events.pages` (immediate
     aggregate's writes — guaranteed by writes-before-return).
   * **Cascade**: `BusListener.await_terminal_events(...)` for
     events from PMs/sagas/other aggregates.
   * **Rejection**: read from `response.error` (synchronous failure
     path).

`context.{players,tables,tournaments,reservations}[name]` keeps only
**routing data** (UUIDs, names) — never copies of aggregate state.

## Rollout order

1. **Land Part 1** — `pmg-hand-for-hand` PM, strip sagas + tournament
   round-arithmetic, prove EA-0013 still green via existing test
   path. (Confirms PM is correct before the test refactor.)
2. **Land Part 2** — `BusListener` + AMQP NodePort. Migrate EA-0013
   step defs to the `(command, terminal-events)` shape. Validates
   the new test pattern on the most complex scenario.
3. **Strip Pattern A from `tournament_steps.py`** — every
   `tournament X has Y` Then step reads from event store / response
   events. (Largest single mirror-based file.)
4. **Strip Pattern A from `player_steps.py` and `table_steps.py`** —
   same treatment.
5. **Strip Pattern B** — replace `within N seconds` polls with
   `BusListener.await_terminal_events`.
6. **Strip Pattern C** — `_send_table_command`'s retry workaround
   becomes unnecessary once Pattern D is gone.
7. **Strip Pattern D** — H4H test fan-outs disappear with the PM
   landing in step 1; remaining ad-hoc saga work in other scenarios
   gets converted on contact.

## Cross-language note

Pattern A in particular is likely mirrored in every
`examples-{lang}/main/acceptance_steps/` (each client has its own
copy of the step definitions). Once Python's pattern is fixed, the
shape is the structural template per
``feedback_python_is_structural_template.md``; Rust / Go / Java /
C# / TypeScript each get the same remediation. The cucumber feature
files don't change — only the language-specific step impls.

## Open questions

* PM correlation_id derivation: derived from `tournament_root +
  bubble_entry_seq`? Or operator-supplied? (Affects multi-bubble
  tournaments — same tournament can enter H4H, exit, then re-enter
  if there's a re-bubble; each entry needs its own PM instance.)
* Where does `BusListener` live? Shared utility under `tests/`, or
  per-stage? Probably `tests/bus_listener.py` since it's general-
  purpose acceptance infra.
* `RecordHandForHandEnded` proposed in 1c — does it need its own cmd
  on tournament, or fold into `EliminatePlayer` somehow? Cleanest
  is a new explicit cmd: PM is the one detecting bubble break, PM
  fires the cmd; tournament aggregate just emits the event from
  the cmd. Avoids tournament aggregate caring about H4H state at
  all beyond the marker bool.
