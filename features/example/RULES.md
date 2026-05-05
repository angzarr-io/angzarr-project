# Rule Reference

Every poker scenario in `features/example/unit/*.feature` and
`features/example/acceptance/*.feature` cites the real-world poker rule it
expresses via a `# Rule:` comment. This document catalogues those citations
so anyone reading a scenario can find the source rule, and anyone reading
the rules can find which scenario(s) codify them.

## Rule sources

| Source       | Version                | Canonical URL                                      |
|--------------|------------------------|----------------------------------------------------|
| **TDA**      | 2024 v1.0 (Oct 9 2024) | https://www.pokertda.com/poker-tda-rules/         |
| **TDA-RP**   | 2024 (longform addendum) | https://www.pokertda.com/poker-tda-rules/         |
| **Robert's** | v11 (Bob Ciaffone)     | https://www.pagat.com/docs/RobsPkrRules11.pdf      |
| **WSOP**     | 2025 Tournament Rules  | https://wsop.gg-global-cdn.com/wsop/pdfs/2025-WSOP-Tournament-Rules.pdf |

The TDA Rules supplement the conventional rules of any house. WSOP overrides
TDA where they disagree (TDA Rule 1: "in case of conflict with a gaming
agency, the agency rules apply"). Robert's Rules of Poker fills in gaps that
TDA delegates to "house rules" (most importantly: detailed odd-chip
distribution, hand-evaluation tiebreaks, and showdown card-by-suit
disambiguation).

## Rule → scenarios index

The numbers below refer to TDA 2024 longform sections unless prefixed.

| Rule                                                | Scenarios                          |
|-----------------------------------------------------|------------------------------------|
| TDA Rule 7  — random correct seating                 | EU-1182                            |
| TDA Rule 8A — late registration / re-entry full stack| EU-0857..0860                      |
| TDA Rule 8B — re-entry forfeited chips removed       | EU-1151                            |
| TDA Rule 10A — broken-table seating options          | EU-1183                            |
| TDA Rule 11A — table balancing: BB-next to worst seat| EU-1180; EA-0012 (cluster, @wip)   |
| TDA Rule 11D — halt play when 3+ short                | EU-1184                            |
| TDA Rule 13A — must table all hole cards              | EU-1200, EU-1271                   |
| TDA Rule 13C — dealer cannot kill obvious winner      | EU-1272                            |
| TDA Rule 14 — multi-place tournament payout           | EU-0861..0865                      |
| TDA Rule 15B — mucked-while-claiming, uncalled refund | EU-1261                            |
| TDA Rule 16 — face-up for all-ins                     | EU-1220                            |
| TDA Rule 17A — showdown order (last aggressor first) | EU-1120..1124                      |
| TDA Rule 17B — uncontested showdown                  | EU-1221                            |
| TDA Rule 19 — Hold'em "playing the board"            | EU-1200, EU-1201                   |
| TDA Rule 20A — odd chip to seat left of button       | EU-1170                            |
| TDA Rule 20C — odd chip in H/L split to high side    | EU-1171                            |
| TDA Rule 21 — side pots split separately             | EU-1100..1109                      |
| TDA Rule 23 — level change applies to next hand      | EU-1210, EU-1211                   |
| TDA Rule 24A — chip race: max 1 chip / no race-out   | EU-1160, EU-1161                   |
| TDA Rule 24C — non-rescue race chips removed         | EU-1162                            |
| TDA Rule 27 — declared rebuy plays behind             | EU-1150                            |
| TDA Rule 28 — rabbit hunting prohibited               | EU-1270                            |
| TDA Rule 29 — action clock 25s + 5s countdown        | EU-1130, EU-1131, EU-1132          |
| TDA Rule 30 — at-seat for live hand; absent forfeit  | EU-0009, EU-1145, EU-1146          |
| TDA Rule 32 — dead button                             | EU-0575..0578                      |
| TDA Rule 33 — dodging blinds penalty                  | EU-1185                            |
| TDA Rule 34A — incorrect button movement after SA    | EU-1290                            |
| TDA Rule 34B — heads-up: dealer = SB                 | EU-0543, EU-0577                   |
| TDA Rule 35A — misdeal taxonomy (pre-SA redeal)      | EU-1230                            |
| TDA Rule 35B — two consecutive cards on button OK    | EU-1273                            |
| TDA Rule 35C — re-deal preserves button              | EU-1274                            |
| TDA Rule 35E — fouled deck (duplicate rank+suit)     | EU-1231                            |
| TDA Rule 36 — substantial action threshold            | EU-1232                            |
| TDA Rule 37 — button with too few cards               | EU-1275                            |
| TDA Rule 38 — one burn per street                     | EU-1233                            |
| TDA Rule 39A — 4-card flop                            | EU-1276                            |
| TDA Rule 39B — no-burn flop (pre/post action)        | EU-1277, EU-1278                   |
| TDA Rule 43 — minimum raise = largest prior raise    | EU-0017, EU-0067, EU-1000..1003    |
| TDA Rule 43A — 50%-rule for silent push              | EU-1133, EU-1134                   |
| TDA Rule 47A — short all-in does not reopen          | EU-1007, EU-1141                   |
| TDA Rule 47A (cum.) — multi short all-in reopens     | EU-1140                            |
| TDA Rule 47B — limit 50% threshold reopens           | EU-1295                            |
| TDA Rule 48 — limit raise cap (1+4)                   | EU-1296                            |
| TDA Rule 52A — underbet/underraise correction (NL)   | EU-1135, EU-1250                   |
| TDA Rule 52B — pot-limit underbet correction         | EU-1284                            |
| TDA Rule 53A — out-of-turn action                     | EU-1240, EU-1241, EU-1242          |
| TDA Rule 53B — skipped player must defend            | EU-1285                            |
| TDA Rule 54 — pot-limit bet calculation              | EU-0738                            |
| TDA Rule 54B — PL pre-flop assumes full blinds       | EU-1286                            |
| TDA Rule 54D — "bet the pot" in NL = min bet         | EU-1287                            |
| TDA Rule 55 — invalid bet declarations                | EU-1288                            |
| TDA Rule 58 — non-standard folds binding              | EU-1289                            |
| TDA Rule 65A — accidentally killed hand refund       | EU-1260                            |
| TDA Rule 71A — penalty options                        | EU-1310                            |
| TDA Rule 71C — player on penalty (cards killed)      | EU-1311                            |
| TDA Rule 71D — DQ chips removed from play            | EU-1312                            |
| TDA RP-5 — premature flop / turn / river              | EU-1280, EU-1281, EU-1282          |
| TDA RP-8A — H4H simultaneous bust splits payout      | EU-1190                            |
| TDA RP-8B — H4H deducts ≤3 minutes per hand          | EU-1191                            |
| TDA RP-8C — H4H clock reduction per-hand, not batched| EU-1192                            |
| TDA RP-9  — final-table combination 5+5 → 9          | EU-1181                            |
| TDA RP-9 / WSOP Rule 68 — FT combine 8/7/6-handed    | EU-1187, EU-1188                   |
| TDA RP-11 — BB-ante format; no ante reduction        | EU-1110, EU-1111                   |
| WSOP Rule 14 — late reg first hand can be SB/BB/btn  | EU-1313                            |
| WSOP Rule 16 — no-show chips removed                  | EU-1314                            |
| WSOP Rule 34 — random seat assignment                 | EU-1182                            |
| WSOP Rule 36 — heads-up absent blind progression     | EU-1315                            |
| WSOP Rule 67c — seat redraw at 3/2/FT thresholds     | EU-1316                            |
| WSOP Rule 85 — initial button at first stack right   | EU-1186                            |
| WSOP Rule 126b — same-table multi-bust tiebreak      | EU-1317                            |
| TDA Rule 11B — HORSE button shifts (mixed games)     | EU-1320                            |
| TDA Rule 17A (stud) — high hand showing tables first | EU-1321                            |
| TDA Rule 20B — stud odd chip high-by-suit            | EU-1322                            |
| TDA Rule 35A-6 (stud) — exposed downcard = misdeal   | EU-1323                            |
| TDA Rule 66 — stud mucking (turn down all up cards)  | EU-1324                            |
| TDA RP-10A — exposed downcard becomes upcard         | EU-1325                            |
| TDA RP-10B — exposed 7th street replacement          | EU-1326                            |
| TDA RP-10C — absent player no 4th street             | EU-1327                            |
| TDA RP-10D — stud tiebreak by suit                   | EU-1328, EU-0753, EU-0754          |
| TDA RP-10E — bring-in all-in for ante                | EU-1329                            |
| TDA RP-10F — no doubled bet on open pair 4th street  | EU-1330                            |
| TDA RP-10G / RP-5D — premature stud card             | EU-1332                            |
| TDA RP-10H sub-A — short stub: prior burns sufficient| EU-1333                            |
| TDA RP-10H sub-B — stub ≥3 but burns insufficient    | EU-1334                            |
| TDA RP-10H sub-C — 7th street short stub community   | EU-1331                            |
| WSOP §SC Stud — 3 first cards down: scramble & turn  | EU-1335                            |
| WSOP §SC Stud — wrong bring-in correction window     | EU-1336                            |
| WSOP §SC Stud — bring-in completion ≠ raise          | EU-1337                            |
| WSOP §SC Stud — absent at 3rd street forfeits        | EU-1338                            |
| WSOP §SC Stud Hi/Lo + Razz — open pair locks low lim | EU-1339                            |
| Robert's §SC Stud #18 — wrong card count at showdown | EU-1340                            |
| Robert's §RAZZ #3 — open pair doesn't affect razz lim| EU-1341                            |
| WSOP §Seven Card Stud — variant definition           | EU-0750, EU-0751, EU-0753, EU-0755, EU-0757 |
| WSOP §Seven Card Razz — variant + low evaluation     | EU-0750, EU-0754, EU-0756, EU-0758, EU-0759 |
| WSOP §Stud Hi/Lo 8b — qualifier rule                 | EU-0760                            |
| Robert's §1 — universal hand hierarchy               | EU-0029..0042, EU-0705, EU-0757    |
| Robert's §31 — kicker = highest remaining card       | EU-0707..0709, EU-0729..0736       |
| Robert's §35-5(a) — odd chip first seat clockwise    | EU-1170                            |
| Robert's §35-9 — multi-way odd chip = high-by-suit   | EU-1172, EU-1322                   |
| Robert's (universal) — wheel A-2-3-4-5 = STRAIGHT    | EU-0717, EU-0033, EU-0737, EU-0758 |
| Robert's §Omaha-1 — must use 2 hole + 3 board        | EU-0711..0713                      |

## Working-but-not-yet-implemented scenarios

Scenarios tagged `@wip` are spec-driven (TDD): they pin behavior the
implementation must produce but haven't yet been wired through to passing
code. The `@wip` tag is removed when the implementation lands. Cluster-tier
@wip scenarios live in `acceptance/cluster_tournament.feature`:

- `EA-0011` color-up chip race (TDA Rule 24)
- `EA-0012` table balancing (TDA Rule 11)
- `EA-0013` hand-for-hand on the bubble (TDA RP-8)

## Convention for adding new scenarios

When adding a scenario that codifies a poker rule:

1. Add a `# Rule: <source> <section> (<version>) — <quote>` comment line
   immediately after the scenario title (or its `@<tag>` line).
2. Cite by source-section identifier, not by URL or page number — the
   sources at the top of this file are versioned and stable enough to
   re-locate by section.
3. If the scenario expresses a corrective behavior (auto-promote, refund,
   etc.) cite the *behavior* clause, not just the rule heading.
4. Add the scenario to the index above so the rule → scenario mapping
   stays current.
