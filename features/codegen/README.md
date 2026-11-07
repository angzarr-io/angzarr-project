# Tier: codegen

Cucumber specs for behaviour **angzarr-cli** owns: linting the
`(component)` / `(command)` / `(fact)` / `(event)` / `(refusal_status)`
declarations across a compiled proto tree, and the shape of the handler
interfaces, dispatch tables and descriptors it generates
(`docs/design/component-options.md`, `docs/design/component-descriptors.md`).
Client and coordinator repos do not run this tier.

| Feature | Covers |
|---|---|
| `component_options.feature` | cross-component lint warnings ANZ100-ANZ103 (exit status unaffected); sources derived from the events named (14.78): a policy or projector naming no event (C-0855), a policy with events of two domains, each folded by its domain's aggregate (C-0856), an override on an owned event (C-0857), a process manager folding another domain's event (C-0604); a consumer outside the generated set skipped with a warning naming it (C-0858; 14.99); the one required component name (C-0859; 14.87); a policy with no destination domain (C-0582); `starting_types` copied into the descriptor (C-0607), warned when empty (C-0611), refused when not the PM's own input (C-0860; 14.91); a generated policy's one refusal callback over its target's refusal messages (C-0612; 14.89), none for a target that cannot refuse (C-0861; 14.99); the handler result shaped by `refuses` (C-0625); a refusal message refused with the status it declares (C-0745), no status or UNSPECIFIED a failure (C-0862; 14.95), the option on a message no command refuses with a failure (C-0746), ExpectedSequenceMismatch excepted (C-0863; 14.94); two attributes, `#[handles_cmd]` returning `Emit` and `#[handles_fact]` returning `FactEmit`, each following the option (C-0648, C-0864; 14.110), a fact step returning a refusal a failure (C-0876), a message under the other kind's attribute a failure (C-0877; replaces C-0650), both options a failure (C-0865; 14.91); a PM starting from a command or a fact (C-0651); a policy's generated code sending each output in the arm its destination declares (C-0794; 14.69); every handler returning a list of events (C-0797; 14.75); a policy whose target can refuse and whose source, an aggregate folding the event, takes no fact (C-0799) |
| `descriptor.feature` | The whole ComponentDescriptor generated at build time (14.42), its kind a oneof (14.78) and types named by name (14.101): the build version and state type_name (C-0535), Describe answered with it unchanged (C-0565), a policy's derived input and declared output domain (C-0715), each kind's arm and nothing else, a projector naming an event (C-0716; C-0855), a PM's domain, state and starting types (C-0866), a projector's derived input domains, each event folded by the aggregate of its domain (C-0867) |

Generic domain vocabulary only (`order`, `inventory`, `payment`,
`shipping`); scenario IDs are `@C-NNNN`, shared with the other framework
tiers.
