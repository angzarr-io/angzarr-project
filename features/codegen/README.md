# Tier: codegen

Cucumber specs for behaviour **angzarr-cli** owns: linting the
`ComponentOptions` / `(command)` / `(event)` declarations across a compiled
proto tree, and the shape of the handler interfaces and dispatch tables it
generates. Client and coordinator repos do not run this tier.

| Feature | Covers |
|---|---|
| `component_options.feature` | `facts` (one fact handler per entry; aggregates only) and `emits_facts` (lint against target-domain aggregates' `facts`) |

Generic domain vocabulary only (`order`, `inventory`, `payment`,
`shipping`); scenario IDs are `@C-NNNN`, shared with the other framework
tiers.
