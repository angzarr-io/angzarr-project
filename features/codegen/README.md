# Tier: codegen

Cucumber specs for behaviour **angzarr-cli** owns: linting the
`ComponentOptions` / `(command)` / `(event)` declarations across a compiled
proto tree, and the shape of the handler interfaces and dispatch tables it
generates. Client and coordinator repos do not run this tier.

| Feature | Covers |
|---|---|
| `component_options.feature` | cross-component lint warnings ANZ100-ANZ103 (exit status unaffected); errors for a policy with no destination domain, a process manager with an output domain or an (event) entry from another domain, `starts` on an aggregate's entry, and a `refuses` type that does not resolve or is from another domain; a warning for a process manager with no starting input; starting inputs advertised in the descriptor; a policy's required refusal callback (C-0612; 14.76), the handler result shaped by `refuses`, and the CLI's translate switch naming the scaffold's fact (C-0623); a refusal code refused with the status its `(refusal_status)` marks, FAILED_PRECONDITION unset (C-0745), the option outside a refusal's Reason, or on its zero value, a lint error (C-0746; 14.52); a policy's generated code sending each output in the arm its destination declares (C-0794; 14.69, 14.73), a domain given a refusal handler for each command its policies send (C-0795; 14.73, 14.76), every handler returning a list of events (C-0797; 14.75), and errors for a command a policy may send that declares no `refuses` (C-0798) and for a policy whose source takes no fact (C-0799; 14.76) |
| `descriptor.feature` | The whole ComponentDescriptor generated at build time (14.42): the build version and state type (C-0535), Describe answered with it unchanged (C-0565), a policy's one input and output domain (C-0715), no output domain on any other kind (C-0716) |

Generic domain vocabulary only (`order`, `inventory`, `payment`,
`shipping`); scenario IDs are `@C-NNNN`, shared with the other framework
tiers.
