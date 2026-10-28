# Blackjack on the latest proto: rulings needed

**Status:** open, 2026-10-19. Each item below waits on an owner ruling.
Branch `spec/blackjack-latest` (based on `spec/20261019-draft`) carries the
blackjack spec ported from `feat/blackjack-spec`. Context:
`docs/design/blackjack-mvp.plan.md` (on the blackjack-plan worktree), Stage 0.


> **A process manager takes facts only and sends no commands (decision
> 14.31).** pmg-buy-in subscribes to nothing: `TableBuyInSaga`
> (saga-table-buy-in) and `PlayerBuyInSaga` (saga-player-buy-in) turn the
> table's and the wallet's events into facts for it (`TableSeatHeld`,
> `TablePlayerSeated`, `PlayerFundsHeld`, `PlayerFundsCaptured`). It
> records each step as a buy-in event carrying the next command's data,
> and two sagas from "buy-in" build the commands: `BuyInPlayerSaga`
> (saga-buy-in-player: `HoldFunds`, `CaptureFunds`) and `BuyInTableSaga`
> (saga-buy-in-table: `ConfirmSeat`). `TableSeatHeld` is its one starting
> fact (ruling B1): any other fact for a buy-in it has not seen is
> skipped. Wherever this note says the PM hears of an event, read "a saga
> into "buy-in" sends it a fact"; wherever it says the PM sends or issues
> a command, read "the PM records an event and a buy-in saga sends the
> command". R2's options are unchanged in substance: a refusal still
> reaches the PM only as a recorded event, now turned into a fact by the
> target's saga into "buy-in", and a hard rejection of the saga's command
> is dead-lettered.

> **One saga per (source, destination) pair (decision 14.23).** The
> table -> player reactions (round history and loyalty, and settlement if
> a ruling restores it) are one saga, `TablePlayerSaga`
> (saga-table-player). The saga names below are the earlier spec's.

## How the port was cut

A proto message, field or Gherkin scenario was ported when it means the same
thing however the rulings go. It was held back when it uses a construct the
latest `io.angzarr.v1` contract removes or reshapes, or when a ruling could
change what it does. The usual case is a command that may have to record a
refusal as an event instead of rejecting. Nothing below has been decided.
Held-back scenario IDs stay allocated, so each can return under its own ID.

The stage-1 slice ported unchanged: `cards.proto` (SplitMix64 + Fisher–Yates),
`CreateTable` → `TableCreated` + `ShoeShuffled`, EU-1440..1442 (table creation)
and EU-1520..1525 (golden shoe vectors, values untouched). The only stage-1
touchpoint with a removed construct is that `CreateTable` used to come with a
lasting (`RETENTION_PERSIST`) snapshot (R9, EU-1591). The stage-1 "done"
criteria do not depend on it.

## Headline list

| # | Construct | What it did in the game |
|---|-----------|-------------------------|
| R1 | Compensation: the top-up refusal | A top-up the table refuses mid-round is undone in the wallet |
| R2 | Compensation: buy-in refusals into pmg-buy-in | A refused hold or seat confirmation fails the buy-in and releases the other half |
| R3 | Facts injected by a saga | Chips added and cash-outs credited to the wallet exactly once, never refusable |
| R4 | `SYNC_MODE_CASCADE` replies | `RequestSeat` / `LeaveTable` callers wait until the buy-in or credit finishes |
| R5 | Cascade error modes and `undoes` | What a waiting caller gets when a follow-up fails; retracting round results |
| R6 | `SYNC_MODE_ISOLATED` | Importing a legacy player without triggering reactions |
| R7 | Merge strategy: `COMMUTATIVE` and `MANUAL` | Stale deposits merging past a rename; stale withdrawals sent for human review |
| R8 | Speculative execution and editions | The what-if round; speculative withdrawals; the "no peeking at the shoe" guarantee |
| R9 | Snapshot retention | A lasting snapshot at the start of every shoe |
| R10 | Fact used as a test seeding path | Seeding an old-shape deposit for the upcaster scenario |

Several scenarios combine constructs and need more than one ruling; see
[Composite scenarios](#composite-scenarios).

---

## R1. Compensation: the top-up refusal

**Where.**
- `table.proto`: `AddChips` (refused with `WAGER_IN_PLAY`, `NOT_SEATED`,
  `TOP_UP_EXCEEDS_MAX`, "compensated by the player"), `ChipsAdded`,
  `TableState.added_holds`, the `TOP_UP_EXCEEDS_MAX` code, top-ups in the L2
  comment.
- `player.proto`: `RequestTopUp`, `TopUpRequested`, `TopUpRefused`,
  `Hold.PURPOSE_TOP_UP`, `Hold.STATUS_SETTLED`, `Hold.STATUS_REFUSED`,
  `PlayerState` `compensates: AddChips` (handler `OnAddChipsRejected`).
- `sagas.proto`: `PlayerTableSaga` (saga-player-table).
- `ledger.proto`: the top-up transfer pair.
- Gherkin: table.feature EU-1455..1459; player.feature EU-1423..1427;
  saga.feature EU-1530..1535; acceptance EA-0029. Composites: EU-1438,
  EU-1464, EU-1573, EU-1580, EU-1581, EU-1583, EA-0030, EA-0047.

**What it did.** A player asks for more chips. The wallet holds the money
and the saga asks the table to add the chips. If the player has a bet in
play (or is not seated, or would exceed the maximum buy-in), the table
refuses. The framework then delivered the rejection back to the wallet as a
`RejectionNotification`, and the wallet released the hold (`TopUpRefused`).
This was the example's showcase for compensation.

**Why it cannot port.** The compensation channel is deleted (decision-log
2.2, 2.3; `saga.proto`: "there is no compensation channel back to a saga").
A hard rejection of a saga's command is retried if retryable and otherwise
dead-lettered. Ported as it stands, a refused top-up would leave the hold
open for good and put a dead letter in front of an operator.

**Candidates.**
- **(a) Refusal event plus a saga back.** The table never rejects `AddChips`
  for business reasons. It records `ChipsRefused{hold_id, player_root,
  code}` instead, and a table→player saga turns `ChipsAdded` / `ChipsRefused`
  into commands that settle or release the hold. This is the path decision
  2.2 names ("refusal events plus a saga or PM"). EU-1456..1458 become "the
  table turns the chips away" (an event) instead of a refusal.
- **(b) A top-up process manager.** Same table change. A `pmg-top-up` owns
  the flow like pmg-buy-in and handles the table's answer as a reply. It
  costs more, and gives a queryable top-up status.
- **(c) Drop top-ups from the demo.** A player re-buys by leaving and
  buying in again. This is the simplest option. It removes the L3 top-up
  pair, and the demo no longer has an undo across domains.

## R2. Compensation: buy-in refusals into pmg-buy-in

**Where.**
- `buy_in.proto`: the "HoldFunds rejected" and "ConfirmSeat rejected" flow
  rows, `BuyInFailed`, `BuyInState.Phase.PHASE_FAILED`,
  `BuyInState.failure_reason`, `compensates: HoldFunds` and
  `compensates: ConfirmSeat` (handlers `OnHoldFundsRejected`,
  `OnConfirmSeatRejected`).
- `table.proto`: `ConfirmSeat` refusals `SEAT_HOLD_NOT_FOUND`,
  `PLAYER_ALREADY_SEATED`.
- `player.proto`: `HoldFunds` refusals `INSUFFICIENT_AVAILABLE_FUNDS`,
  `HOLD_CONFLICT`.
- Gherkin: table.feature EU-1451, EU-1452; player.feature EU-1414, EU-1416;
  process_manager.feature EU-1554..1556; acceptance EA-0027, EA-0028.
  Composites: EU-1582, EU-1584.

**What it did.** If the wallet cannot fund a buy-in, or the table cannot
confirm the seat (the hold is gone, or the player took another seat
meanwhile), the PM heard the rejection through compensation. It then failed
the buy-in and released whichever half had gone through.

**Why it cannot port.** A PM learns of a refusal only when the target records
it as a domain event, which a saga into the PM's domain turns into a fact
(`process_manager.proto`, "Replies"). A hard rejection
of a buy-in saga's command (the PM sends none; decision 14.31) is
dead-lettered, and the seat or the hold would stay held.

**Candidates.**
- **(a) Refusal events.** The wallet records `FundsHoldRefused{hold_id,
  code}` instead of rejecting `HoldFunds`, and the table records
  `SeatConfirmationRefused{buy_in_id, code}`. saga-player-buy-in and
  saga-table-buy-in turn them into facts for pmg-buy-in. The failure branch then runs as before (`BuyInFailed`,
  with `ReleaseSeat` and `ReleaseHold` built by the buy-in sagas from it). EU-1414, EU-1416, EU-1451 and EU-1452 turn
  into recorded refusals.
- **(b) As (a), but only for the refusals the flow must answer**
  (`INSUFFICIENT_AVAILABLE_FUNDS`, `PLAYER_ALREADY_SEATED`). The rest
  (`HOLD_CONFLICT`, `SEAT_HOLD_NOT_FOUND`) stay hard rejections, so they
  become dead letters that point at a bug.
- **(c) Reorder the flow so fewer refusals happen.** For example, the
  wallet holds the funds before the seat is requested. The seat race
  (EU-1584, EA-0028) still needs (a) or (b) on the table side.

Dropping the failure branch is not a real candidate: two buy-ins racing for
one player is ordinary play, so it will happen. This ruling also feeds
stage 3. Stage 2's "stacks before the wallet" question is separate.

## R3. Facts injected by a saga

**Where.**
- `player.proto`: `TopUpSettled`, `CashOutCredited`, `PlayerState`
  `facts: TopUpSettled, CashOutCredited`, `PlayerState.anomalies` (facts
  recorded with an anomaly), `total_from_tables` (nothing credits it now).
- `sagas.proto`: `TablePlayerSettlementSaga` with `emits_facts`.
- `table.proto`: the `TablePlayerSettlementSaga` consumer on
  `PlayerCashedOut` (the event itself is ported).
- `ledger.proto`: the cash-out transfer pair.
- Gherkin: player.feature EU-1428..1430; saga.feature EU-1536..1540;
  acceptance EA-0031. Composites: EU-1427, EU-1438, EU-1573, EU-1575,
  EU-1580, EU-1581, EA-0014, EA-0016, EA-0030, EA-0047.

**What it did.** The table's decision is final: once chips are added or a
player cashes out, the wallet must record it. It may flag a mismatch, but it
cannot refuse. The saga injected these as facts, keyed by `hold_id` /
`cashout_id`, so redelivery recorded them once.

**Why it cannot port.** A fact is now an external reality only: it needs a
`FactOrigin.external_id` from outside the system, and a reactor that emits a
`Fact` is refused and dead-lettered (`types.proto` `CommandPage`;
`saga.proto`: "Every emitted command is a Command (never a Fact)";
decision-log 1.7).

**Candidates.**
- **(a) Plain reaction commands that the wallet never refuses**
  (`SettleTopUp`, `CreditCashOut`). "Cannot refuse" becomes a business-code
  rule: a mismatch is recorded as an anomaly event. Exactly-once comes from
  the derived command id (UUIDv5 of the trigger, the saga's name and the
  command's index), so `cashout_id` is no longer needed for deduplication,
  though the ledger can still pair on it (L3, EU-1461).
- **(b) An external bridge.** A process outside the framework reads table
  events and injects real Facts with `external_id = hex(cashout_id)`. The
  demo keeps a fact, but it is a reactor in disguise, which goes against
  "facts are external realities".
- **(c) Drop the fact demo.** Use (a) for the money and show facts
  elsewhere, for example a deposit arriving from a payment-provider webhook,
  which is a real external fact.

## R4. `SYNC_MODE_CASCADE` replies

**Where.** `table.proto` `RequestSeat` and `LeaveTable` ("Sent with
SYNC_MODE_CASCADE so the reply arrives once the buy-in has finished / the
bankroll has been credited"); acceptance EA-0015, EA-0016 (EA-0016 also
needs R3). Both commands are ported; only the send mode was stripped.

**What it did.** The player who asks for a seat (or leaves) gets an answer
only when the whole cross-domain flow has finished, so the answer already
shows them seated (or credited).

**Why it cannot port.** CASCADE is deleted. No mode waits for reactions
(`command_handler.proto` command modes; decision-log 2.1).

**Candidates.**
- **(a) Client-side wait.** Send with `Handle` (DECISION), then follow the
  command's `correlation_id` (`EventStreamFilter` /
  `GetCorrelatedEvents`) until `BuyInCompleted` or the credit. This fits
  the plan's player seam, whose Act half needs a "my action landed" signal
  anyway.
- **(b) Wait on the player-view projection** until it shows the seat.
- **(c) Drop EA-0015 and EA-0016.** The flow stays covered asynchronously by
  EA-0026, EA-0045 and EA-0046.

## R5. Cascade error modes, `undoes`, and the loyalty refusal

**Where.**
- `player.proto`: `RoundResultRetracted`, `RoundResult.retracted`,
  `RoundResult.sequence`, `PlayerState` `undoes: RecordRoundResult`
  (handler `OnRecordRoundResultUndo`), the `LOYALTY_NOT_ENROLLED` refusal of
  `AwardLoyaltyPoints`.
- `sagas.proto`: `TablePlayerLoyaltySaga` ("that deterministic refusal is
  what the CascadeErrorMode scenarios rely on").
- `ledger.proto`: `LedgerRoundResult.retracted`.
- Gherkin: player.feature EU-1433, EU-1436; saga.feature EU-1544;
  projector.feature EU-1570; acceptance EA-0032..0036.

**What it did.** A non-member's loyalty award is refused, which gave the
acceptance tier a predictable failing follow-up. With that, it showed every
cascade error mode: stop at the first failure (EA-0032), carry on and report
(EA-0033), undo what already happened by retracting round results (EA-0034,
EU-1436), set the failure aside for review (EA-0035), and "a caller who does
not wait is unaffected" (EA-0036).

**Why it cannot port.** Cascade error modes and `undoes` are deleted
(decision-log 2.1, 2.3). A refused reaction command is retried or
dead-lettered and alerted, so as things stand every round with a non-member
seated would raise a dead letter.

**Candidates.**
- **(a) Don't refuse.** `AwardLoyaltyPoints` for a non-member records a
  forfeit event (or nothing) and never rejects. Drop the cascade-error
  scenarios and the retraction. EA-0036 can come back without its
  "not awarded" line.
- **(b) Keep the refusal as the demo's dead-letter showcase.** EA-0035
  becomes "the refused award waits in the dead-letter queue", and an
  operator replays it after the player enrolls. The cost is an alert for
  every non-member round.
- **(c) Filter in the saga.** This needs membership on `RoundSettled`, which
  the table does not know. Listed for completeness only.

## R6. `SYNC_MODE_ISOLATED`

**Where.** `player.proto` `ImportPlayer` ("Sent with SYNC_MODE_ISOLATED"),
`PlayerImported` ("the ledger projector only sees it on a rebuild");
player.feature EU-1405 (a comment, removed); acceptance EA-0025. EU-1405
and EU-1406 are ported, because the wallet behaves the same either way.

**What it did.** It migrated a legacy player without waking the ledger or
any saga.

**Why it cannot port.** ISOLATED is deleted. Every mode publishes, and "there
is no mode that writes silently" (decision-log 2.1).

**Candidates:** (a) import as an ordinary command, with the ledger showing
the player at once (EA-0025 inverted or dropped); (b) a migration tool that
writes and then rebuilds projections (outside the demo); (c) drop the
import.

## R7. Merge strategy: `COMMUTATIVE` and `MANUAL`

**Where.** `player.proto` concurrency notes: `DepositFunds` used
`MERGE_COMMUTATIVE` and `WithdrawFunds` used `MERGE_MANUAL`. Acceptance
EA-0019, EA-0020 (commutative) and EA-0021 (manual review).

**What it did.** A stale deposit merged past a rename but not past another
deposit. A stale withdrawal went to a person for review and was never
retried automatically.

**Why it cannot port as written.** Merge strategy is now
`ConflictResolution`. `MANUAL` is deleted (decision-log 1.8, 6.12).
`COMMUTATIVE` exists, but only for a state that lists it in its `(state)`
option and marks its conflict units, and it then becomes that state's
**default** for every command, withdrawals and holds included, unless
configuration overrides it per command type.

**Candidates.**
- `COMMUTATIVE`: (a) `PlayerState` opts in and marks its fields (for example
  `display_name`, `bankroll`, `total_deposited`; `holds` per key), with
  configuration pinning `WithdrawFunds` and the hold commands to STRICT.
  EA-0019 and EA-0020 then hold as written. (b) `DepositFunds` under
  `AGGREGATE_HANDLES` with its own rule. (c) drop.
- `MANUAL`: (a) STRICT, so the caller re-reads on ABORTED; (b) send the
  withdrawal with `HandleAsync` and a caller-provided `expected_sequence`.
  The latest contract dead-letters an ABORTED queued command with
  `SequenceMismatchDetails`, which is "waiting for a person" without a
  `MANUAL` mode, so EA-0021 can largely stand. (c) drop.

## R8. Speculative execution and editions

**Where.** Acceptance EA-0039 (the what-if round: branch before a stand,
hit instead), EA-0040 and EA-0041 (speculative withdrawal and overdraft),
and the `table.proto` note "Speculative execution is never offered on this
aggregate: its state holds the undealt shoe, so a speculative Hit would
reveal the next card".

**What it did.** It replayed a round differently without touching the real
table, and previewed a withdrawal's outcome. The note guaranteed that no
player could peek at the shoe.

**Why it cannot port as written.** There is no speculative RPC. A what-if is
an ordinary command in a named edition, created with
`EditionAdminService.CreateEdition(diverge_at)`, which is an operator action
(`meta.proto`; decision-log 2.4).

**Candidates.**
- EA-0039: (a) port as an edition what-if (operator creates the edition at
  the stand's sequence; Hit and Stand go to the edition). This is the
  closest mapping. Review its `@needs-core-X-021` and `@needs-core-X-089`
  tags. (b) drop.
- EA-0040 and EA-0041: (a) re-express as a wallet edition (create, withdraw
  in it, read, delete); (b) drop.
- The shoe guarantee: anyone who can create an edition can deal the next
  card in it. Either restate it as "players never get edition access"
  (editions are operator-only today), or accept that operators can peek.

## R9. Snapshot retention

**Where.** `table.proto` snapshot note (`RETENTION_DEFAULT` routine
snapshots plus a `RETENTION_PERSIST` snapshot in every EventBook with a
`ShoeShuffled`, which includes the one `CreateTable` writes);
snapshot.feature EU-1591..1593; acceptance EA-0038.

**What it did.** It kept a snapshot at the start of every shoe for audits of
the cards dealt from it, with routine snapshots replaced by newer ones.

**Why it cannot port.** `SnapshotRetention` is deleted. Snapshots are
framework policy (the newest is kept), and business milestones are events
(decision-log 2.5).

**Candidates:** (a) drop lasting snapshots. `ShoeShuffled` already records
the full order, so the event is the milestone (EU-1440 and EU-1503 already
show it). (b) show a shoe's start with an as-of read (`TemporalQuery`
`as_of_sequence` at the `ShoeShuffled`). (c) drop the scenarios. EU-1590,
EU-1594 and EA-0037 (rebuild from a snapshot, routine cadence) are ported.
They need no retention.

## R10. Fact used as a test seeding path

**Where.** Acceptance EA-0042: "The harness stores the old-shape event
directly as a fact."

**What it did.** It put a `FundsDepositedV1` into stored history so the
upcaster scenario has something to upcast.

**Why it cannot port.** A Fact now goes through an ingest handler, which
emits current events, never the legacy shape.

**Candidates:** (a) the harness writes the old-shape event straight into
the event store (test-only access); (b) drop EA-0042. The in-process
EU-1437 and EU-1569 cover upcasting and are ported.

---

## Composite scenarios

These need more than one ruling.

| Scenario | Needs |
|----------|-------|
| player.feature EU-1427 (refusal after settlement) | R1, R3 |
| player.feature EU-1438 (L1 over a mix of movements) | R1, R3 |
| table.feature EU-1464 (L2 through seating, top-up, cash-out) | R1 |
| projector.feature EU-1573 (transfer pairing, either side first) | R1, R3 |
| projector.feature EU-1575 (L4 when nothing is in flight) | R3 |
| session.feature EU-1580, EU-1581 (whole session, double delivery) | R1, R3 |
| session.feature EU-1582, EU-1584 (buy-in refused, two buy-ins) | R2 |
| session.feature EU-1583 (top-up refused mid-round) | R1 |
| acceptance EA-0014 (smoke: buy in, play, cash out) | R3 |
| acceptance EA-0016 (leave and wait for the credit) | R4, R3 |
| acceptance EA-0030 (top-up between rounds) | R1, R3 |
| acceptance EA-0047 (L4 after a scripted session) | R1, R3 |

The whole of `session.feature` (EU-1580..1584) is held back, so the file is
absent. Ledger rule L4 has no citing rule-tier scenario until EA-0047
returns. `check_rule_citations.py` lists L4 in `AWAITING_RULING`, and the
entry should be removed when EA-0047 is back.

## Mapped without a ruling

These are mechanical: the latest contract has a direct equivalent.

| Earlier spec | Latest contract | Where |
|--------------|-----------------|-------|
| `MERGE_STRICT` | `CONFLICT_RESOLUTION_STRICT` (ABORTED, retryable) | table.proto Hit/Stand/DoubleDown; EA-0024 |
| `MERGE_AGGREGATE_HANDLES` | `CONFLICT_RESOLUTION_AGGREGATE_HANDLES` (decide gets the window and must call `resolve_conflicts` with the nonce) | table.proto PlaceBet; EA-0022, EA-0023 |
| `angzarr_deferred`, "deduplicated by provenance" | Reaction commands carry no Handling; the destination stamps its head; dedup on the derived command id | all saga commands (a PM sends none; 14.31) |
| `SYNC_MODE_DECISION` on PM output | DECISION mode (`Handle`), chosen by the buy-in sagas' configuration (the PM sends no commands; 14.31) | buy_in.proto; EU-1550, EA-0026 |
| Waiting for the read models (`SIMPLE`) | `HandleSync` | EA-0017 |
| Routine snapshot every N events | Framework snapshot policy; the newest snapshot is kept | EU-1590, EU-1594, EA-0037 |
| Tags `@sync-mode`, `@merge-strict`, `@merge-aggregate-handles` | `@command-mode`, `@conflict-strict`, `@conflict-aggregate-handles` | cluster.feature |

Also removed with the poker example (the blackjack branch had already
deleted them): the poker protos, including `ai_sidecar.proto`, which the MVP
plan cites as prior art for a policy sidecar. It imported the poker types.
It is still in git history (`spec/20261019-draft`).
