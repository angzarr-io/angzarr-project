# Rule Reference

Every poker scenario in `features/example/poker/*.feature` and
`features/example/acceptance/*.feature` cites the real-world poker rule it
expresses via a `# Rule:` comment (framework-concept scenarios live in
`features/example/framework/` and are out of scope for this catalog).
This document catalogues those citations bidirectionally so anyone reading
a scenario can find the source rule, and anyone reading the rules can find
which scenario(s) codify them.

## Rule sources

| Source       | Version                  | Canonical URL                                                          |
|--------------|--------------------------|------------------------------------------------------------------------|
| **TDA**      | 2024 v1.0 (Oct 9 2024)   | https://www.pokertda.com/poker-tda-rules/                              |
| **TDA-RP**   | 2024 (longform addendum) | https://www.pokertda.com/poker-tda-rules/                              |
| **Robert's** | v11 (Bob Ciaffone)       | https://www.pagat.com/docs/RobsPkrRules11.pdf                          |
| **WSOP**     | 2025 Tournament Rules    | https://wsop.gg-global-cdn.com/wsop/pdfs/2025-WSOP-Tournament-Rules.pdf |

The TDA Rules supplement the conventional rules of any house. WSOP overrides
TDA where they disagree (TDA Rule 1: "in case of conflict with a gaming
agency, the agency rules apply"). Robert's Rules of Poker fills in gaps that
TDA delegates to "house rules" (most importantly: detailed odd-chip
distribution, hand-evaluation tiebreaks, and showdown card-by-suit
disambiguation).

## Audit status (2026-05-05)

A full reverse pass against the canonical TDA 2024 longform (Rules 1-71 +
RP-1 through RP-22) and WSOP 2025 (Rules 1-128 + Sections VIII/IX) was
completed on 2026-05-05. Results:

- **Forward direction**: 100% — all 666 scenarios trace back to a rule
  citation OR a framework rationale.
- **Reverse direction**: every in-scope rule from the canonical reference
  set is mapped below to ≥1 scenario, or marked as a `@wip` gap with a
  scenario authored, or marked as out-of-scope with the reason recorded.

## TDA 2024 — Rules 1 to 71

| Rule | Title                                  | Status      | Scenarios / Reason                              |
|------|----------------------------------------|-------------|-------------------------------------------------|
| 1    | Floor Decisions                        | OUT-OF-SCOPE | subjective floor authority; no implementable behavior |
| 2    | Player Responsibilities                | OUT-OF-SCOPE | human conduct list                              |
| 3    | Official Terminology and Gestures      | covered     | EU-0010..0017 (verbal binding)                  |
| 4    | Player Identity                        | OUT-OF-SCOPE | casino auth / photo ID                          |
| 5    | Electronic Devices                     | OUT-OF-SCOPE | physical-device policy                          |
| 6    | Official Language                      | covered     | EU-1182 (random correct seating cited 6+7)      |
| 7    | Random Correct Seating                 | covered     | EU-1182, EU-0103..0108, EU-0553..0559           |
| 8    | Late Reg / Re-Entry / Forfeit          | covered     | EU-0807..0811 (Rule 8), EU-0857..0860 (8A), EU-1151 (8B) |
| 9    | Special Needs                          | OUT-OF-SCOPE | accommodation policy                            |
| 10A  | New Players & Broken-Table Seating     | covered     | EU-1183                                         |
| 11A  | Balancing Tables — BB-next             | covered     | EU-1180; EA-0012 (cluster, @wip)                |
| 11B  | Mixed-Game Button Shifts (HORSE)       | covered     | EU-1320, EU-1322..1341 (stud variants)          |
| 11D  | Halt Play When 3+ Short                | covered     | EU-1184, EU-1184B (resume), EU-1184C..F (clauses + halt effects) |
| 12   | Cards Speak at Showdown                | covered     | EU-0027..0028, EU-0082..0087, EU-1008, EU-1009  |
| 13A  | Tabling Cards Properly                 | covered     | EU-0025..0026, EU-0077..0081, EU-1271, EU-1272  |
| 13B  | Partial Muck                           | covered     | EU-1200, EU-1271 (must table all hole cards)    |
| 13C  | Dealer Cannot Kill Tabled Hand         | covered     | EU-1272                                         |
| 14   | Live Cards at Showdown                 | covered     | EU-0025..0026, EU-1261                          |
| 15A  | Showdown / Discarding Irregularities   | covered     | EU-1260 (accidentally killed) + EU-1261         |
| 15B  | Mucked While Claiming — Refund         | covered     | EU-1261                                         |
| 16   | Face Up for All-Ins                    | covered     | EU-0057..0066 (10 scenarios), EU-1220, EU-1924  |
| 17A  | Showdown Order — Last Aggressor First  | covered     | EU-1120..1124, EU-1321 (stud)                   |
| 17B  | Uncontested Showdown                   | covered     | EU-0027..0028, EU-1221                          |
| 18   | Asking to See a Hand                   | **@wip**    | **EU-1342, EU-1343** (added 2026-05-05)         |
| 19   | Playing the Board                      | covered     | EU-1200, EU-1201                                |
| 20A  | Odd Chip — Seat Left of Button         | covered     | EU-1170                                         |
| 20B  | Stud — Odd Chip High by Suit           | covered     | EU-1322, EU-1328 + RP-10D coverage              |
| 20C  | H/L Split — Odd Chip to High Side      | covered     | EU-1171, EU-1172                                |
| 21   | Side Pots Split Separately             | covered     | EU-0044..0045, EU-1100..1109                    |
| 22   | Disputed Hands and Pots                | **@wip**    | **EU-1344** (added 2026-05-05)                  |
| 23   | New Limits — Next Hand                 | covered     | EU-0825..0826, EU-0855..0856, EU-1210, EU-1211  |
| 24A  | Chip Race — Max 1 Chip                 | covered     | EU-1160, EU-1161                                |
| 24C  | Non-Rescue Race Chips Removed          | covered     | EU-1162                                         |
| 25   | Discretionary Color-Ups                | **@wip**    | **EU-1345** (added 2026-05-05)                  |
| 26   | Deck Changes                           | OUT-OF-SCOPE | dealer push timing; no aggregate state         |
| 27   | Re-buys (Plays Behind)                 | covered     | EU-0560..0563, EU-0817..0818, EU-0834..0837, EU-1150 |
| 28   | Rabbit Hunting Prohibited              | covered     | EU-1270                                         |
| 29   | Action Clock 25s+5s                    | covered     | EU-1130, EU-1131, EU-1132, EU-1573              |
| 30   | At-Seat Rule                           | covered     | EU-0007..0009, EU-0051..0099, EU-1145, EU-1146  |
| 31   | At Table With Action Pending           | covered     | EU-0109, EU-0110, EU-0111                       |
| 32   | Dead Button                            | covered     | EU-0112..0115, EU-0539..0544, EU-0575..0578     |
| 33   | Dodging Blinds                         | covered     | EU-1185                                         |
| 34A  | Incorrect Button Movement              | covered     | EU-1290                                         |
| 34B  | Heads-Up — Button is SB                | covered     | EU-0112..0115, EU-0539..0544, EU-0575..0578     |
| 35A  | Misdeals — Pre-SA Redeal               | covered     | EU-1230                                         |
| 35A-6 | Stud Misdeal Trigger                  | covered     | EU-1323..1341 (stud-specific)                   |
| 35B  | Two Consecutive Cards on Button OK     | covered     | EU-1273, EU-1274, EU-1275                       |
| 35C  | Re-Deal Preserves Button               | covered     | EU-1274                                         |
| 35D  | Misdeal Sub-Triggers                   | covered     | EU-1230..1233 (sec hdr cites 35A & 35D)         |
| 35E  | Fouled Deck (Duplicate Rank+Suit)      | covered     | EU-1231                                         |
| 36   | Substantial Action Threshold           | covered     | EU-1232, EU-1233                                |
| 37   | Button With Too Few Cards              | covered     | EU-1275                                         |
| 38   | One Burn Per Street                    | covered     | EU-0018..0021, EU-1233                          |
| 39A  | 4-Card Flop                            | covered     | EU-1276                                         |
| 39B  | No-Burn Flop (Pre/Post Action)         | covered     | EU-1277, EU-1278                                |
| 40   | Verbal vs Chip Betting                 | **@wip**    | **EU-1346, EU-1347** (added 2026-05-05)         |
| 41   | Methods of Calling                     | **@wip**    | **EU-1348** (added 2026-05-05)                  |
| 42   | Methods of Raising                     | **@wip**    | **EU-1346** (verbal raise → min legal)          |
| 43   | Min Raise = Largest Prior Raise        | covered     | EU-0017, EU-0067, EU-1000..1003, EU-0043, etc.  |
| 43A  | 50%-Rule for Silent Push               | covered     | EU-1133, EU-1134, EU-1135                       |
| 44   | Oversized Chip = Call (Silent)         | **@wip**    | **EU-1350** (added 2026-05-05)                  |
| 45   | Multiple Chip Betting                  | **@wip**    | **EU-1351** (added 2026-05-05)                  |
| 46   | Prior-Bet Chips Not Pulled In          | **@wip**    | **EU-1352, EU-1353** (added 2026-05-05)         |
| 47A  | Short All-In — No Reopen               | covered     | EU-0088..0092, EU-0903, EU-1006, EU-1007, EU-1141 |
| 47A (cum.) | Multi Short All-In Reopens       | covered     | EU-1140, EU-1141                                |
| 47B  | Limit 50% Threshold Reopens            | covered     | EU-1295                                         |
| 48   | Limit Raise Cap (1+4)                  | covered     | EU-1296                                         |
| 49   | Accepted Action                        | **@wip**    | **EU-1354, EU-1355** (caller responsibility)    |
| 50   | Acting in Turn                         | covered     | EU-0900, EU-0901, EU-0902                       |
| 51   | Binding Declarations / Undercalls      | **@wip**    | **EU-1354, EU-1355** (added 2026-05-05)         |
| 52A  | NL Underbet/Underraise Correction      | covered     | EU-1135, EU-1250                                |
| 52B  | PL Underbet Correction                 | covered     | EU-1284                                         |
| 53A  | Out-of-Turn Action                     | covered     | EU-1240, EU-1241, EU-1242                       |
| 53B  | Skipped Player Must Defend             | covered     | EU-1285                                         |
| 54B  | PL Pre-Flop Full-Blinds Assumption     | covered     | EU-1286                                         |
| 54D  | "Bet the Pot" in NL = Min Bet          | covered     | EU-1287                                         |
| 55   | Invalid Bet Declarations               | covered     | EU-0010..0017 + EU-1288 (25 total)              |
| 56   | String Bets and Raises                 | **@wip**    | **EU-1356** (added 2026-05-05)                  |
| 57   | Non-Standard / Unclear Betting         | **@wip**    | **EU-1357** (added 2026-05-05)                  |
| 58   | Non-Standard Folds Binding             | covered     | EU-1289                                         |
| 59   | Conditional / Premature Declarations   | **@wip**    | **EU-1358** (added 2026-05-05)                  |
| 60   | Count of Opponent's Stack              | **@wip**    | **EU-1359** (added 2026-05-05)                  |
| 61   | Over-Betting Expecting Change          | **@wip**    | **EU-1360** (added 2026-05-05)                  |
| 62   | All-In with Chips Found Behind         | **@wip**    | **EU-1361** (added 2026-05-05)                  |
| 63   | Chips Out of View / In Transit         | OUT-OF-SCOPE | physical chip handling                          |
| 64   | Lost and Found Chips                   | OUT-OF-SCOPE | physical / human                                |
| 65A  | Accidentally Killed Hand Refund        | covered     | EU-1260, EU-1261                                |
| 66   | Stud Mucking                           | covered     | EU-1324, EU-1330..1341                          |
| 67   | No Disclosure / One Player to a Hand   | **@wip**    | **EU-1362** (added 2026-05-05)                  |
| 68   | Exposing Cards / Proper Folding        | **@wip**    | **EU-1363** (added 2026-05-05)                  |
| 69   | Ethical Play (Soft Play)               | covered     | EU-1374 (DQ for soft play)                      |
| 70   | Etiquette Violations                   | OUT-OF-SCOPE | subjective; no aggregate behavior               |
| 71A  | Penalty Options                        | covered     | EU-1310                                         |
| 71C  | Penalty (Cards Killed)                 | covered     | EU-1311                                         |
| 71D  | DQ Chips Removed from Play             | covered     | EU-1312, EU-1374                                |

## TDA 2024 Recommended Procedures (RP-1 to RP-22)

| RP   | Title                                    | Status       | Scenarios / Reason                              |
|------|------------------------------------------|--------------|-------------------------------------------------|
| RP-1 | All-In Buttons                           | OUT-OF-SCOPE | physical button placement                       |
| RP-2 | Bringing in Bets is Discouraged          | OUT-OF-SCOPE | dealer mechanics                                |
| RP-3 | Personal Belongings                      | OUT-OF-SCOPE | physical                                        |
| RP-4 | Disordered Stub                          | **@wip**     | **EU-1364** (added 2026-05-05)                  |
| RP-5A | Premature Flop                          | covered      | EU-1280                                         |
| RP-5B | Premature Turn                          | covered      | EU-1281                                         |
| RP-5C | Premature River                         | covered      | EU-1282                                         |
| RP-5D | Premature Stud Card                     | covered      | EU-1332..1341                                   |
| RP-6 | Efficient Movement of Players            | OUT-OF-SCOPE | floor operations                                |
| RP-7 | Timing of Dealer Pushes                  | OUT-OF-SCOPE | dealer mechanics                                |
| RP-8A | H4H Simultaneous Bust Splits Payout     | covered      | EU-1190                                         |
| RP-8B | H4H ≤3 Min/Hand Deduction               | covered      | EU-1191                                         |
| RP-8C | H4H Per-Hand Reduction                  | covered      | EU-1192                                         |
| RP-9 | Final-Table Combination 5+5 → 9          | covered      | EU-1181, EU-1187, EU-1188                       |
| RP-10A..H | Stud Dealing Procedures             | covered      | EU-1325..1341                                   |
| RP-11 | BB-Ante Format                          | covered      | EU-1110..1115, EU-0825..0856                    |
| RP-12 | Dealers Should Announce Bets            | OUT-OF-SCOPE | UI/dealer presentation                          |
| RP-13 | Stack Chips in Split-Pot                | OUT-OF-SCOPE | UI                                              |
| RP-14 | Randomness for Special Situations       | **@wip**     | **EU-1365** (added 2026-05-05)                  |
| RP-15 | Tournament Staff Communication          | OUT-OF-SCOPE | floor operations                                |
| RP-16 | Player Absent on Breaking Table         | **@wip**     | **EU-1370** (added 2026-05-05)                  |
| RP-17 | Tournament Draw Betting Procedures      | covered      | EU-0022..0024, EU-0718..0721                    |
| RP-18 | Order of Mixed Games                    | **@wip**     | **EU-1371** (added 2026-05-05)                  |
| RP-19 | Reducing Stalling                       | covered      | TDA Rule 29 coverage subsumes this              |
| RP-20 | Cards Ready for Shuffle                 | OUT-OF-SCOPE | dealer mechanics                                |
| RP-21 | Spreading the Pot                       | OUT-OF-SCOPE | UI                                              |
| RP-22 | Bounty Chips                            | **@wip**     | **EU-1372, EU-1373** (added 2026-05-05)         |

## WSOP 2025 — Notable Rules

WSOP 2025 has 128 numbered rules. Most overlap with TDA — covered above.
Below are WSOP-unique requirements:

| WSOP Rule | Title                                  | Status       | Scenarios / Reason                              |
|-----------|----------------------------------------|--------------|-------------------------------------------------|
| 1-25      | Section I — Registration / Entry       | OUT-OF-SCOPE | casino administration; covered partially by EU-0800..0816 (event registration) |
| 13        | Re-entry per structure sheet           | covered      | EU-0807..0811                                   |
| 14        | Late Reg first hand can be SB/BB/btn   | covered      | EU-1313                                         |
| 16        | No-Show Chips Removed                  | covered      | EU-1314                                         |
| 26-30     | Section II — Scheduling                | OUT-OF-SCOPE | tournament scheduling                           |
| 31-39     | Section III — Prizes / Seating         | partial      | 31 (EU-0861..0865), 34 (EU-1182), 36 (EU-1315), 39 (**@wip EU-1372**) |
| 40-55     | Section IV/V — Conduct / Likeness      | OUT-OF-SCOPE | casino-floor conduct                            |
| 56-119    | Section VI — Poker Rules               | mirrors TDA  | every poker mechanic is covered above           |
| 67b       | Balancing Tables (HORSE)               | covered      | EU-1320..1341                                   |
| 67c       | Seat Redraw at 3/2/FT Thresholds       | covered      | EU-1316                                         |
| 68b/d     | FT Combine 8/7/6-Handed                | covered      | EU-1187, EU-1188                                |
| 85        | Initial Button at First-Stack Right    | covered      | EU-1186                                         |
| 86        | Dodging Blinds                         | covered      | EU-1185                                         |
| 88a-6     | Misdeals / Fouled Decks                | covered      | EU-1323..1341                                   |
| 92        | Multi-Chip = Call When All Needed      | **@wip**     | **EU-1348** (TDA 41 mirror)                     |
| 97        | Oversized Chip = Call                  | **@wip**     | **EU-1350** (TDA 44 mirror)                     |
| 99        | Over-Betting Expecting Change          | **@wip**     | **EU-1360** (TDA 61 mirror)                     |
| 103       | String Bets                            | **@wip**     | **EU-1356** (TDA 56 mirror)                     |
| 105       | All-In Chips Found Behind              | **@wip**     | **EU-1361** (TDA 62 mirror)                     |
| 113       | Penalties — Verbal Warning to DQ       | covered      | EU-1310, EU-1311, EU-1312                       |
| 114       | Disqualification — Chips Removed       | covered      | EU-1312                                         |
| 116       | Table Talk / Disclosure                | **@wip**     | **EU-1362** (TDA 67 mirror)                     |
| 117       | Exposing Cards                         | **@wip**     | **EU-1363** (TDA 68 mirror)                     |
| 118       | Soft Play                              | **@wip**     | **EU-1374** (added 2026-05-05)                  |
| 122       | Day 2+ Suspension                      | **@wip**     | **EU-1376** (added 2026-05-05)                  |
| 125       | End of Day Stop Time                   | **@wip**     | **EU-1375** (added 2026-05-05)                  |
| 126       | Hand for Hand                          | covered      | EU-1190..1192, EU-1317                          |
| 126b      | Same-Table Multi-Bust Tiebreak         | covered      | EU-1317                                         |
| §VIII     | Tournament Betting Formats (NL/PL/Ltd) | covered      | EU-1006, EU-1010..1013, EU-1295, EU-1296        |
| §IX HE    | Texas Hold'em                          | covered      | EU-0007..0009, EU-0073..0075, etc.              |
| §IX Omaha | Omaha (4-card, 2 hole + 3 board)       | covered      | EU-0711..0713                                   |
| §IX Stud  | Seven Card Stud / Hi-Lo / Razz         | covered      | EU-0750..0760, EU-1320..1341                    |
| §IX Draw  | Draw Games                             | covered      | EU-0022..0024, EU-0568, EU-0718..0721           |

## Robert's Rules of Poker (v11) — Gap Fillers

| Rule         | Coverage Reason                                                  | Scenarios |
|--------------|------------------------------------------------------------------|-----------|
| §1           | Universal hand hierarchy (TDA leaves to "house rules")           | EU-0029..0042, EU-0705, EU-0757 |
| §31          | Kicker tiebreak by highest remaining card                        | EU-0707..0709, EU-0729..0736 |
| §31-9        | Must declare playing the board                                   | EU-1200, EU-1201 |
| §35-5(a)     | Odd chip first seat clockwise of button                          | EU-1170 |
| §35-8        | "Chip goes to the high card by suit" (split-pot tiebreak)        | EU-1171, EU-1172 |
| §35-9        | Multi-way odd chip = high-by-suit                                | EU-1172, EU-1322 |
| §38          | Side-pot construction                                            | EU-1100..1109 |
| §RAZZ #3     | Open pair doesn't lock razz limit                                | EU-1341 |
| §SC Draw     | Best 5-card hand from any combo of hole cards                    | EU-0714..0716 |
| §SC Hold'em  | Best 5-card hand from any combo of hole + board                  | EU-0705..0710 |
| §SC Omaha-1  | Must use 2 hole + 3 board                                        | EU-0711..0713 |
| §SC Stud #5/#6/#8/#18 | Stud-specific showdown / tabling rules                  | EU-1336..1341 |

## Out-of-scope rules — rationale

The following categories are intentionally not testable as scenarios:

1. **Subjective floor authority** — TDA 1, 2, 70; WSOP 56, 57. The
   coordinator emits events and rejects commands; "fairness" decisions
   are surfaced as `FloorDecisionRequired` events but not pre-decided.
2. **Casino administration** — TDA 4, 9; WSOP 1-25, 26-30, 40-55. Photo
   ID, registration desks, scheduling, branding are outside the example
   coordinator's domain (player aggregate handles only the funds-locking
   side).
3. **Physical chip handling** — TDA 26, 63, 64; RP-1, RP-3, RP-6, RP-7,
   RP-12, RP-13, RP-15, RP-20, RP-21. The coordinator tracks chip values
   and ownership; transit, stacking, cash drops, and dealer mechanics are
   table-side concerns.
4. **Electronic devices and likeness** — TDA 5; WSOP 52, 53, 54, 55, 64.
   No aggregate impact.

A scenario marked `@wip` is spec-driven (TDD): it pins the behavior the
implementation must produce and is removed/un-tagged when the
implementation lands. See the `@wip` tag policy in `features/example/README.md`.
The implementation plan for the 127 currently-`@wip` scenarios lives in
`features/example/WIP_TRIAGE.md` (organized as 16 batches by shared
proto / handler infrastructure, with effort estimates and dependencies).

## Working-but-not-yet-implemented scenarios (cluster-tier)

`EA-NNNN` scenarios in `acceptance/cluster_tournament.feature` live behind
saga + manifest work:

- `EA-0011` color-up chip race (TDA Rule 24)
- `EA-0012` table balancing (TDA Rule 11)
- `EA-0013` hand-for-hand on the bubble (TDA RP-8)

## Convention for adding new scenarios

When adding a scenario that codifies a poker rule:

1. Add a `# Rule: <source> <section> (<version>) — <quote>` comment line
   inside the scenario or in its containing section header.
2. Cite by source-section identifier, not by URL or page number — the
   sources at the top of this file are versioned and stable enough to
   re-locate by section.
3. If the scenario expresses a corrective behavior (auto-promote, refund,
   etc.) cite the *behavior* clause, not just the rule heading.
4. Update this file's coverage matrix with the new scenario IDs.
