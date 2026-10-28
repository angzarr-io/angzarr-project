# Tier: codegen

Cucumber specs for behaviour **angzarr-cli** owns: linting the
`ComponentOptions` / `(command)` / `(event)` declarations across a compiled
proto tree, and the shape of the handler interfaces and dispatch tables it
generates. Client and coordinator repos do not run this tier.

| Feature | Covers |
|---|---|
| `component_options.feature` | cross-component lint warnings ANZ100-ANZ103 (exit status unaffected); errors for a saga with no destination domain, a process manager with an output domain or an (event) entry from another domain, `starts` on an aggregate's entry, and a `refuses` type that does not resolve or is from another domain; a warning for a process manager with no starting input; starting inputs advertised in the descriptor; the refusal modes' generated handlers, the handler result shaped by `refuses`, and the CLI-only refusal switch |

Generic domain vocabulary only (`order`, `inventory`, `payment`,
`shipping`); scenario IDs are `@C-NNNN`, shared with the other framework
tiers.
