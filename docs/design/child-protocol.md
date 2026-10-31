# The child-process launch protocol (v1)

**Status:** normative, decision 14.59 (2026-10-31). Scenarios:
[`parity/client/child.feature`](../../parity/client/child.feature)
(C-0749 to C-0756). Reason key: `HOST_REASON_HANDSHAKE_MALFORMED`
(`proto/io/angzarr/v1/reasons.proto`).

A **host** (angzarr-embedded, or any runtime that runs a business process
written in another language) launches the business process as a **child**
process and talks to it over gRPC on a Unix socket. This page is the whole
launch contract: a client library that provides a child shim (client-python's
`angzarr_client.child.run_child`) implements the child's side, and a host
the host's side. Everything served over the socket is ordinary angzarr gRPC
(`ComponentService`, the kind's service, `grpc.health.v1`), specified
elsewhere; this page covers only how the two find each other, and how the
child ends.

The key words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119.

## 1. The socket: `ANGZARR_SOCKET`

- The host chooses the socket path and passes it to the child in the
  environment variable `ANGZARR_SOCKET`. The path is absolute, and at most
  107 bytes long (a Unix socket address's `sun_path`, less its NUL); a host
  refuses a socket directory too long to hold the names it gives.
- Before launching, the host removes any file already at that path (a stale
  socket from an earlier child).
- The child MUST listen on exactly that path, and MUST name it in its
  handshake (section 2). A child launched with `ANGZARR_SOCKET` unset MAY
  choose a path of its own, and names that one.
- The host connects to the path the handshake names.

## 2. The handshake line

Once it is ready (section 4), the child writes one line on its stdout:

```text
angzarr-handshake v1 unix:/absolute/path/to/the.sock
```

Its grammar (ABNF, RFC 5234), after the line ending (LF, or CR LF) is
removed:

```abnf
handshake  = "angzarr-handshake" SP version SP address
version    = %s"v1"
address    = %s"unix:" path
path       = "/" *path-char        ; the rest of the line, absolute
path-char  = %x00-09 / %x0B-FF      ; any octet but LF
```

Every match is case-sensitive. The path is everything after `unix:` to the
end of the line, spaces included. `v1` is the line's format version; a
later format changes it.

A reader (a host reading a child's stdout, or a client's handshake parser)
classifies each line by its **first word**, the characters before its first
space (the whole line when it has none):

1. **Not a handshake**: the first word is not exactly `angzarr-handshake`.
   An empty line, a library's banner, or `angzarr-handshaker v1 unix:/a` (a
   longer first word) is not a handshake. A host skips such a line.
2. **A handshake**: the first word is `angzarr-handshake` and the line
   matches `handshake`. The host connects to its path.
3. **Malformed**: the first word is `angzarr-handshake` and the line does
   not match `handshake`: another version (`v2`), another transport
   (`tcp:...`), a relative path, a missing address, or two spaces where one
   belongs. It is refused, never skipped, under
   `HOST_REASON_HANDSHAKE_MALFORMED` (INTERNAL; args `line`, the line as
   read with its line ending removed). A host that reads one fails to start
   the child, and stops it (section 5).

Only `unix:` is defined. Named pipes and an inherited descriptor
(FUTURE.md) would be new address forms, and a new format version.

## 3. Stdout and stderr

- **Before the handshake**, the child SHOULD write nothing on stdout. It MAY
  write lines that are not handshakes (rule 1 above: a banner a library
  prints on import, say); the host skips them. It MUST NOT write a line whose
  first word is `angzarr-handshake` other than its one handshake.
- **The handshake is the only protocol on stdout.** The child writes it
  once. After it, the host never parses the child's stdout: it drains it, so
  the child never blocks on a full pipe, and passes it on to its own stderr.
  The child MAY go on writing there (a stray `print`), or close its stdout;
  either is its own output, never protocol, and a later line whose first
  word is `angzarr-handshake` means nothing.
- **Stderr** is the child's log. The host passes it through (inherits it).
- A child that exits before writing its handshake failed to start; its
  stderr says why.

## 4. Readiness before the handshake

The child MUST serve `grpc.health.v1.Health` on the socket, and MUST write
its handshake only once the overall server (service `""`) reports
`SERVING` there: listening, its component's services registered, and its
readiness probes passing. So the host may call `ComponentService.Describe`
the moment it has read the line, and a health check it sends at once
answers `SERVING`. After the handshake, health reports the child's
readiness as anywhere else: `NOT_SERVING` once shutdown begins.

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
- The host removes the socket file the handshake named once the child has
  ended, however it ended, so a child that crashed or was killed leaves no
  file behind; and the path it chose, before every launch (section 1) and
  when a launch fails.

## 7. Not specified here

- How the host reports a handshake that never arrives (its time limit) or a
  child whose stdout closes first: the host's own failures, with no spec
  key yet.
- Which command launches a child of a given language, and how a host
  restarts one: the host's configuration and supervision.
- What the host does with health after the handshake (watching it for
  every child) and a language-neutral conformance probe a new client can
  run against its child: S4's host-side half, still to come.
