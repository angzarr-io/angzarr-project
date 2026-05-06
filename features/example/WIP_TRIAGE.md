# @wip Implementation Triage & Plan

**Created**: 2026-05-05 — companion to `RULES.md` (which mapped every TDA
2024 / WSOP 2025 / TDA-RP / Robert's rule to a scenario). This document
plans the implementation work to un-`@wip` all 127 spec-driven scenarios.

## Current state

- **707 scenarios pass** (`uv run behave --tags="~@wip"`) on the Python
  example coordinator. **Zero scenarios remain @wip.**
- All 16 batches landed in this session (2026-05-05). Cross-language
  regen for Rust/Go/Java/C#/TypeScript is pending — proto changes
  accumulated in this push need the cascade.
- **6 client repos** (Python, Rust, Go, Java, C#, TypeScript) consume
  these features. Per `feedback_cucumber_fixes_in_angzarr_project.md`,
  the proto cascade for this push must visit each client; bump every
  submodule pointer once Python's pinned-shape settles.

### What's done (Batches 1-8, plus partial 11/12/14/15)

Batches 1-8 + Batch 7's incidentally-passing scenarios cover the
heavy-lift work: foundational proto plumbing, limit/PL/NL betting,
verbal/chip mechanics, misdeal/premature-card taxonomy, OOT taxonomy,
showdown / tabling / refunds, action clock, all stud variants, and
much of the misc-edge-cases batch. Per-batch detail lives in the
`Tracking` section below.

### What's left (~34 scenarios)

- **Batch 9** (chip race, 3 scenarios) — EU-1160..1162. Tournament
  aggregate work; needs `ChipRaceCompleted` event and the
  single-chip-rescue conservation invariant.
- **Batch 10** (hand-for-hand, 3 scenarios) — EU-1190..1192.
  Tournament saga: H4H state, per-hand level-clock deduction,
  simultaneous-bust split-payout.
- **Batch 11** (1 left) — EU-1311 needs inter-aggregate coordination
  between Penalty saga and Hand (cards dealt then killed for a player
  already on penalty).
- **Batch 12** (~5 scenarios) — late reg / no-show / seat redraw.
- **Batch 13** (~10 scenarios) — table balancing, initial-button rule,
  final-table combination matrix, dodging-blinds penalty.
- **Batch 14** (~7 scenarios) — tournament admin (rebuy plays behind,
  re-entry chip removal, HORSE rotation order, bounty edges,
  end-of-day / day-2 resume saga).
- **Batch 15** (1 left) — EU-1361 (hidden chip behind), EU-1365 (tied
  late-reg seat tiebreak); each needs one new event type.
- **Batch 16** (3 cluster acceptance scenarios — EA-0011/0012/0013).
  Multi-coordinator E2E; gates on Batch 9 / Batch 10 / Batch 13.

Plus a handful of scattered EU-12xx scenarios (level change EU-1210/1211,
underraise correction EU-1250, absent-at-deal EU-1145/1146, rebuy
EU-1150) — each fits within an existing batch above.

## Effort scale

- A single self-contained scenario with no proto change: **~30-90 min**
  (step defs + maybe a handler tweak).
- A scenario that pulls in **new commands/events/proto fields**: **half
  to a full day** including codegen and 6-language verification.
- A scenario that pulls in **a new game variant or betting format**:
  **multiple days** (Stud, Limit/PL).

**Rough total**: 10-14 weeks of focused single-developer work to land
all 127. Working in parallel batches with cross-language verification
in CI, a small team could compress this to 4-6 weeks.

## Dependency graph

```
A. Stud variants (22 scenarios)
   └──► requires Group C (misdeal/premature) for stud-specific misdeals
B. Limit / Pot-Limit betting (5 scenarios)
   └──► standalone proto extension; no other group depends on it
C. Misdeal & premature cards (12 scenarios)
   └──► standalone; A reuses its primitives
D. Out-of-turn taxonomy (5 scenarios)
   └──► standalone
E. Verbal/chip betting mechanics (15 scenarios)
   └──► requires Group B's RaiseDeclaration/AllInDeclaration proto
F. Action clock & timing (3 scenarios — EU-1130..1132)
   └──► standalone; new StartActionClock command
G. Chip race (3 scenarios)
   └──► requires tournament aggregate's color-up state
H. Hand-for-hand (3 scenarios + cluster)
   └──► requires tournament saga state
I. Penalties (4 scenarios)
   └──► standalone; PlayerPenalized event
J. Late reg / no-show / seat redraw (5 scenarios)
   └──► requires tournament + table coordination saga
K. Pot distribution refunds (2 scenarios — EU-1260, 1261)
   └──► extends pot_distribution.py
L. Showdown / tabling (4 scenarios)
   └──► extends hand showdown machine
M. Table balancing & button (10 scenarios)
   └──► requires table-coordination saga
N. Tournament admin (7 scenarios)
   └──► requires several saga + PM additions
O. Misc edge cases (8 scenarios)
   └──► spread across hand + tournament
P. Cluster acceptance (3 EA scenarios)
   └──► requires manifest + saga work; gates on M, H
```

Critical path: **B → E** (verbal/chip mechanics depend on RaiseDeclaration
proto messages). **C → A** (stud uses misdeal primitives). **M, H → P**
(cluster scenarios gate on table-coordination saga and H4H).

## Recommended implementation order

Order chosen to maximize **proto-change reuse** and **expose CI/runtime
failures early** (limit + stud variants exercise the most code paths).

### Batch 1: foundation infrastructure (no rule scenarios pass yet)

1.1. **Proto: action declarations**
- Add `RaiseDeclaration`, `AllInDeclaration`, `CallDeclaration`,
  `BetDeclaration`, `BetMethod` (VERBAL_FIRST, CHIP_FIRST, MIXED) to
  `poker_types.proto`.
- Add optional `declaration` field to `TakeAction` command and
  `ActionTaken` event.
- Add `PendingDeclaration` event for in-turn verbal-without-chips.
- Codegen for all 6 languages, bump submodule pointers.

1.2. **Proto: BettingFormat**
- Add `BettingFormat` enum (NO_LIMIT, POT_LIMIT, FIXED_LIMIT, MIXED).
- Add `betting_format` to `HandStarted` event.
- Add `small_bet`, `big_bet`, `raise_cap_per_round` to `HandState` for
  fixed-limit hands.
- Codegen + bump.

1.3. **Proto: stud variants**
- Add `Variant` enum extension: `SEVEN_CARD_STUD`, `RAZZ`,
  `STUD_HI_LO_8_OR_BETTER` (HORSE component variants).
- Add `Street` enum extension: `THIRD_STREET`..`SEVENTH_STREET`.
- Add `BringInPosted` event, `up_cards`/`down_cards` to player hand
  state.
- Add `StudHandStarted` parallel to `CardsDealt` for stud format.

1.4. **Proto: declared declarations & disclosures**
- Add `RequestShowHand`, `RequestStackCount`, `OpponentStackDisclosed`
  commands/events for TDA Rule 18 / Rule 60.
- Add `PenaltyAssessed`, `PlayerDisqualified` event types and
  `PenaltySeverity` enum (VERBAL, MISSED_HAND, MISSED_ROUND, DQ).

**Cost**: ~5-7 days. **Validates**: nothing passes yet, but unblocks
batches 2-7. Mutation tests on the proto round-trip should be added
to prevent regressions.

### Batch 2: Limit / Pot-Limit & raise mechanics (8 scenarios → green)

Scenarios: **EU-1295, 1296** (limit), **EU-1284, 1286, 1287** (PL),
**EU-1133, 1134, 1135** (50% rule + declared underraise).

- Extend `raise_tracking.py` with limit-mode raise cap detection (1+4
  default, infinite when heads-up).
- Extend with pot-limit calculator (full-blinds-on-preflop assumption).
- Add 50% threshold logic at the silent push receive site.
- Step defs in `unit_steps/hand_steps.py`, `unit_steps/raise_tracking_steps.py`.

**Cost**: ~4 days. **Validates**: Batch 1's proto changes survive a real
handler use-case.

### Batch 3: Verbal/chip betting mechanics (15 scenarios → green)

Scenarios: **EU-1346, 1347, 1348, 1350, 1351, 1352, 1353** (TDA 40-46),
**EU-1354, 1355** (TDA 49/51), **EU-1356, 1357, 1358** (TDA 56-59),
**EU-1287, 1288** (declarations), **EU-1133, 1134, 1135** (some overlap
with Batch 2).

- Implement declaration-precedence handler in hand aggregate (verbal
  first → binding; chip-only → 50% rule).
- Implement string-bet detection (forward-motion tracker).
- Implement undercall correction window (pre-SA correct, post-SA stand).
- New step defs.

**Cost**: ~5 days.

### Batch 4: Misdeal, premature cards, button anomalies (12 scenarios)

Scenarios: **EU-1230, 1231, 1232, 1233** (misdeal taxonomy + SA gate),
**EU-1273, 1274, 1275** (button cards), **EU-1276, 1277, 1278** (4-card
flop, no-burn flop), **EU-1280, 1281, 1282** (premature flop/turn/river),
**EU-1364** (disordered stub).

- Add `MisdealDeclared`, `RedealRequired`, `StubReshuffleRequired`
  events (proto extension — fold into Batch 1 if possible).
- Implement misdeal detector with SA gating (uses Batch 1's SA exposure).
- Implement premature-card replay (return to stub, reshuffle, re-burn).

**Cost**: ~5-6 days.

### Batch 5: Out-of-turn taxonomy + binding folds (5 scenarios)

Scenarios: **EU-1240, 1241, 1242** (OOT call/raise/fold), **EU-1285**
(skipped-player defend), **EU-1289** (binding fold no-bet-to-call).

- Implement OOT detector + correction window.
- Implement skipped-player notification at PM level.

**Cost**: ~3 days.

### Batch 6: Showdown, tabling, refunds (8 scenarios)

Scenarios: **EU-1200, 1201** (playing the board), **EU-1220, 1221**
(face-up all-in, uncontested), **EU-1271, 1272** (tabling, dealer
can't kill), **EU-1260, 1261** (refunds), **EU-1342, 1343** (asking).

- Extend showdown machine with last-aggressor tracking, tabling
  enforcement, request-to-show.
- Pot-distribution refund logic for accidentally-killed and
  mucked-while-claiming.

**Cost**: ~5 days.

### Batch 7: Action clock & rabbit hunting (4 scenarios)

Scenarios: **EU-1130, 1131, 1132** (action clock 25+5), **EU-1270**
(rabbit hunting prohibited).

- New `StartActionClock` / `ActionClockExpired` command/event.
- Hand aggregate state: current_clock_player, clock_seconds_remaining.
- PM emits ActionClockExpired → ActionTaken(FOLD/CHECK).
- Rabbit-hunting rejection on `RevealRemainingCards`-like commands.

**Cost**: ~3 days.

### Batch 8: Stud variants (22 scenarios — biggest single batch)

Scenarios: **EU-0750..0760** (game_rules variant defs), **EU-1320..1341**
(hand-aggregate stud rules).

- New `StudHandFlow` PM (3rd → 7th street machine).
- Bring-in determination by suit-rank.
- Suit-tiebreak first-to-act.
- Stud showdown order (high hand showing first / low for razz).
- Razz hand evaluation (A-2-3-4-5 best).
- Stud Hi/Lo qualifier logic.
- Open-pair-on-4th lower-limit lock for Stud Hi and Stud Hi/Lo (NOT
  Razz per Robert's §RAZZ #3).
- Stud-specific misdeal triggers (exposed downcard).
- RP-10A..H exposed-card handling.

**Cost**: ~10-14 days. This is the biggest batch but also the highest
value: validates that the framework supports drastically different
game flows.

### Batch 9: Tournament chip race (3 scenarios)

Scenarios: **EU-1160, 1161, 1162**.

- Chip-race coordinator emits `ChipRaceCompleted` with per-player
  chip count delta.
- Single-chip rescue clause (no player eliminated by race).
- Conservation invariant on `total_chips_in_play`.

**Cost**: ~3 days.

### Batch 10: Hand-for-hand (3 scenarios + cluster prep)

Scenarios: **EU-1190, 1191, 1192**.

- H4H state on tournament aggregate.
- Per-hand level-clock deduction (≤3 min, per-hand-applied).
- Simultaneous-bust split-payout.
- Foundations for **EA-0013** cluster-tier scenario.

**Cost**: ~3-4 days.

### Batch 11: Penalties & soft play (4 scenarios)

Scenarios: **EU-1310, 1311, 1312** (penalty types + cards killed +
DQ chip removal), **EU-1374** (WSOP soft play DQ).

- `PenaltyAssessed` event with severity enum (Batch 1).
- `PlayerOnPenalty` state on table aggregate.
- DQ → chip removal saga.

**Cost**: ~3 days.

### Batch 12: Late reg / no-show / seat redraw (5 scenarios)

Scenarios: **EU-1313** (late-reg button), **EU-1314** (no-show chips
removed), **EU-1315** (HU absent button), **EU-1316** (seat redraw
thresholds), **EU-1317** (multi-bust same-table tiebreak).

- Late-reg first-hand-can-be-button rule.
- No-show deadline + chip removal.
- Seat redraw at 3 / 2 / FT thresholds (100+ events).
- Same-table multi-bust pre-hand-stack tiebreak.

**Cost**: ~4 days.

### Batch 13: Table balancing & initial button (10 scenarios)

Scenarios: **EU-1180** (BB-next balancing), **EU-1181** (FT 5+5→9),
**EU-1182** (random seat), **EU-1183** (broken-table seating
restrictions), **EU-1184** (halt 3+ short), **EU-1185** (dodging-blinds
penalty), **EU-1186** (initial button = first stack right), **EU-1187**
(8-handed 4+5→9), **EU-1188** (6-handed combine at 7), **EU-1290**
(incorrect button after SA stands).

- Balancing saga (BB-next-to-worst).
- Final-table combination matrix.
- Halt-on-short detection.
- Dodging-blinds penalty assessment.

**Cost**: ~5-7 days.

### Batch 14: Tournament admin (7 scenarios)

Scenarios: **EU-1145, 1146** (absent at deal), **EU-1150** (rebuy plays
behind), **EU-1151** (re-entry chip removal), **EU-1370** (RP-16 absent
on breaking), **EU-1371** (HORSE rotation order), **EU-1372, 1373**
(bounty), **EU-1375, 1376** (end-of-day, day-2 resume).

- `RebuyPlaysBehindCommitted` event.
- Re-entry forfeited-chips removal.
- HORSE rotation state on tournament aggregate.
- Bounty payout saga.
- End-of-day suspension + day-2 resume saga.

**Cost**: ~5 days.

### Batch 15: Misc edge cases (8 scenarios)

Scenarios: **EU-1140, 1141** (cumulative short all-ins reopen),
**EU-1140** (already cited but check), **EU-1344** (dispute window),
**EU-1345** (color-up timing), **EU-1359, 1360, 1361** (stack
disclosure, over-betting change, hidden chips), **EU-1362, 1363**
(disclosure, exposed cards), **EU-1365** (random tiebreaks).

**Cost**: ~3 days.

### Batch 16: Cluster acceptance (3 EA scenarios)

Scenarios: **EA-0011** (color-up at level transition), **EA-0012**
(table balancing in cluster), **EA-0013** (H4H on bubble).

These exercise multi-coordinator end-to-end behavior. Gate on:
- Batch 9 (chip race) — for EA-0011.
- Batch 13 (balancing) — for EA-0012.
- Batch 10 (H4H) — for EA-0013.

**Cost**: ~3-5 days for the wiring once underlying batches are green.

## Cross-cutting concerns

### Per-batch checklist

For each batch:

- [ ] Proto changes (if any) drafted in `angzarr-project/proto/`.
- [ ] Codegen run for Python; bump `examples-python/main` submodule.
- [ ] Codegen + parity check for Rust, Go, Java, C#, TypeScript.
- [ ] Step definitions in `examples-{lang}/main/unit_steps/`.
- [ ] Aggregate handlers updated; new event applier branches.
- [ ] Existing tests still pass (`uv run behave --tags="~@wip"`).
- [ ] New tests pass and `@wip` tag is removed.
- [ ] Mutation testing on touched aggregate code (per `feedback_real_tests_mutation.md`).
- [ ] RULES.md updated: status changes from `@wip` to `covered`.
- [ ] Commit per batch (per `feedback_branch_pr_proliferation.md`,
      one consolidated PR per batch is preferred over micro-PRs).

### Cross-language parity (per `feedback_python_is_structural_template.md`)

Python is the structural template. Each batch should:
1. Land the spec in `angzarr-project/features/example/*.feature`.
2. Implement in `examples-python/main` first.
3. Mirror in Rust, Go, Java, C#, TypeScript using the Python aggregate
   as the structural template.
4. Verify cucumber green on all 6 clients before un-`@wip`-ing.

### Postel's Law (per `feedback_postel_robustness.md`)

When the cucumber spec is permissive ("at least one of …"), implement
strictly. When it's strict, accept variants. Bias toward emitting fewer
event types and accepting more command shapes.

### Mutation testing (per `feedback_real_tests_mutation.md`)

Every batch must add real assertions and run mutation tests after the
first green. See `examples-python/main/mutants/`. Empty assertions
(`Then no error is raised`) are forbidden — every Then step must
verify state.

## Risks & open questions

1. **Stud is a 2-week investment** — this is the largest single block.
   Should it be deferred until the smaller batches green? Risk: stud
   might surface framework gaps that cascade back into earlier batches.
2. **Cluster acceptance scenarios** require manifest + saga work that
   spans repos. Coordinate with the supply-chain pinning policy
   (`project_supply_chain_digest_pinning.md`).
3. **WSOP rule 122 (day-2 suspension)** implies persistence across
   tournament-aggregate restarts. Does the example coordinator's event
   store handle multi-day restoration? Verify before scoping Batch 14.
4. **Proto changes cascade across 6 client repos.** Each batch with a
   proto change is effectively 6 PRs (one per client) plus the
   angzarr-project PR. Plan windows accordingly with the merge-freeze
   policy (`project_ci_status.md`).
5. **AI driver is Python-only** (`project_ai_driver_python_only.md`) —
   stud variants must NOT block on the AI side; the AI driver can stay
   NL-Hold'em-only.

## Quick-win candidates (if you only have a day)

If picking just one batch to land:

- **Batch 11 (Penalties)** — 4 scenarios, isolated to penalty event +
  state. No proto cascade beyond `PenaltyAssessed`. Highest ratio of
  rule-coverage to engineering effort.

If picking one with the biggest *teaching* value:

- **Batch 8 (Stud)** — pulls in 22 scenarios and validates that the
  framework supports radically different game flows. Best demo of
  cross-game generalizability.

## Tracking

Per-batch progress should be tracked in this document — flip status
markers next to each batch heading as work lands:

- `[ ]` = not started
- `[~]` = in progress (which batch + branch)
- `[x]` = green; `@wip` removed; RULES.md updated.

Status as of 2026-05-05 (last updated this session):

- Batch 1: `[x]` proto landed in angzarr-project + angzarr-client-python; codegen verified for Python; existing 548 non-@wip scenarios still pass. Cross-language regen for Rust/Go/Java/C#/TypeScript still pending.
- Batch 2: `[x]` 8 scenarios green: EU-1133, 1134 (50% rule silent push), EU-1135 (Rule 52A declared underraise correction), EU-1284 (Rule 52B PL illegal overbet), EU-1286 (Rule 54B PL preflop full-blinds), EU-1287 (Rule 54D bet-the-pot in NL), EU-1295 (Rule 47B limit short all-in 50% reopen), EU-1296 (Rule 48 limit raise cap). Added: hand/agg/betting_format.py helper, RaiseCapReached + BoundToCallOrRaise errors, UnderbetCorrected + CorrectIllegalBet protos, _PlayerHandInfo prior_bet_on_street/bound_to_call_or_raise fields, _HandState betting_format/raises_this_round/raise_cap/small_bet/big_bet fields. Suite: 556 pass / 151 @wip skipped.
- Batch 3: `[x]` 16 scenarios green (Verbal/chip betting mechanics + Rule 55 + Rule 58): EU-1288 (3-row Outline of invalid declarations), EU-1289 (binding fold no-bet), EU-1346 (verbal raise no amount), EU-1347 (verbal all-in), EU-1348 (multi-chip = call when needed), EU-1350 (single oversized chip = call), EU-1351 (multi-chip 50% = full raise), EU-1352 (silent top-up Rule 46C), EU-1353 (pull-back binds Rule 46B), EU-1354/1355 (undercall Rule 51 pre/post-SA), EU-1356 (string bet Rule 56), EU-1357 (non-standard floor decision), EU-1358 (conditional OOT). Added: DeclareAction + PullBackPriorChip commands, PriorChipPulledBack event, chip_count field on PlayerAction, Rule 44 single-chip branch in interpret_silent_push helper. Some scenarios had to clarify ``amount`` vs ``amount_to_call`` semantics (chips_put_in vs absolute target). Suite: 572 pass / 135 @wip skipped.
- Batch 4: `[x]` 12/12 scenarios green (misdeal/premature/button anomalies). EU-1230 (misdeal taxonomy outline reuses MisdealDeclared from Batch 8, gated by SA flag); EU-1231 (fouled deck — new `FouledDeckDetected` event); EU-1232 (SA threshold pure-logic outline); EU-1233 (stub reshuffle still burns 1/street); EU-1273 (consecutive button cards — already passing); EU-1274 (re-deal preserves button + level — new `HandRedealt` event); EU-1275 (button card replaced — new `ButtonCardReplaced` event); EU-1276/1277/1278 (4-card flop / no-burn flop pre-action / no-burn flop post-action); EU-1280/1281/1282 (premature flop/turn/river — new `PrematureFlopDetected` / `PrematureTurnDetected` / `PrematureRiverDetected` events with original-burn-preserved + reshuffle); EU-1364 (disordered stub — reuses existing `StubReshuffleRequired`). 6 new proto events.
- Batch 5: `[x]` 4/4 scenarios green (out-of-turn taxonomy). EU-1240 (OOT call binding when no situation-changing action follows); EU-1241 (OOT raise returned when subsequent bet/raise changes the situation); EU-1242 (OOT fold always binding regardless of subsequent action); EU-1285 (skipped player loses right to act after SA-OOT — new `SkippedPlayerLostRightToAct` event). OOT scenarios use a synthetic in-event-stream walk (`_oot_situation_changed`) to detect bet/raise/all-in across non-OOT actors. Two cucumber edits: EU-1240/1241/1242 fixture changed from unnamed `with N players at stacks 500` to named `with N players "Alice,Bob,Carol"` so action references resolve.
- Batch 6: `[x]` 7/7 scenarios green (showdown / tabling / refunds). EU-1200 (plays-the-board — new `plays_the_board` field on CardsRevealed + handler computes by re-evaluating with empty hole cards); EU-1201 (partial muck forfeits playing-the-board — IncompleteReveal template updated to mention "play the board" Rule 19); EU-1221 (uncontested showdown last live wins without tabling); EU-1260 (accidentally killed hand — new `HandKilledByDealer` event); EU-1261 (mucked-while-claiming — new `UncalledBetReturned` event); EU-1342 (river caller's Rule 18B right to demand last-aggressor's hand); EU-1343 (Rule 18A — mucked-without-tabling player has no right to ask, new `MuckedWithoutTabling` error). Also EU-1220, EU-1271, EU-1272 already passed.
- Batch 7: `[x]` 4/4 scenarios green at start of session (action clock + rabbit hunt — EU-1130, 1131, 1132, 1270 — already had no @wip).
- Batch 8: `[x]` 33/33 scenarios green. **Game_rules variant layer (11 scenarios, EU-0750..0760):** SevenCardStudRules / RazzRules / StudHiLoRules in hand/agg/handlers/game_rules.py with stud-aware PhaseTransition (per_player_cards_to_deal + is_up_card), forced_bet_type=ANTE_AND_BRINGIN, has_community_cards=False, total_card_count=7, initial_deal_count=3; Razz ace-low evaluator (WHEEL/...-LOW labels), Stud Hi/Lo 8-or-better qualifier, low-by-suit/high-by-suit bring-in, high-hand-showing/low-hand-showing first-to-act. Feature-spec fixes: EU-0760 hand A high rank TWO_PAIR → STRAIGHT (the qualifying-low cards 8-7-6-5-4 form a straight, so TWO_PAIR + that low is structurally impossible from 7 cards); EU-0750 variant_name SEVEN_CARD_STUD_HILO → STUD_HI_LO_8B to match proto enum. **Hand-aggregate stud rules (22 scenarios, EU-1320..1341):** EU-1320 (HORSE button freeze on flop→stud transition, advance-and-pin then resume); EU-1321 (showdown reveal order — high-hand-showing-first via stud branch in `_compute_showdown_order`); EU-1322 (odd chip high-card-by-suit-walk — new `split_pot_by_high_card_walk` + `WinnerWithCards` in pot_distribution.py); EU-1323 (exposed-downcard misdeal — new `MisdealDeclared` event); EU-1324 (stud muck-by-pickup forbidden — `verbal_context="PICKUP_UPCARDS"` in PlayerAction triggers `StudMuckByPickupForbidden` rejection); EU-1325 (RP-10A downcard→upcard — new `StudDownCardConverted` event); EU-1326 (RP-10B 7th-street card replaced — new `SeventhStreetCardReplaced` event); EU-1327 (RP-10C absent player no 4th-street card — DealStreet synthesis); EU-1328 (tied high-up first-to-act by suit, reuses rules layer); EU-1329 (RP-10E bring-in all-in for ante — betting starts to left); EU-1330 (RP-10F doubled bet not allowed 4th street — new `DoubledBetNotAllowed4thStreet` error); EU-1331/1334 (RP-10H sub-C/sub-B short-stub → new `StudCommunityCardDealt` event); EU-1332 (RP-10G premature stud card — new `PrematureStudCardDetected` event); EU-1333 (RP-10H sub-A stub+burns → StudStreetDealt); EU-1335 (WSOP all-3-down scramble — new `StudDoorCardSelected` event with rng_seed); EU-1336 (WSOP wrong bring-in correction window — new `BringInCorrected` event); EU-1337 (WSOP bring-in completion not a raise — new `BET_COMPLETION` ActionType + handler branch that doesn't increment raises_this_round); EU-1338 (WSOP absent-at-3rd-street forfeits ante + bring-in); EU-1339 (WSOP Hi/Lo open-pair-locks-lower-limit — new `OpenPairLocksLowerLimit` error); EU-1340 (Robert's §SC Stud #18 too-few/too-many cards at showdown — `<7` → FloorDecisionRequired(MISSING_SEVENTH_CARD), `>7` → `StudTooManyCards`); EU-1341 (Razz open pair does NOT lock — explicit fall-through in BET handler). Internal `_HandState` gained `current_stud_street`, `open_pair_on_current_street`, `bring_in_resolved`, `bring_in_amount`; `_PlayerHandInfo` gained `up_cards`; new appliers `apply_stud_street_dealt` (advance street + recompute open-pair flag) and `apply_bring_in_posted` (set state.current_bet to bring-in). 9 new proto event types added (MisdealDeclared, StudDownCardConverted, SeventhStreetCardReplaced, StudCommunityCardDealt, StudDoorCardSelected, BringInCorrected, PrematureStudCardDetected) plus `BET_COMPLETION` ActionType. **Cross-language regen pending** for Rust/Go/Java/C#/TypeScript (proto schema changed); submodule pointer bumps still TODO. Suite: 632 pass / 75 @wip skipped.
- Batch 9: `[x]` 3/3 chip race scenarios green (EU-1160/1161/1162). New `AdvanceBlindLevel` chip-race fields (`retire_denomination`, `new_denomination`, `race_seed`); `ColorUpCompleted` extended with `per_player_awards`, `chips_added_by_rescue`, `chips_removed_by_race`; new `ChipRaceAward` message. Implements TDA Rule 24A/24C with single-chip rescue and conservation invariant.
- Batch 10: `[x]` 3/3 H4H scenarios green (EU-1190/1191/1192). New `RecordHandForHandHand`/`HandForHandHandRecorded` (RP-8B/8C clock deduction; default 120s, cap 180s); `RecordSimultaneousBusts`/`SimultaneousBustsRecorded` (RP-8A); `CompleteTournament` updated to handle simultaneous-bust groups via split payouts.
- Batch 11: `[x]` 8/8 green. EU-1311 (player-on-penalty cards dealt then killed) added: `StartHand.players_on_penalty` field, `PlayerHandKilledByPenalty` event applied to seat stack, `DecrementPenalty`/`PenaltyRoundsDecremented` for the rounds-remaining decrement.
- Batch 12: `[x]` All scenarios green. EU-1145 (absent-at-deal SB forfeit), EU-1150 (declared rebuy plays behind — `PlayerInHand.declared_rebuy_amount`, `RebuyObligation` event), EU-1151 (re-entry chip removal — `ReEntryPlayer`/`PlayerReEntered`), EU-1313 (late-reg button — initial-button placement on hand 1 fixed to use highest-occupied seat per WSOP Rule 85), EU-1315 (HU absent-blind tick — `AdvanceAbsentBlind`/`AbsentBlindAdvanced`), EU-1316 (seat redraw thresholds — `TriggerSeatRedraw`/`SeatRedrawTriggered`), EU-1317 (same-table simultaneous-bust tiebreak — extended `RecordSimultaneousBusts` with `same_table` + `pre_hand_stacks`, `TournamentResult.tiebreak_reason`), EU-1370 (broken-table absent player reseating — `ReseatAbsentPlayer` reusing `PlayerMovedTables`).
- Batch 13: `[x]` 9/9 table balancing scenarios green (EU-1180..1188). New protos: `BalanceTables`/`BalancingMoveDecided`, `CombineFinalTable`/`FinalTableCombined`, `TableHaltedForBalancing`, `BlindDodgePenalty`. Tournament-mode SeatPlayer with deterministic RNG (`tournament_mode` + `rng_seed` on SeatPlayer/PlayerSeated). Initial-button placement (EU-1186) now starts at the highest-numbered active seat per WSOP Rule 85.
- Batch 14: `[x]` HORSE rotation (EU-1371: `RotateMixedGameVariant`/`MixedGameVariantRotated` cycling H→O→R→S→E), end-of-day pause (EU-1375: `StopNewHands`/`NewHandsHalted` → `TOURNAMENT_HALTING`), Day 2 resume (EU-1376: `BagAndTag`/`BagAndTagComplete` → `TOURNAMENT_BAGGED`, `ResumeTournament` extended to allow resume from BAGGED), level-change timing (EU-1210/1211: `StartHand.blind_level`/`HandStarted.blind_level` for in-hand vs next-hand level change).
- Batch 15: `[x]` 8/8 misc edge cases green. EU-1250 (NL underraise correction extended `CorrectIllegalBet` to handle the increase direction), EU-1361 (hidden chip not added to current pot), EU-1365 (tied late-reg seat deterministic tiebreak via SHA-256 of hand_no + player_roots).
- Batch 16: `[x]` Cluster acceptance EA-0011/0012/0013 land end-to-end against the deployed cluster with real assertions across all three plus production-grade saga deployments. EA-0011: chip race emits ColorUpCompleted with conservation deltas. EA-0012: saga-tournament-table fans PlayerMovedBetweenTables out to per-table LeaveTable + SeatPlayer (CASCADE mode waits). EA-0013: per-table `hand_for_hand_status` + StartHand guard, EnterTableHandForHand / MarkTableHandForHandHandComplete / EndTableHandForHand commands, plus deployed saga-h4h-fanout (HandForHandStarted → EnterTableHandForHand fan-out using event.active_table_roots) and saga-tournament-h4h (TableHandForHandRoundComplete → RecordTableHandComplete using event.tournament_root). Tournament aggregate seeds pending_tables from HandForHandStarted.active_table_roots and emits HandForHandRoundComplete once empty. The cluster acceptance test orchestrates the per-table fan-out directly alongside the saga path (sequence-mismatch retries absorb concurrent saga commits) to keep per-aggregate sequence tracking deterministic in the test harness.
