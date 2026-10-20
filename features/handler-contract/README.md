# Tier: handler-contract

Cucumber specs for behaviour the **client library** owns when the
coordinator calls the business process: answering
`ComponentService.Describe` with its one component, and, inside
`CommandHandlerService.Handle` and `ProcessManagerService.Handle`, what
happens between the delivery and business code and between business code
and the answer. That is the rules version reported with every answer and in
each description, upcasting and unknown types, and the conflict nonce and
COMMUTATIVE resolution.

## Files

| Feature | Covers |
|---|---|
| `handling.feature` | Describing the process's one component, and refusing a second; the post-command state on every answer; the build version on every answer and in each description; snapshots folded unchecked; command and fact upcasting and the unknown-type refusal; the AGGREGATE_HANDLES nonce; the COMMUTATIVE resolver |

## Who runs these

- **angzarr-router** is the only implementer: the shared dispatch core every
  client library links. Its conformance suite binds these scenarios by ID
  and runs them against the Rust core and every language binding.
- The coordinator's side of the same behaviour (stamping the version,
  choosing snapshots, delivering the window and the nonce) is in
  [`../coordinator-contract/`](../coordinator-contract/).

## Domain vocabulary

Generic only: `order`, `inventory`, `payment`, `shipping`. No poker types
(STEP_VOCABULARY.md §12, §17).

## Scenario IDs

`@C-NNNN`, shared with `../client/`, `../coordinator-contract/`,
`../codegen/` and `../../parity/`. Allocate the next with:

```bash
git grep -hoE '@C-[0-9]{4}' -- features parity | sort -u | tail -1
```
