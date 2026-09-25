# Plan: replace the poker example with a blackjack tournament

**Status:** Proposed. Nothing is implemented yet.
**Scope:** `angzarr-project` (specs, protos, docs), `angzarr-examples-python` (the reference implementation), plus small follow-ups in `angzarr-cli` and `angzarr-router`.

---

## 1. Summary

The poker example has grown bigger than the framework it is meant to illustrate. This plan replaces it with a **single-table elimination blackjack tournament**. The new example covers:

- **3 aggregates:** player, tournament, hand
- **3 sagas**
- **1 process manager**
- **1 projector**
- **one compensation path**

That is every component kind Angzarr has, each used once for a reason a reader can see. It is specified in about **75 scenarios** (poker has about 600) and built outside-in with TDD.

Three principles run through the whole design:

1. **The domain logic is plain objects with no framework dependency.** Generated handler classes only translate between protos and those objects.
2. **Randomness is recorded as an event.** Replaying a hand never re-runs a random number generator.
3. **Every test goes through production code.** Assertions read aggregate state or projections, never values the test itself stored.

The component declarations in §6 were sketched as protos. They pass `angzarr lint` with 0 errors and 0 warnings, and `angzarr codegen python` / `angzarr scaffold python` generate from them cleanly. The sketch was run in a scratch directory and has not been committed.

---

## 2. Why: what the audit found

These are measured on the current trees: `angzarr-project` @ `5b02b1f` and `angzarr-examples-python` @ `887c6c9`.

| Symptom | Evidence |
|---|---|
| Spec volume | `features/example/poker` has 475 `Scenario` keywords and `framework/` has 115. `WIP_TRIAGE.md` estimates **10–14 weeks** to un-`@wip` what remains. There are 369 `@wip` tags. |
| Proto volume | `hand.proto` 1,006 lines, `tournament.proto` 1,032, `table.proto` 455, plus `ai_sidecar.proto`. |
| Implementation volume | 34.6k lines of Python. About 9.2k are domain code and about 15.4k are tests (`unit_steps/` alone is 10.8k). |
| Repo weight | About 186 MB of committed `.pt` models and training logs (`selfplay*.log`, `training_full.log` at 21 MB). The AI player is out of scope for a framework example. |
| Three aggregate styles | Player uses pure functions plus a thin class. Hand, Table and Tournament use "dual-mode" classes with private applier registries. Reservation uses a plain decorated class. |
| Duplicate and drifted code | `sagas/` duplicates the deployed `table/saga-*` modules. One deployed copy constructs `ReleaseFunds(table_root=…)`, but the proto field is `key`, and no test covers it. There are three HandFlow PMs and none of them is deployed. |
| Tests that do not exercise production code | `orchestration_steps.py` re-implements the orchestrator's logic inside the step definitions. The player tests bypass the Router. `projector.feature` is excluded as "out of sync". |
| Test acts as the system | `ACCEPTANCE_REMEDIATION_PLAN.md` describes the same problem: step definitions fan commands out like a process manager, and assertions read `context.*` values the `When` step wrote. |
| Tangled domains | `reservation/pmg` re-folds Table and Tournament events locally. The Reservation aggregate imports `player.agg.state`, and makes it work with `sys.path` hacks. |
| Stale submodule pin | `examples-python` pins `angzarr-project@8d60829`, which is from before `io.angzarr.*.v1`, before the `options.proto` annotations, and before the per-component codegen. The example does not use `angzarr codegen` at all. |

The lesson that shapes this plan: the scope never had a ceiling. Every real-world rule (TDA, WSOP, Robert's) became a scenario, so the example kept growing to cover the rulebook instead of staying the size needed to teach the framework. This plan sets the ceiling up front (§4 and §9).

---

## 3. Blackjack tournament rules (sourced)

Every rule below is backed by two independent sources. Rules that no source settles are marked **HOUSE RULE**. They are choices I made, and the user can change them.

| # | Rule | Sources |
|---|---|---|
| R1 | Every entrant starts the round with the same number of chips. The chips are tournament chips and cannot be redeemed. | [pagat][pagat-t]: "Each player begins each round with an equal value in chips". [blackjacktournament.org][bjt]: "equal amounts of chips … non-redeemable" |
| R2 | A round has a fixed number of hands. 30 is typical. | [Wikipedia][wiki]: "in most cases is thirty hands"; [bjt]: "30 hands are dealt per round" |
| R3 | Each hand has a minimum and a maximum bet. | [pagat-t]: "There is a minimum and maximum bet per hand"; [wiki]: "must stay within the minimum and maximum bet" |
| R4 | The starting position ("button") passes to the left after every hand. | [pagat-t]: "The role of starting player passes to the left after each hand"; [Wikipedia search summary][wiki]. **Weak:** the Wikipedia article itself does not mention the button when fetched, so treat this rule as single-source plus common practice. |
| R5 | Bets and player cards are visible to everyone. | [pagat-t]: "cards dealt to the players are visible to all players"; [wiki] describes the secret bet as the exception |
| R6 | After each designated elimination hand, the entrant with the fewest chips is eliminated. The standard hands are 8, 16 and 25 of 30. | [wiki]: "at the end of the 8th, 16th and 25th hands"; [bjt]: "Hands #8, #16, and #25 … 'Elimination Hands'" |
| R7 | An entrant who has no chips, or who cannot cover the minimum bet, is eliminated. | [wiki] and [bjt]: "lose all chips, cannot meet table stakes" |
| R8 | At most 7 entrants per table. | [wiki]; [bjt] |
| R9 | At the end of the round, the entrant with the most chips wins. | [pagat-t]: "the player with the most chips at each table goes through"; [pagat-t] single-table format: "highest chip count wins" |
| R10 | Blackjack rules: A counts 1 or 11, face cards count 10, a natural pays 3:2, ties push, dealer draws to 17, the soft-17 rule varies by house, double down means one more card at twice the stake. | [pagat blackjack][pagat-b]; also consistent with [wiki] and [bjt], which assume standard blackjack |
| R11 | If an entrant's bet timer expires, the minimum bet is placed for them. | [bjt] only. **Out of scope for v1.** The two sources also disagree on the timer lengths (15/30 s in [bjt] versus 25/45 s in the search summary of [wiki]). |
| R12 | Secret bet: each entrant may hide one bet per round. | [pagat-t]; [bjt]. **Out of scope for v1.** It is a candidate for a v2 scenario. |

The HOUSE RULES below have no source. They exist so the scenarios are deterministic.

- **H1. Elimination tie-break.** If two or more entrants tie for fewest chips at an elimination hand, the entrant who bet earlier in that hand is eliminated. Neither [wiki] nor [bjt] specifies a tie-break.
- **H2. Fractional payouts are rounded down.** A 3:2 payout on an odd bet rounds down to a whole chip.
- **H3. The shoe is reshuffled every hand**, as with a continuous shuffling machine, so there is no carry-over or cut-card logic.
- **H4. Prize split.** The prize pool is `entry_fee × entrants`, split by a configured percentage list (for example `[70, 30]`). Any rounding remainder goes to first place.
- **H5. Final standings.** Survivors are ordered by chips. Eliminated entrants are ordered by elimination, so the one eliminated later finishes higher.

**v1 excludes:**

- split, surrender and insurance
- the secret bet
- the action clock
- multi-table rounds and advancement
- the "knockout card" variant

Each of these is additive later, and none is needed to demonstrate the framework.

[pagat-t]: https://www.pagat.com/banking/tournament_blackjack.html
[pagat-b]: https://www.pagat.com/banking/blackjack.html
[wiki]: https://en.wikipedia.org/wiki/Elimination_Blackjack
[bjt]: https://www.blackjacktournament.org/guide/elimination-blackjack/

---

## 4. Scope ceiling (the anti-bloat contract)

These limits are enforced in review. Exceeding one means amending this plan first.

| Limit | Ceiling |
|---|---|
| Aggregates / sagas / PMs / projectors | 3 / 3 / 1 / 1 |
| Example scenarios, all tiers | ≤ 90 |
| Proto lines, all example files | ≤ 400 |
| Hand-written Python (domain + handlers) | ≤ 1,500 lines |
| Step-definition Python | ≤ 1,200 lines. Steps go through one harness, not per-file dispatch. |
| Committed binaries, logs, ML models | 0 |
| `@wip` scenarios on `main` | 0. A scenario lands only together with its implementation. |

---

## 5. Domain model (object-oriented design)

### 5.1 Layering: hexagonal, with a pure core

```
            proto command ─┐                           ┌─ proto events
                           ▼                           │
  ┌──────────── generated wiring (DO NOT EDIT) ──────────────┐
  │  <Component>Handler Protocol + new_*_dispatch + Rebuilder │
  └───────────────────────────┬──────────────────────────────┘
                              ▼
  ┌──── adapter: scaffolded handler class (ours, thin) ─────┐
  │  proto state → domain object; call it; domain events →  │
  │  proto events. No rules here. ~5 lines per method.      │
  └───────────────────────────┬──────────────────────────────┘
                              ▼
  ┌──── domain core: plain Python, no angzarr/proto imports ─┐
  │  value objects, entities, policies; raise DomainError     │
  └──────────────────────────────────────────────────────────┘
```

- **Dependency rule.** `domain/` imports nothing from `angzarr_*` or `*_pb2`. This is enforced with an import-linter contract in CI.
- **Why.** Blackjack rules can then be unit-tested in milliseconds with no router, and each other language's example is a port of `domain/` alone. The wiring is generated.

### 5.2 Value objects

All value objects are immutable (`@dataclass(frozen=True)`) and check their own invariants.

| Type | Responsibility | Replaces |
|---|---|---|
| `Chips` | A non-negative integer amount with `+`, `-` (raises when the result would go below zero) and `payout(ratio)` (applies H2). | `int` passed around unchecked |
| `Card`, `Rank`, `Suit` | Card identity and point value. | ints |
| `HandValue` | `total`, `is_soft`, `is_bust`, `is_blackjack`, built from `tuple[Card]`. This is where the rules for aces live. | total calculations spread through the code |
| `Shoe` | An ordered `tuple[Card]` with `draw() -> (Card, Shoe)`, which returns a new shoe instead of mutating. | a mutable deck |
| `BetLimits` | `min`, `max`, `validate(amount, stack)`. The effective maximum is `min(max, stack)`. | checks scattered through handlers |
| `SeatOrder` | The betting order for one hand, with `rotate()` for the button (R4). | index arithmetic |
| `TournamentRules` | The configuration from R2, R3, R6, R8, H4 and the soft-17 setting. It is checked once at creation. | a loose proto passed around |

### 5.3 Entities and aggregate roots

| Aggregate | Domain object | Behaviour (tell, don't ask) |
|---|---|---|
| player | `Bankroll` | `deposit`, `pay_entry(tournament, fee)` (rejects if funds are short), `refund_entry` (compensation), `credit(amount)` |
| tournament | `TournamentTable` | `enter(player)` (R8, rejects duplicates and entries once closed), `start()` (seats entrants, sets R1 stacks), `settle(hand_result)` (applies stack changes, then R6, R7 and H1 eliminations), then either `next_hand()` or `complete()` (R9, H4, H5) |
| hand | `BlackjackRound` | `place_bet` (R3, R5 order), `deal(shoe)`, `hit`, `stand`, `double`, `play_dealer(policy)`, `settle()` (R10, H2) |

### 5.4 Policies (strategy objects)

These are injected, so each variant is a class rather than an `if` flag.

- `DealerPolicy`: `StandsOnSoft17` or `HitsSoft17`, chosen from `TournamentRules.dealer_hits_soft_17`.
- `EliminationPolicy`: `LowestStackAtHands({8,16,25})` combined with `CannotCoverMinimum()` (R6 + R7 + H1). A composite, so the knockout-card variant later becomes one new class.
- `PayoutSchedule`: `PercentSplit([70,30])` (H4).
- `Shuffler` (a port): `RandomShuffler` in production, `StackedShuffler(cards)` in tests.

### 5.5 Randomness is an event, not a replay dependency

The event that deals the cards (`CardsDealt`, and each later `CardDrawn`) records the cards, or at least the cards consumed. Replay reads the recorded cards. It never re-runs the PRNG.

- Replays are exact in every language. We never need a cross-language PRNG specification. Poker relied on seeded decks, which needed exactly that.
- Scenarios stay readable: `Given the shoe is stacked: | A♠ | K♥ | 9♣ | … |`.
- The one random decision happens in the command handler, through the injected `Shuffler`, and its outcome is stored.

### 5.6 OO guardrails (review checklist)

- **SRP:** one aggregate per consistency boundary. A PM tracks one workflow. No multi-workflow "reservation" PM.
- **OCP:** a new rule variant is a new policy class, not a new branch in a handler.
- **LSP:** every `Shuffler`, `DealerPolicy` and `EliminationPolicy` implementation passes the same contract tests. These are parametrized pytest fixtures.
- **ISP:** the generated `Protocol` seams are already per-component. Do not add god base classes.
- **DIP:** handlers depend on the policy and `Shuffler` abstractions, supplied through a composition root in each `main.py`.
- **No primitive obsession:** chips, cards and seat order are types.
- **Law of Demeter:** handlers call exactly one domain method per command.
- **No shared mutable state between domains.** A cross-domain fact arrives as an event or in a command payload. There are no synchronous query reads inside handlers; this removes the `QueryClient`-in-a-PM pattern.

---

## 6. Angzarr components

The package is `io.angzarr.examples.blackjack.v1` in `proto/io/angzarr/examples/blackjack/v1/`. A separate package lets it sit next to poker during the migration without name collisions (`HandStarted`, `PlayerState` and others exist in both).

```
 player ──EntryFeePaid──▶ [EntrySaga] ──EnterPlayer──▶ tournament
   ▲  └─(EnterPlayer rejected → PlayerAggregate compensates: EntryFeeRefunded)
   │
   │                         tournament ──HandStarted──▶ [DealSaga] ──OpenHand──▶ hand
   │                              ▲                                                │
   │                              └──SettleHand── [SettlementSaga] ◀─HandCompleted─┘
   │
   └──CreditWinnings── [PayoutProcessManager] ◀─TournamentCompleted── tournament
                               ▲    └──ClosePayouts──▶ tournament
                               └──WinningsCredited── player

 tournament events ──▶ [StandingsProjector]  (live leaderboard read model)
```

| Component | Kind | Domains | What it teaches |
|---|---|---|---|
| `PlayerAggregate` | aggregate | `player` | Typed single-emit commands (`emits:`). Compensation via `compensates: EnterPlayer`. |
| `TournamentAggregate` | aggregate | `tournament` | One command that emits several events (`SettleHand` → `HandSettled` + `PlayerEliminated`* + `HandStarted` \| `TournamentCompleted`). |
| `HandAggregate` | aggregate | `hand` | A short-lived aggregate whose root is derived from `(tournament_root, hand_number)`. Recorded randomness. |
| `EntrySaga` | saga | player → tournament | Stateless translation, and a rejection flowing back to the source for compensation. |
| `DealSaga` | saga | tournament → hand | Starting a new aggregate from another domain's event. |
| `SettlementSaga` | saga | hand → tournament | Closes the hand loop. Sequence stamping from `Destinations`. |
| `PayoutProcessManager` | PM | tournament, player → player, tournament | Genuinely stateful fan-out and fan-in, correlated per tournament. It is the only place a PM earns its keep (see the `process-manager.mdx` anti-pattern warning). |
| `StandingsProjector` | projector | `tournament` | A single-domain read model plus a query surface. |

Choreography through sagas drives the game loop, and the one PM handles the one workflow that must wait for N confirmations. This split is deliberate: it teaches readers when not to reach for a PM.

A draft of the protos (player, tournament, hand, flows; about 100 lines) was built with `grpc_tools.protoc --include_imports --include_source_info` and linted with `angzarr lint` built from `angzarr-cli@02a6b37`. The result was `lint OK: 0 warning(s)`. The same sketch generated 8 Python wiring files and 8 scaffolds (913 lines, all generated).

---

## 7. Test strategy: outside-in, double-loop TDD

```
 outer loop (behaviour)   Gherkin scenario (red) ────────────────────────────▶ green
                              │                                                  ▲
 inner loop (design)          └─▶ pytest: domain object test (red → green → refactor) ┘
```

For each slice in §8:

1. **Spec first, in `angzarr-project`.** Write the scenarios, tag them `@EU-NNNN`, cite the rule as `# Rule: R6 / [wiki] [bjt]`, and update the rule index. The spec lands first, per `features/README.md` ownership.
2. **Proto next.** Add the messages and annotations, then run `angzarr lint` (it must stay at 0 warnings) and `angzarr codegen`.
3. **Inner loop in `examples-python/domain/`.** Write pytest unit tests for the value objects and policies first. Use Hypothesis property tests for invariants:
   - chips are conserved across a hand (the sum of stack changes equals the negated dealer net)
   - `HandValue` is never a bust while a soft ace can still be demoted
   - a shoe draw never duplicates a card
4. **Adapter.** Fill the scaffolded handler. Each method maps the proto to the domain, calls one domain method, and maps back.
5. **Outer loop goes green.** The step definitions go through **one** `InProcessHarness`: a real `Router` built from the generated `new_*_dispatch`, with sagas and the PM chained synchronously. They assert on rebuilt aggregate state or on the projector's read model.
6. **Refactor, then check mutation testing.** `mutmut` on `domain/` must kill at least 90% of mutants. Poker's gate was 80%; the domain core is small and pure, so it can be higher.

**Test-suite rules.** These are lessons from `ACCEPTANCE_REMEDIATION_PLAN.md`.

- A `Then` step reads the system (aggregate, projection or emitted book). It never reads `context.*` values that a `When` step wrote.
- Step definitions never sequence cross-domain commands. If a scenario needs orchestration, that orchestration is production code.
- One harness per tier, with the same step phrasing at both tiers (in-process and cluster). The cluster tier swaps `InProcessHarness` for `GrpcHarness` behind one `Harness` interface (LSP again).
- Tier purity stays as it is today: `features/client/` stays generic (Order/Payment), and `features/example/` becomes blackjack-only.

### Scenario budget (estimates for sizing, not counts)

| File | Scenarios | Covers |
|---|---|---|
| `blackjack/hand_value.feature` | ~8 | R10: soft and hard totals, naturals, busts |
| `blackjack/hand.feature` | ~20 | R3, R5, R10, H2: betting order and limits, hit/stand/double, dealer S17/H17, settlement, dealer blackjack |
| `blackjack/tournament.feature` | ~18 | R1, R2, R4, R6–R9, H1, H4, H5 |
| `blackjack/player.feature` | ~8 | bankroll, entry fee, winnings |
| `framework/saga.feature` | ~6 | the 3 sagas, including the rejection → compensation path |
| `framework/process_manager.feature` | ~6 | payout fan-out, partial confirmation, completion, state rebuilt from its own events |
| `framework/projector.feature` | ~5 | standings fold, idempotent replay, unknown-event tolerance |
| `acceptance/cluster.feature` | ~4 | a full 2-entrant tournament end to end, restart durability, projector lag bound, cross-domain routing |
| **Total** | **~75** | Ceiling 90 (§4) |

---

## 8. Delivery slices

Each slice is a vertical, shippable increment. Every scenario it adds is green and none is `@wip`.

| # | Slice | Repos | Done when |
|---|---|---|---|
| 0 | **Groundwork.** Add ADR 0002 (example domain change). Create `proto/io/angzarr/examples/blackjack/v1/` and `features/example/blackjack/`. Add a `RULES.md` rewrite for sources R1–R12, and point `check_rule_citations.py` at the new directory. In `examples-python`, a fresh `blackjack/` package with a `domain/`, `handlers/` and `main/` layout, `buf.gen.yaml` using `angzarr codegen python` + `scaffold`, `InProcessHarness`, an import-linter contract, and CI jobs. | project, examples-python | An empty suite runs green in CI. Codegen output is reproducible. |
| 1 | **Cards and hand values.** Pure domain only; no framework yet. | both | `hand_value.feature` is green. The Hypothesis properties pass. |
| 2 | **Player aggregate.** Register, deposit, pay entry fee, credit winnings. | both | `player.feature` is green through the Router. |
| 3 | **Tournament setup.** Create, enter, start, seating and button. | both | Setup scenarios are green. |
| 4 | **EntrySaga + compensation.** A full or closed tournament refunds the fee. | both | The saga scenarios, including compensation, are green. |
| 5 | **Hand aggregate.** Bets, deal (stacked shoe), hit/stand/double, dealer policy, settlement. | both | `hand.feature` is green. |
| 6 | **Game loop.** `DealSaga` and `SettlementSaga`, `SettleHand` → next hand. | both | A 2-entrant, 3-hand tournament plays out in-process. |
| 7 | **Elimination and completion.** R6, R7, H1, R9, H4, H5. | both | `tournament.feature` is green. |
| 8 | **PayoutProcessManager.** | both | The PM scenarios are green. Winnings land in bankrolls. |
| 9 | **StandingsProjector** and its query surface. | both | The projector scenarios are green. |
| 10 | **Cluster acceptance.** Helm values for 8 components, a kind CI job, and `GrpcHarness`. | examples-python | The `acceptance/cluster.feature` scenarios are green on kind. |
| 11 | **Retire poker** (§10). | all | No poker references remain outside git history. |
| 12 | **Docs.** Rewrite `site/.../examples/*` around blackjack, with embeds pointing at the new paths. Replace `why-poker.md` with `why-blackjack.md`. | project | The site builds, and every embed resolves. |

Slices 1–2 can run in parallel with 3–4. Slice 5 depends only on 1. Slice 6 needs 3 and 5. Slices 8 and 9 are independent once 7 is done.

---

## 9. Cross-repository impact

| Repo | Change | Where the evidence is |
|---|---|---|
| angzarr-project | New protos, features, `RULES.md`, ADR, site pages. Remove the poker protos and features in slice 11. Rename the poker-worded steps in `coordinator-contract/fact_flow.feature` ("Hand injects ActionRequested fact…"). Update rule 12 of `STEP_VOCABULARY.md` and the tier READMEs. | `features/README.md`, `features/coordinator-contract/fact_flow.feature` |
| angzarr-cli | `just generate-check` expects `table_aggregate_angzarr.pb.go` / `table_hand_saga_angzarr.pb.go`; repoint it to `hand_aggregate` / `deal_saga`. **Proposal, needs a decision:** typed multi-emit. Today, `emits` with more than one type falls back to returning a raw `EventBook`. `PlaceBet`, `Hit`, `Stand`, `DoubleDown` and `SettleHand` can each emit 1–3 event types, so without this change they all use that fallback. | `angzarr-cli/justfile:38-50`; `codegen/*` (with one `emits`, the handler returns a typed list) |
| angzarr-router | Comments only. `aggregate.test.rs` uses `io.angzarr.examples.v1.ReserveStock` as an opaque type string, and `registry.rs:450` and `docs/architecture.md:143` mention poker. The conformance suite is already domain-neutral (`test.counter`). Separately, the "Declaration" section of `docs/architecture.md` is stale: it still describes services, rpcs and `applies`/`reacts`. | files named |
| angzarr-examples-python | A new implementation. The poker tree, `ai_player/`, the models and the logs are deleted in slice 11. Bump the submodule pin from `8d60829` to the current layout. | agent audit (§2) |
| angzarr-client-python | Stop shipping the poker protos as `angzarr_client.proto.examples`. Example protos belong with the example. | `angzarr_client/proto/examples/` |
| Other `examples-*` languages | Port `domain/` and fill in the generated scaffolds. The feature files are shared. | per repo |

---

## 10. Retiring poker

1. Tag `angzarr-project` and `angzarr-examples-python` as `poker-final`, so the full example stays reachable in git history.
2. Keep poker and blackjack side by side, in separate proto packages, until slice 10 is green.
3. Slice 11 then deletes:
   - `proto/io/angzarr/examples/v1/*`, except anything still referenced by `features/client`. `order_workflow.proto` is generic, so move it to the client tier or delete it.
   - `features/example/{poker,framework,acceptance}` poker content, `WIP_TRIAGE.md` and `ACCEPTANCE_REMEDIATION_PLAN.md`, which are superseded.
   - the whole poker tree in examples-python, including `ai_player/`, `models/`, `*.log` and the stale planning docs.
4. Keep the scenario IDs as they are. New blackjack scenarios start at `@EU-1382` and `@EA-0014`. IDs are never reused (`features/README.md`).

---

## 11. Open decisions (defaults assumed above)

| # | Question | Default in this plan |
|---|---|---|
| D1 | Where the implementation lives | Rewrite in place in `angzarr-examples-python` on a new branch. That repo is not in this session's push scope. |
| D2 | What happens to poker | Tag `poker-final`, then delete (§10) |
| D3 | v1 rule scope | Hit, stand and double only. Split, surrender, insurance, secret bet and action clock are deferred. |
| D4 | Elimination tie-break (H1, unsourced) | The entrant who bet earlier in the hand is eliminated |
| D5 | Typed multi-emit in angzarr-cli | Propose it as a separate CLI change. The example uses the raw-EventBook fallback until it lands. |
| D6 | Language order | Python first as the reference implementation, then the others port `domain/` |
