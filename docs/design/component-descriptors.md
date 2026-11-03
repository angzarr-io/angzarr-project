# Component descriptors: self-description and the coordinator's checks

**Status:** normative (decisions 14.24, 14.31, 14.41, 14.42, 14.53, 14.55; as amended by decisions 14.78, 14.91, 14.101 and 14.102). Moved from `proto/io/angzarr/v1/types.proto`'s comments (decision 14.109). Covers what a component descriptor is, how it is generated or written by hand, its kinds, and the checks the coordinator makes of it. The messages are `types.proto`'s `ComponentKind`, `ComponentDescriptor`, `AggregateDescriptor`, `ProcessManagerDescriptor`, `PolicyDescriptor`, `ProjectorDescriptor` and `StateDescriptor`; the service is `component/v1/component.proto`'s `ComponentService`.

## 1. What a descriptor is

A ComponentDescriptor is component self-description: the one component a
business process is. The coordinator pulls it from the business process
(ComponentService.Describe; [component-registration.md](component-registration.md)
§3); holding it is what makes the component registered
([component-registration.md](component-registration.md) §4). Never stored.

ComponentKind names a kind of dispatch component as a bare tag: in a dead
letter (AngzarrDeadLetter.source_component_kind, stored), in the DLQ
admin's StoredDeadLetter, and as a reason's component_kind arg. A
declaration and a descriptor say their kind by the case of their `kind`
oneof (decision 14.78), and each language derives this tag from it.

## 2. Generated or written by hand

Generated or written by hand, then validated (decision 14.42, amended).
angzarr-cli generates the whole descriptor at build time from the
component's protos (its (component) declaration, its (command) and
(event) entries and its (state) message), with rules_version the build's
baked-in version, and a policy's and a projector's sources derived from
the events they name ([component-options.md](component-options.md) §4;
decision 14.78). Generated code is
hand-replaceable: business code may write the descriptor itself instead,
to this message's documented schema (a client library may offer one
builder per kind for it), and a hand-written descriptor is held to
exactly the rules a generated one is. Either way the business process
answers Describe with it unchanged, and the client library's router never
builds or checks it, nor does the component host: the coordinator owns
every descriptor check (decision 14.102).

## 3. Kinds

The kind is a oneof (decision 14.78, from the owner's ruling #2): each
arm holds exactly what that kind has, so no field is set on a kind that
may not have it.

Type identity is a fully-qualified NAME everywhere in a descriptor (the
state's type_name, a process manager's starting_types), never a type URL
(decision 14.101).

- **Aggregate.** The domain of the stream it owns is copied from its
  declaration (AggregateDecl.domain). Required: after the one component
  name (F8) the name no longer implies the domain (decision 14.101,
  ruled 2026-11-02). Its event-sourced state is generated from the state message's
  descriptor by angzarr-cli, or written by hand to the same rules.
- **Process manager** (a PM is a domain, decision 14.31). The domain of
  its own workflow stream is copied from its declaration
  (ProcessManagerDecl.domain); required (decision 14.101). Its
  state is as an aggregate's. Its starting_types are the fully-qualified
  type NAMES of its STARTING inputs (§5).
- **Policy**: its one source and its one destination. The input_domain is
  the one domain whose events it reacts to, derived by angzarr-cli from
  the events it names ([component-options.md](component-options.md) §4;
  decision 14.78). The output_domain
  is the one domain its commands and facts go to
  (PolicyDecl.output_domain, options.proto; decision 14.24); every Output
  is addressed to it (io.angzarr.handler.v1.Output).
- **Projector**: its sources, the domains whose events it projects,
  derived by angzarr-cli from the events it names
  ([component-options.md](component-options.md) §4; decision 14.78). There is no wildcard domain (decision 14.53).

A StateDescriptor is a component's state message, as the domain-blind
coordinator needs it: its type, which the snapshot rule checks
([snapshots.md](snapshots.md) §3). Nothing of its schema.

## 4. The coordinator's checks

The COORDINATOR validates what a type cannot hold to, and refuses (see
[component-registration.md](component-registration.md) §6) a descriptor
that has:

- an empty rules_version (`ANGZARR_REASON_MISSING_RULES_VERSION`);
- no kind, the oneof unset (`ANGZARR_REASON_DESCRIPTOR_NO_KIND`);
- an aggregate or a process manager with no domain
  (`ANGZARR_REASON_DESCRIPTOR_NO_DOMAIN`) or no state
  (`ANGZARR_REASON_MISSING_STATE_TYPE`);
- a policy or a projector with no source
  (`ANGZARR_REASON_NO_INPUT_DOMAIN`: a policy's empty input_domain, a
  projector's empty input_domains; decision 14.101, one rule, the
  coordinator's; for a projector also decision 14.55);
- a policy with no output_domain
  (`ANGZARR_REASON_POLICY_NO_OUTPUT_DOMAIN`).

The coordinator owns every descriptor check.

rules_version is the business binary's full version, baked in when it is
built: the same value the component reports on every answer
(io.angzarr.handler.v1.HandleResponse.rules_version). Because the
coordinator refuses a descriptor with an empty rules_version, a binary
built without a version is never registered and never delivered to
([component-registration.md](component-registration.md) §6 for how the
refusal surfaces). The coordinator checks
snapshot versions against it before offering a snapshot
([snapshots.md](snapshots.md) §3), and refuses an answer that reports any
other version.

An answer whose rules_version or state type is not the registered one is
the coordinator's to refuse (`ANGZARR_REASON_RULES_VERSION_MISMATCH`,
`ANGZARR_REASON_STATE_TYPE_MISMATCH`).

## 5. A process manager's starting types

starting_types are the fully-qualified type NAMES (no type URL prefix:
"examples.v1.OpenTable", never "/examples.v1.OpenTable") of the command
and fact types that are the PM's STARTING inputs, copied from its
declaration's starting_types
([component-options.md](component-options.md) §9; decision 14.91). The coordinator matches an input by the name its type URL ends
in, after upcasting (decision 14.41). An input for a root with no
PM instance is delivered only if its type is listed here; otherwise the
coordinator dead-letters a fact and refuses a command (ruling B1,
adapted; decision 14.31; see [process-managers.md](process-managers.md)
§4).
