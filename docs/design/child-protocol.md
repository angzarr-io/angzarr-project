# The child-process launch protocol (v1)

**Status:** normative, decisions 14.59 (2026-10-31) and 14.62
(2026-11-01). Scenarios:
[`parity/client/child.feature`](../../parity/client/child.feature)
(C-0749 to C-0756, C-0759 to C-0762). Reason keys: HostReason's
`HOST_REASON_HANDSHAKE_*`, `HOST_REASON_CHILD_*` and
`HOST_REASON_PROBE_INPUT` (`proto/io/angzarr/v1/reasons.proto`; section
7).

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
  environment variable `ANGZARR_SOCKET`. The path is absolute, UTF-8, and
  at most 107 bytes long (a Unix socket address's `sun_path`, less its
  NUL); a host refuses a socket directory too long to hold the names it
  gives.
- Before launching, the host removes any file already at that path (a stale
  socket from an earlier child).
- The child MUST listen on exactly that path, and MUST name it in its
  handshake (section 2). A child launched with `ANGZARR_SOCKET` unset MAY
  choose a path of its own, UTF-8 too, and names that one. A child given
  an `ANGZARR_SOCKET` that is not UTF-8 MUST NOT serve there: it writes no
  handshake and exits with a status other than 0 (it fails to start,
  section 3), since no handshake could name the path.
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
path-char  = %x00-09 / %x0B-7F / UTF8-2 / UTF8-3 / UTF8-4
                                   ; any UTF-8 character but LF
; UTF-8 (RFC 3629, section 4):
UTF8-2     = %xC2-DF UTF8-tail
UTF8-3     = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
             %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
UTF8-4     = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
             %xF4 %x80-8F 2( UTF8-tail )
UTF8-tail  = %x80-BF
```

Every match is case-sensitive, and made on the line's bytes. The path is
everything after `unix:` to the end of the line, spaces included, and is
UTF-8: a socket path that is not names no file any reader can hold as
text, so a v1 handshake whose path is not UTF-8 does not match `handshake`
and is malformed (rule 3 below). Only the path is held to UTF-8: what
precedes it is ASCII by the grammar, and a line that is not a handshake
is never decoded. `v1` is the line's format version; a later format
changes it.

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
   (`tcp:...`), a relative path, a path that is not UTF-8, a missing
   address, or two spaces where one belongs. It is refused, never skipped,
   under `HOST_REASON_HANDSHAKE_MALFORMED` (INTERNAL; args `line`, the
   line as read with its line ending removed). A host that reads one fails
   to start the child, and stops it (section 5).

`line` is text. A line that is UTF-8 is given as it is; one that is not is
given with each of its bytes outside printable ASCII (%x20-7E), and each
backslash, written `\xhh`, two lowercase hexadecimal digits, so no byte
of it is lost and none is decoded into another character:
`angzarr-handshake v1 unix:/run/caf\xe9.sock` for a path holding the
Latin-1 byte E9.

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

## 7. The host's failures with a child

A host that launches a child, and a conformance probe that takes one
child through this protocol a step at a time (angzarr-embedded's
`angzarr_embedded_host::probe`, the cli's `angzarr probe`), refuse a child
that breaks it under HostReason's keys (decision 14.62). `component` is
the child's name in the host's configuration.

| Key | Status | Args | When |
|---|---|---|---|
| `HOST_REASON_HANDSHAKE_MALFORMED` | INTERNAL | `line` | a malformed line (section 2, rule 3) |
| `HOST_REASON_HANDSHAKE_TIMEOUT` | INTERNAL | `timeout_ms` | no handshake within the host's time limit, in milliseconds |
| `HOST_REASON_HANDSHAKE_CLOSED` | INTERNAL | none | the child's stdout ended before a handshake: it exited, or closed it (section 3) |
| `HOST_REASON_CHILD_NOT_SERVING` | INTERNAL | `component`, `status` | its overall server reported other than SERVING once it had handshaken (section 4); `status` the health status's name, or its number when it has none |
| `HOST_REASON_CHILD_EXIT_STATUS` | INTERNAL | `component`, `exit_code` | it exited on its stdin's end with a status other than 0 (section 5) |
| `HOST_REASON_CHILD_NOT_EXITED` | INTERNAL | `component`, `ended` | it did not exit by itself on its stdin's end within its grace (section 5); `ended` how it did: `signalled`, `terminated`, `killed` or `not-running` |
| `HOST_REASON_PROBE_INPUT` | INVALID_ARGUMENT | `component`, `kind` | a probe given an input a child of its kind (`domain`, `policy`, `projector`) does not handle; nothing is sent |

The first four fail a host's start of the child, which then stops it
(section 5). The two shutdown keys are a probe's: a host stopping its
children reports how each ended rather than refusing one. A host's other
failures (a launch command that cannot start, a socket it cannot connect
to) are its own, under codes of its own.

## 8. Not specified here

- Which command launches a child of a given language, and how a host
  restarts one: the host's configuration and supervision.
- What the host does with health after the handshake (watching it for
  every child): S4's host-side half, still to come.
