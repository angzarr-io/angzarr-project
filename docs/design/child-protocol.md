# The child-process launch protocol (v1)

**Status:** normative, decisions 14.59 (2026-10-31), 14.62 and 14.63
(2026-11-01), as amended by 14.80 (DRAFT, 2026-11-02: no handshake line).
Scenarios:
[`parity/client/child.feature`](../../parity/client/child.feature), run by
every child shim, and
[`parity/host/supervision.feature`](../../parity/host/supervision.feature)
(C-0763 to C-0768), run by every host; the handshake scenarios of
`child.feature` are falsified by 14.80 and wait on its review. Reason keys:
EmbeddedReason's `EMBEDDED_REASON_CHILD_*` and `EMBEDDED_REASON_PROBE_INPUT`, the
local-process transport's
(`proto/io/angzarr/transport/embedded/v1/reasons.proto`, English in
`reasons.en-US.ftl` beside it; section 7; decision 14.64). The protocol's
constants (`ANGZARR_SOCKET` and the 103-byte path limit) are declared once,
as the `(child_protocol)` option of
`proto/io/angzarr/transport/embedded/v1/child_protocol.proto`.

A **host** (angzarr-embedded, or any runtime that runs a business process
written in another language) launches the business process as a **child**
process and talks to it over gRPC on a Unix socket. This page is the whole
launch contract: a client library that provides a child shim (client-python's
`angzarr_client.child.run_child`) implements the child's side, and a host
the host's side. Everything served over the socket is ordinary angzarr gRPC
(`ComponentService`, the kind's service, `grpc.health.v1`), specified
elsewhere; this page covers only how the host finds the child ready, and
how the child ends.

The key words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119.

## 1. The socket: `ANGZARR_SOCKET`

- The host chooses the socket path and passes it to the child in the
  environment variable `ANGZARR_SOCKET`. The path is absolute, UTF-8, and
  at most 103 bytes long: the portable minimum of a Unix socket address's
  `sun_path`, less its NUL. macOS and the BSDs give `sun_path` 104 bytes
  (103 usable), Linux 108 (107 usable), so 103 is the longest path every
  platform a host or child may run on accepts (decision 14.108, DRAFT); a
  host refuses a socket directory too long to hold the names it
  gives.
- Before launching, the host removes any file already at that path (a stale
  socket from an earlier child).
- The child MUST listen on exactly that path. The host chose it, so the
  child names it back nowhere (decision 14.80). A child launched with
  `ANGZARR_SOCKET` unset, or set to a path that is not UTF-8, MUST NOT
  serve: it exits with a status other than 0 (it fails to start, section
  3).
- The host connects to the path it chose.

## 2. Readiness: health SERVING on the host's path

There is no handshake line (decision 14.80; the owner's ruling F1 of
2026-11-02). The child MUST serve `grpc.health.v1.Health` on the socket,
and its overall server (service `""`) reports `SERVING` there once it is
ready: listening, its component's services registered, and its readiness
probes passing. The host connects to the path it chose and sends
`Health/Check` for service `""` until it answers `SERVING`, within its time
limit for a start; the moment it does, the host may call
`ComponentService.Describe`. A path with no listener yet, or a check that
answers otherwise, is not yet ready, and the host checks again. After
that, health reports the child's readiness as anywhere else:
`NOT_SERVING` once shutdown begins.

## 3. Stdout and stderr

- **Stdout carries no protocol.** The host never parses it: it drains it,
  so the child never blocks on a full pipe, and passes it on to its own
  stderr. Whatever the child writes there is its own output.
- **Stderr** is the child's log. The host passes it through (inherits it).
- A child that exits before its health reports `SERVING` failed to start;
  its stderr says why.

## 4. (Merged into section 2.)

## 5. Shutdown

- The host writes nothing on the child's stdin, and holds it open while the
  child is to run. A child reads and discards anything it is given there.
- The child MUST shut down when its stdin reaches end of file (the host
  closed it, or exited) and when it receives SIGTERM. It MAY also shut down
  on SIGINT. Shutting down, it reports `NOT_SERVING`, refuses new calls,
  lets the calls in flight finish within its grace, removes its socket file
  (section 6), and exits with status 0.
- A host stops a child in three steps: it closes the child's stdin and
  waits a grace for it to exit; then it sends SIGTERM and waits a second
  grace; then it kills it (SIGKILL).

## 6. Socket cleanup

- The child MUST remove its socket file when it shuts down (section 5).
- The host removes the socket file at the path it chose once the child has
  ended, however it ended, so a child that crashed or was killed leaves no
  file behind; and before every launch (section 1) and when a launch
  fails.

## 7. The host's failures with a child

A host that launches a child, and a conformance probe that takes one
child through this protocol a step at a time (angzarr-embedded's
`angzarr_embedded_host::probe`, the cli's `angzarr probe`), refuse a child
that breaks it under EmbeddedReason's keys (decision 14.62). `component` is
the child's name in the host's configuration.

| Key | Status | Args | When |
|---|---|---|---|
| `EMBEDDED_REASON_CHILD_NOT_SERVING` | INTERNAL | `component`, `status`, `timeout_ms` | its overall server did not report SERVING on the host's path within the host's time limit for a start (`timeout_ms`), or it exited first (section 2); `status` the last health status it answered, by its name, or its number when it has none, or `none` when no check was answered |
| `EMBEDDED_REASON_CHILD_EXIT_STATUS` | INTERNAL | `component`, `exit_code` | it exited on its stdin's end with a status other than 0 (section 5) |
| `EMBEDDED_REASON_CHILD_NOT_EXITED` | INTERNAL | `component`, `ended` | it did not exit by itself on its stdin's end within its grace (section 5); `ended` how it did: `signalled`, `terminated`, `killed` or `not-running` |
| `EMBEDDED_REASON_PROBE_INPUT` | INVALID_ARGUMENT | `component`, `kind` | a probe given an input a child of its kind (`domain`, `policy`, `projector`) does not handle; nothing is sent |

The first fails a host's start of the child, which then stops it
(section 5). The two shutdown keys are a probe's: a host stopping its
children reports how each ended rather than refusing one. A host's other
failures (a launch command that cannot start, a socket it cannot connect
to) are its own, under codes of its own.

## 8. Supervision

Once a child has reported SERVING (section 2), its host supervises it
(decision 14.63):

- **The check.** Every check interval, the host sends the child a
  `grpc.health.v1.Health/Check` for the overall server (service `""`),
  with a deadline. A host MAY also watch the child's health
  (`Health/Watch`); the periodic check is what finds a child that is
  wedged, its watch still reporting SERVING while it answers nothing.
- **Healthy, unhealthy.** A child is unhealthy from the first moment its
  health is seen other than SERVING, by a check answering otherwise, a
  check failing or passing its deadline unanswered, or its watch
  reporting otherwise or ending; and healthy again once a check or its
  watch reports SERVING. While it is unhealthy, the host sends it no new
  call: a call to it fails retryably, as a call to a child that is not
  running does (`ANGZARR_REASON_HANDLER_UNAVAILABLE`).
- **The grace, and a restart.** A child unhealthy for its whole grace,
  unbroken, is restarted: the host stops it (section 5), launches a new
  child, and waits for it to report SERVING and describes it as it did the
  first.
  The host judges the grace when it sees the child's health, so the
  restart comes at the first check, or watch report, at or after the
  grace's end.
- **The restart limit.** A host restarts a component's child for its
  health at most its restart limit of times. Past the limit the host
  stops the child once its grace has passed again and starts no other:
  the component stays down, and every call to it fails retryably, until
  the host itself is restarted.
- **The reset window.** The count of a component's restarts clears once
  its child has been healthy for the whole reset window, unbroken: a child
  that wedges only now and then is never given up for restarts long past
  (decision 14.67). The host judges the window when it sees the child's
  health, as it judges the grace; a child seen unhealthy within it starts
  it over the next time it is healthy.
- **In flight.** A call in flight on a child the host stops fails
  retryably; the host never sends it again by itself, to that child or the
  next. Whether it is retried is its caller's to decide.

The interval, the deadline, the grace, the limit and the reset window are
the host's configuration (angzarr-embedded: `angzarr.yaml`'s `supervision`,
the window `unhealthy_reset_ms`, 10 minutes by default). A child
that exits by itself is the host's to restart as it chooses
(angzarr-embedded: at once, then with a backoff while restarts fail); its
restarts are not counted against the restart limit.

## 9. Not specified here

- Which command launches a child of a given language: the host's
  configuration.

## 10. The constants' declaration

The protocol's declared constants (decision 14.64) are the words both
sides of the protocol must spell alike: `ANGZARR_SOCKET` (section 1) and
the 103-byte socket path limit (section 1). They are stated once, as the
`(child_protocol)` file option of
`proto/io/angzarr/transport/embedded/v1/child_protocol.proto`, for every
language's code generator to read, as each reads the
`(io.angzarr.v1.reason)` args.

Why a file option: proto3 has no constants, an enum value holds a number
and never a string, and the spec states no constant any other way. A
custom option is the spec's existing idiom for data a generator reads off
the descriptor (options.proto's `(component)`, `(state)` and `(conflict)`,
reasons.proto's `(reason)`), so the constants are a typed message set as
that file's option, read the same way, and nothing else on the wire.
