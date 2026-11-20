Feature: Child process - the launch protocol between a host and its child
  A host (angzarr-embedded) runs a business process written in another
  language as a child process, and talks to it over gRPC on a Unix socket.
  The launch contract is normative in docs/design/child-protocol.md
  (decisions 14.59 and 14.62, as amended by 14.80: there is no handshake
  line): the host chooses the socket path and names it in ANGZARR_SOCKET
  (absolute, UTF-8, at most 103 bytes; decision 14.108); the child listens
  on exactly that path and names it back nowhere; it is ready once its
  grpc.health.v1 overall server (service "") reports SERVING there; its
  stdout carries no protocol; it shuts down on stdin's end of file or
  SIGTERM and removes its socket.

  Every client that provides a child shim (client-python's run_child) runs
  the child scenarios against it, launched as a host launches it: stdin
  and stdout piped, stderr passed through, the socket named in the
  environment. The host's half (a start that fails, under
  EMBEDDED_REASON_CHILD_NOT_SERVING) is parity/host/supervision.feature's.

  Fixtures use the generic client-tier vocabulary: an "order" aggregate
  component.

  @C-0749
  Scenario: A child serves at the socket its parent names
    Given a child serving an aggregate component for domain "order"
    And a parent that names a socket path in ANGZARR_SOCKET
    When the parent launches the child
    Then the gRPC health service at that socket reports SERVING for the overall server
    And ComponentService.Describe is served at that socket
    And the child serves at no other path

  @C-0750
  Scenario: A child reports SERVING only once it is ready
    # The test holds the child's readiness (a client holds it its own way:
    # a readiness probe that does not pass yet), so the interleaving is
    # forced, never waited for.
    Given a child serving an aggregate component for domain "order", its readiness held
    And a parent that names a socket path in ANGZARR_SOCKET
    When the parent launches the child
    Then the gRPC health service at that socket reports NOT_SERVING for the overall server
    When the child's readiness is released
    Then the gRPC health service at that socket reports SERVING for the overall server

  @C-0751
  Scenario: A child's stdout carries no protocol
    # The host only drains the child's stdout, onto its own stderr
    # (decision 14.80); the shim writes nothing there of its own.
    Given a started child serving an aggregate component for domain "order"
    When a HandleRequest for domain "order" is sent to CommandHandlerService.Handle at its socket
    And the parent closes the child's stdin
    Then the child shim has written nothing on the child's stdout

  @C-0752
  Scenario: Closing a child's stdin stops it and removes its socket
    Given a started child serving an aggregate component for domain "order"
    When the parent closes the child's stdin
    Then the child exits with status 0
    And the socket file at the path the parent named no longer exists

  @C-0753
  Scenario: SIGTERM stops a child and removes its socket
    Given a started child serving an aggregate component for domain "order"
    When the parent sends the child SIGTERM
    Then the child exits with status 0
    And the socket file at the path the parent named no longer exists

  # C-0754, C-0755, C-0756, C-0759, C-0760 and C-0761 (reading a stdout
  # handshake line: what names a socket, what is skipped, what is refused
  # as malformed, its UTF-8 path) are retired: there is
  # no handshake line, stdout carries no protocol, and the handshake keys
  # are gone (decision 14.80).

  @C-0762
  Scenario: A child given a socket path that is not UTF-8 fails to start
    Given a child serving an aggregate component for domain "order"
    And a parent that names a socket path that is not UTF-8 in ANGZARR_SOCKET
    When the parent launches the child
    Then the child exits with a status other than 0
    And nothing is served at that path

  @C-0868
  Scenario: A child launched with no socket path fails to start
    # It never picks a path of its own (decision 14.80).
    Given a child serving an aggregate component for domain "order"
    And a parent that leaves ANGZARR_SOCKET unset
    When the parent launches the child
    Then the child exits with a status other than 0
    And the child serves at no path
