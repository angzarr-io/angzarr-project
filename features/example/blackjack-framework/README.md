# Tier: blackjack framework concepts

Framework concepts — translators (policies), the buy-in process manager, the
ledger projector and snapshots — demonstrated through
the blackjack components. In-process tier only: these scenarios observe
internals (what a translator emits, a process's progress, a rebuilt read
model) that the cluster does not expose.

| File | Scope | IDs |
|------|-------|-----|
| `policy.feature` | One settled round feeding the table-to-wallet translator: a round result and loyalty points per seat | EU-1530..1549 |
| `process_manager.feature` | Buy-in steps, ignoring foreign and repeated news, rebuilding progress | EU-1550..1564 |
| `projector.feature` | Ledger read model, in-flight buy-ins, idempotent replay | EU-1565..1579 |
| `snapshot.feature` | Rebuild from snapshot equals full replay | EU-1590..1599 |

`session.feature` (EU-1580..1589, a whole session across every component, run in the in-process test tier) and the
top-up, fact, compensation, buy-in failure, retraction and lasting-snapshot
scenarios of the earlier spec wait on rulings; each is listed, by ID, in
[`docs/design/blackjack-latest-proto-rulings.md`](../../../docs/design/blackjack-latest-proto-rulings.md).
