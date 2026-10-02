# Tier: blackjack cluster acceptance

Scenarios that only make sense against the deployed blackjack example: what a
caller waiting for an answer gets, two callers acting at once, restarts, and
querying stored history (snapshots, what-ifs, as-of reads, live views).
Assertions come from the event stream, stored history and the ledger query
service, never from the test's own bookkeeping.

Runners read `PLAYER_URL`, `TABLE_URL` and `LEDGER_URL`. `within N seconds`
is allowed here ([STEP_VOCABULARY.md §4](../../STEP_VOCABULARY.md)).

`@needs-core-X-NNN` marks a scenario that depends on the framework fix for
review finding X-NNN. Required CI runs exclude those tags; the fix's PR
removes the tag.

| File | IDs |
|------|-----|
| `cluster.feature` | EA-0014..0049 |
