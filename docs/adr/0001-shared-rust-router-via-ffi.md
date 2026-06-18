# ADR 0001 — Shared client router in Rust, FFI-bound into every language

## Status

Accepted. Proven across Rust, Go, and Python by the bootstrap units (S1
projector, S2 saga); process-manager (S3) and the ABI freeze review remain.
This is the architecture of record for client-side dispatch going forward.

## Context

Angzarr ships a client in seven languages (Go, Rust, Python, Java, C#, C++,
TypeScript). Each one independently hand-wrote the **dispatch engine**: the
logic that routes commands/events to business handlers, rebuilds aggregate
state from prior events and snapshots, stamps destination sequences, fans
rejections out to ordered compensators, and maps failures to coded
`google.rpc.Status` errors.

That engine is semantically dense and full of subtle, load-bearing invariants:

- fill-only correlation propagation onto emitted books,
- last-page-only process-manager trigger,
- undeclared domain / event / rejection is **silent, not an error**
  (delegate-to-framework),
- exact type-URL match (no suffix matching),
- ordered compensation fan-out, first-escalation-wins,
- snapshot covered-page boundary, gap pages never terminal.

Each language was a line-for-line transliteration of the same rules, and each
re-encoded and re-tested them. The cost and the risk are both real:

- **Size** — the dispatch layer is roughly 3,300 (Go) to 5,000 (Rust) prod
  LOC per language, ~4,000 on average, of which the bulk is semantics rather
  than glue. Across six languages that is ~24,000 LOC implementing *the same
  behavior six times*.
- **Drift** — divergence is not hypothetical. Inside the Go client alone,
  three parallel dispatch stacks had drifted far enough that unifying them
  meant deleting ~9,100 lines. Six independent reimplementations multiply that
  failure mode.
- **One fix, six edits** — every semantic correction or new component kind had
  to be ported, by hand, into each language and re-verified there.

## Decision

Implement the dispatch engine **once, in Rust**, and share it across all
languages through a C ABI.

- `angzarr-router` (core crate) holds the dispatch state machines, rebuild,
  error model, and sequence stamping — the framework semantics, implemented
  exactly once.
- `angzarr-router-ffi` exposes a versioned C ABI over the core (per-kind
  `register_*` / `dispatch_*` entry points; one callback gateway).
- `client-rust` consumes the core natively; every other language links the
  cdylib through a **thin binding** that only marshals protobuf across the
  boundary and routes callbacks. Bindings carry no business semantics.
- Per-language dispatch engines **retire at parity**. `angzarr-cli` stays as
  the codegen tool and emits the per-kind binding wiring.

Boundaries that do **not** move:

- **Transport and the sidecar coordinator are untouched.** The granularity
  rule: per-event business callbacks go in-process over the FFI; whole-book,
  no-callback semantics remain coordinator concerns. The coarse gRPC wire is
  unchanged.
- **State never crosses the ABI.** Host state lives behind an opaque
  `host_ctx` the binding parks per dispatch; the core never sees it.
- **Errors cross as `google.rpc.Status`** carrying a `google.rpc.ErrorInfo`
  (reason = SCREAMING_SNAKE code, domain `angzarr.io`) — no invented error
  proto.

Quality gates: the core is mutation-tested (kill ≈ 1.0), and a **single**
behavioral conformance suite (Gherkin `.feature` files) runs unchanged against
the Rust core and every language binding — the same spec proves Liskov
substitutability everywhere.

## Consequences

### Positive

- The dispatch semantics exist **once, not six/seven times**. Measured prod
  LOC for the dispatch layer (transport excluded): per language ~4,000 →
  ~1,300 (semantic share ~4,000 → ~350 amortized); across six languages
  ~24,000 → ~7,800 (~3×). The number that drives correctness — how many times
  the hard semantics are written and maintained — goes from six to one.
- A fix lands once and is true everywhere; new component kinds are added in the
  core and inherited by every language.
- The core is mutation-hardened and the behavior is pinned by one shared
  conformance suite, so cross-language equivalence is *proven*, not asserted.
- The ABI is explicitly versioned; a binding and a drifted cdylib refuse each
  other instead of marshaling garbage.

### Negative / costs

- Each binding adds FFI ceremony the old engines lacked: cgo/cffi trampolines,
  copy-at-the-boundary buffer ownership, panic guards so nothing unwinds across
  the ABI.
- A C ABI is now a contract that must be versioned and, eventually, frozen.
- Every non-Rust language's build/CI must produce or carry the router cdylib.
- Debugging a dispatch now crosses a language boundary (host ⇄ Rust).

### Neutral

- Rust is the implementation language for shared client logic; commonality is
  chosen over per-language purity.
- The bootstrap deliberately defers the ABI freeze until all four component
  kinds (aggregate, projector, saga, process-manager) have landed, so the
  freeze captures the real surface.

## References

- `angzarr-router/docs/decision-shared-rust-router.md` — the originating
  decision and granularity analysis.
- `angzarr-router/docs/plan-shared-router-bootstrap.md` — the staged bootstrap
  (review units, conformance, ABI freeze).
- `client-go/docs/architecture.md` — the engine-semantics table the core
  implements as its contract.
