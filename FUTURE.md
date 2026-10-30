# Future

What angzarr doesn't have yet, why each one matters, and the shape we expect it to take. Each entry ends
with what would settle it.

Order: **timers first, then handlers in other processes, then forgetting personal data.** Set-based
validation and outbound side effects are not yet scheduled.

## Why there is no saga primitive

"Saga" means two different things, and angzarr covers both without a primitive of its own.

- **The original saga** (Garcia-Molina and Salem, 1987) is a long-lived transaction split into local
  transactions, each with a *compensating* transaction that undoes it if a later step fails. Its defining
  feature is compensation.
- **The CQRS-framework "saga"** (NServiceBus, Axon) is a stateful event handler that dispatches commands.
  That is Hohpe's *Process Manager* pattern from *Enterprise Integration Patterns*; Microsoft's CQRS
  Journey points out that the name is borrowed. It puts state and decisions in a handler beside the
  aggregates, a second kind of decision-maker with its own persistence, concurrency and testing story.

In angzarr the only decisions are a domain's command handlers, and everything else is assembled from them:

- A **process manager is a domain** (decision 14.31). Its state is aggregate state, rooted at the
  correlation id (14.30), and its decisions are a decide function.
- A **policy** is a stateless event-to-command mapping with no logic of its own (14.33).
- **Compensation** uses the refusal path. When step N's command is refused, `CommandRefused` reaches the
  process manager, which decides to compensate; its events become, through policies, the commands that
  undo steps 1 to N-1.

So orchestration is a process manager, choreography is policies alone, and a 1987 saga is a process
manager that compensates.

The cost is more hops and more streams than a single saga class: event → policy → process-manager command
→ process-manager events → policy → command. That cost is real in the distributed system and close to free
in angzarr-embedded, where a process manager can be built into one binary from standard components.

## Timers and deadlines (first)

*"If no payment arrives within 15 minutes, cancel the order."*

The spec already gives this its shape: a timeout reaches a process manager as a **fact** from a clock or
scheduler source, which it never refuses (see `process_manager.proto` and the commands-vs-facts guide).
Time then stays an input, and replay stays deterministic.

What's missing is anything that produces those facts. There is no scheduler component and no way to say
"deliver this fact at time T". Other frameworks make this central: Axon has `DeadlineManager`, NServiceBus
has `RequestTimeout`, and Temporal is built around timers.

Decided shape: timers emit facts, in two forms:

- **after a duration:** deliver fact F to stream S once N has elapsed;
- **at an instant:** deliver fact F to stream S at time T.

This is a standard component, not a new primitive. A scheduler domain stores each pending timer as its own
events, and something that watches the clock emits the fact once the timer is due. Cancelling a timer is a
command to that domain.

Wanted first by: turn timers in the blackjack example, and taskloom's deferred tasks, which wake on a
revive condition.

Settled by: a red-reviewed scheduler component in angzarr-embedded that delivers a fact on time, survives a
restart, and delivers each fact exactly once, together with a decision on how the distributed system runs
the same component.

## Handlers in other processes (second)

*An aggregate, process manager or policy written in Go or Python, hosted by angzarr-embedded.*

**Status:** the first slice is built, for an aggregate in Python.
- angzarr-embedded's `angzarr-embedded-host` crate: the config, launch, handshake, Unix-socket gRPC, supervision, and
  `RemoteCommandHandler` as a router `CommandHandler`.
- client-python's `angzarr_client.child`.
- `angzarr scaffold python` and `angzarr scaffold startup` in the CLI.
- A blackjack app scaffolded by the CLI plays a hand between a Rust table and a Python player bot.

Still open: remote policies and process managers, Go, and the items below.

The driving case is **Python, for PyTorch**: game engines on angzarr-embedded whose AI runs on PyTorch.

angzarr-embedded runs handlers in-process, in Rust. A handler in another language needs a bridge. The
contract for it already exists: a domain's business logic implements `CommandHandlerService` (decision
14.31), which is a gRPC service.

Decided approach: **gRPC over a local socket.** It lets a handler in any language angzarr supports
run under angzarr-embedded, with one mechanism for all of them. A remote handler is one more
implementation of the handler interface. The kernel keeps
everything it owns (storage, positions, the outbox, router dispatch, the edition lifecycle) and calls out
only for the decision itself. Nothing else crosses the boundary: no bus, no pipes between runtimes. That
is what sank the earlier multiprocess local attempt.

The model is HashiCorp's go-plugin (Terraform providers, Vault and Packer plugins):

- angzarr-embedded launches the handler as a child process;
- the child prints a one-line handshake on stdout naming its socket;
- from then on the two talk gRPC over a Unix domain socket, or a named pipe on Windows. A socket pair
  handed to the child works too, where the handler's gRPC library accepts an open descriptor;
- angzarr-embedded supervises the child. An unreachable handler is a retryable failure, which resume by
  position already handles.

The cost is one local round trip per handler call (microseconds over a Unix socket, against nanoseconds
in-process), plus supervising the child process.

The in-process alternative is WebAssembly: handlers compiled to wasm components, run inside
angzarr-embedded with no sockets and no supervision. The router and angzarr-ports already build for wasm.
Language support is the limit: Rust, Go (TinyGo) and C# are workable; Python and Java are not yet, and
PyTorch's native libraries rule wasm out for the driving case.

The alternatives below were considered and are not the approach. Each covers only some languages.

A third option, specific to Python, is embedding the interpreter in-process (PyO3): no sockets and no
round trip, and PyTorch runs as usual. Its costs: the interpreter's global lock limits parallel handler
calls, the Python environment has to be packaged with the binary, and a crash in native Python code takes
angzarr-embedded down with it. The child-process bridge isolates that crash; PyO3 trades the isolation for
speed.

The CLI does the wiring:

- **It scaffolds handlers in the selected language,** the way `angzarr scaffold rust` does for Rust today,
  from the same protos and markers (`emits`, `refuses`, `fact`).
- **It builds the startup stack for angzarr-embedded:** the host binary or config that registers each
  remote handler, launches its child process, reads the handshake, and supervises it. An app mixing
  in-process Rust handlers and handlers in other languages starts with one command.
- **Python domains start through uv.** The startup stack runs each Python handler with `uv run --locked`
  against its `pyproject.toml` and `uv.lock`. uv fetches the pinned interpreter (a python-build-standalone
  build) and the locked dependencies into a project environment, so no system Python is assumed and
  developers get a working uv environment for the handler.

Until then, the Rust handler interface keeps the same shape as `CommandHandlerService`'s request and
response, so a remote adapter needs no retrofit.

First step: a spike that runs one Python policy doing a PyTorch inference as a child process over a
local socket. Confirm which transports each supported language's gRPC library accepts (a Unix socket
path, a named pipe, an already-open descriptor). Record the per-call cost, and what happens to
angzarr-embedded when the child crashes or runs out of memory. Measuring PyO3 alongside is optional, for
comparison only.

Settled by: a red-reviewed remote-handler adapter in angzarr-embedded that runs a handler written in
another language as a child process, survives that child dying, and passes the same tests as an
in-process handler.

## Set-based validation

*"Usernames are unique." "A player holds at most one active seat."*

The rule spans many streams, but an aggregate enforces rules within one stream only.

Decided approach: **process managers**, the primitives angzarr already has. A process manager is a
domain: it keeps the state the rule needs, sees the commands and facts that bear on it, and refuses or
compensates a claim that breaks it. It needs no new mechanism.

**Reservation domains are a possible future option.** A domain whose streams are the constrained values
(for example, one stream per username), where a duplicate claim is refused. It is seen as added
complexity that the existing primitives already cover, so it is not planned.

**Dynamic Consistency Boundaries are not pursued at this time.** DCB (Sara Pellegrini and others) checks
a write's consistency with a query over tagged events after a position in one globally ordered log.
angzarr has no global position and orders per stream only, so DCB cannot be built on it.

Settled by: a guide page and an example of a process manager enforcing a uniqueness rule.

## Outbound side effects

*Sending an email, calling a payment API, publishing to a partner.*

Facts bring the outside world in. Nothing yet defines how events go out. Today a projector or a policy
would do it ad hoc, with no stated delivery guarantee and no stated retry or deduplication behaviour.
Other frameworks call this a gateway, a connector, or an integration event handler.

Expected shape: assembled from a projector and the outbox, with the external call keyed by the event's id
so a retry stays idempotent. The external system's answer comes back in as a fact.

Settled by: a guide page and one example that sends and retries an external call without sending it twice,
plus a decision on whether this needs a named component.

## Forgetting personal data (third)

*A GDPR erasure request.*

Event stores are append-only, and deleting an edition doesn't cover this: erasure targets one person's
data across every stream they appear in.

Decided technique: **crypto-shredding.** Personal fields are encrypted with a key per data subject, and
destroying the key forgets them everywhere at once, without rewriting any stream.

Decided shape:

- **An annotation marks personal data.** A field option on the proto, for example
  `(angzarr.personal) = { subject: "player_id" }`, marks the field as personal and names the field that
  identifies the data subject (when the subject is the aggregate itself, the stream's root).
- **The code generator emits a field map, not crypto.** At build time it emits a static table: which fields
  of which messages are personal, under which subject.
- **Shared Rust code in angzarr-core does the encryption,** at the store boundary. It encrypts personal
  fields on the way into the store (events and snapshots) and decrypts them on the way out. Handlers,
  policies and projectors in every language see plaintext and never hold a key, including handlers in
  other processes. There is one crypto implementation and one key store.

Open questions for the design:

- **Ciphertext doesn't fit the field's type** (an encrypted `string` isn't a string). The likely answer is
  an envelope on the stored page: the field is cleared in the payload, and its ciphertext is kept
  alongside, keyed by field number.
- **The erased-field marker.** After shredding, a read gets the field's default value plus a marker that it
  was erased, so upcasters and projectors can tell "erased" from "never set".
- **Plaintext copies.** Projections and the outbox hold decrypted data; erasure must purge or rebuild them
  (the `Purge` port and resume by position give a path).
- **Searching by a personal field** (an email lookup) needs a separate, non-reversible index.

This isn't needed for the proof of concept, but it is hard to retrofit onto data that is already stored,
so it should land before real personal data does.

Settled by: a red-reviewed implementation in angzarr-core with the annotation, the generated field map,
the envelope, and a store-suite check that a shredded subject's fields read back as erased once the key is
destroyed.

## A JSONL event store for low-frequency work

*A task log, a config history, a tool that writes a few events a day.*

Owner's idea, 2026-10-29: event streams are append-only, so a store that appends one JSON line per event to a
plain file fits low-frequency work, with no database to install, a format people can read and grep, and files that
diff and merge in git. taskloom's existing JSONL task log is the precedent.

Not decided. It would be one more adapter held to angzarr-ports' store contract, so the questions are the contract's:

- **Layout:** one file per stream fits per-stream ordering (no global position, 14.35); one file per domain or
  project needs a stream key on every line and a scan to read one stream.
- **Atomicity:** the store's single `write` covers events, outbox and positions together. A line append is atomic
  only up to the filesystem's guarantees, so a crash mid-write needs a defined recovery (truncate a torn last line).
- **Concurrency:** two processes appending to one stream need a lock or an expected-sequence check on append.
- **Snapshots, positions, the outbox and `Watch`:** each needs a file-backed form, or the adapter documents which it
  lacks.
- **Merging in git:** a `merge=union` JSONL file reorders lines; sequence numbers per stream make that recoverable,
  where wall-clock order was not (the Go taskloom's known limit).

Settled by: a decision on layout and atomicity, then an adapter that passes the angzarr-ports store suite.

## Already covered

Not gaps, listed so they aren't rediscovered as missing:

- **Snapshots:** separate from the event write, in the storage contract.
- **Upcasters:** event and command upcasting, in the router.
- **Outbox:** written atomically with events in the store's single `write`.
- **Inbox:** deduplication on arrival, by command or fact id.
- **Read-your-writes:** a call can wait for the system to settle.
- **Catch-up subscriptions:** the `Watch` port.
- **Projection rebuilds:** `Purge` and resume by position.
- **Compensation:** the refusal path, as described above.
