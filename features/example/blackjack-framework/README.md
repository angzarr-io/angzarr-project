# Tier: blackjack framework concepts

Framework concepts — translators (sagas), the buy-in process manager, the
ledger projector, snapshots and a whole wired session — demonstrated through
the blackjack components. In-process tier only: these scenarios observe
internals (what a translator emits, a process's progress, a rebuilt read
model) that the cluster does not expose.

| File | Scope | IDs |
|------|-------|-----|
| `saga.feature` | Top-up requests, facts with exactly-once recording, compensation of refused top-ups, one settled round feeding several follow-ups | EU-1530..1549 |
| `process_manager.feature` | Buy-in steps, refusals undoing the other half, ignoring foreign and repeated news, rebuilding progress | EU-1550..1564 |
| `projector.feature` | Ledger read model, in-flight transfers, ledger rule L4, idempotent replay | EU-1565..1579 |
| `session.feature` | All components in one process: ledger rules L3 and L4 end to end | EU-1580..1589 |
| `snapshot.feature` | Rebuild from snapshot equals full replay; lasting snapshot per shoe | EU-1590..1599 |
