Feature: Child process - the launch protocol between a host and its child
  A host (angzarr-embedded) runs a business process written in another
  language as a child process, and talks to it over gRPC on a Unix socket.
  The launch contract is normative in docs/design/child-protocol.md
  (decisions 14.59 and 14.62): the host names the socket in ANGZARR_SOCKET; the child
  serves there and, once its gRPC health reports SERVING, writes one
  handshake line on stdout, "angzarr-handshake v1 unix:<absolute path>";
  it shuts down on stdin's end of file or SIGTERM and removes its socket.

  Every client that provides a child shim (client-python's run_child) runs
  the child scenarios against it, launched as a host launches it: stdin
  and stdout piped, stderr passed through, the socket named in the
  environment. The handshake-line scenarios hold for every reader of the
  line: a client's handshake parser and, the host's half, angzarr-embedded.

  Fixtures use the generic client-tier vocabulary: an "order" aggregate
  component.

  The socket path is UTF-8 (decision 14.62). In "the stdout line of bytes
  ...", "\xhh" is the byte hh, two hexadecimal digits, and every other
  character is itself, in UTF-8; a refused line that is not UTF-8 is given
  back with each byte outside printable ASCII, and each backslash, written
  "\xhh".

  @C-0749
  Scenario: A child serves at the socket its parent names and announces it
    Given a child serving an aggregate component for domain "order"
    And a parent that names a socket path in ANGZARR_SOCKET
    When the parent launches the child
    Then the first handshake line on the child's stdout names that socket path
    And ComponentService.Describe is served at that socket

  @C-0750
  Scenario: A child writes its handshake only once its gRPC health reports SERVING
    # The test holds the child's readiness (a client holds it its own way:
    # a readiness probe that does not pass yet), so the interleaving is
    # forced, never waited for.
    Given a child serving an aggregate component for domain "order", its readiness held
    And a parent that names a socket path in ANGZARR_SOCKET
    When the parent launches the child
    Then the gRPC health service at that socket reports NOT_SERVING for the overall server
    And the child has written no handshake line on stdout
    When the child's readiness is released
    Then the first handshake line on the child's stdout names that socket path
    And the gRPC health service at that socket reports SERVING for the overall server

  @C-0751
  Scenario: The handshake is the only handshake line a child writes
    # After the handshake the host only drains the child's stdout, onto
    # its own stderr; what the child writes there is its own output.
    Given a started child serving an aggregate component for domain "order"
    When a ContextualCommand for domain "order" is sent to CommandHandlerService.Handle at its socket
    And the parent closes the child's stdin
    Then no line on the child's stdout after its handshake is a handshake line

  @C-0752
  Scenario: Closing a child's stdin stops it and removes its socket
    Given a started child serving an aggregate component for domain "order"
    When the parent closes the child's stdin
    Then the child exits with status 0
    And the socket file the handshake named no longer exists

  @C-0753
  Scenario: SIGTERM stops a child and removes its socket
    Given a started child serving an aggregate component for domain "order"
    When the parent sends the child SIGTERM
    Then the child exits with status 0
    And the socket file the handshake named no longer exists

  @C-0754
  Scenario Outline: A handshake line names the socket the child serves
    When the stdout line "<line>" is read
    Then it is a handshake naming socket path "<path>"

    Examples:
      | line                                             | path                     |
      | angzarr-handshake v1 unix:/run/app/order.sock    | /run/app/order.sock      |
      | angzarr-handshake v1 unix:/run/my app/order.sock | /run/my app/order.sock   |

  @C-0755
  Scenario Outline: A line whose first word is not angzarr-handshake is not a handshake
    # A host skips it: a library's banner before the handshake, say.
    When the stdout line "<line>" is read
    Then it is not a handshake

    Examples:
      | line                                          |
      |                                               |
      | listening on /run/app/order.sock              |
      | angzarr-handshaker v1 unix:/run/app/order.sock |
      | Angzarr-handshake v1 unix:/run/app/order.sock |

  @C-0756
  Scenario Outline: A line that starts angzarr-handshake but is not a v1 handshake is refused
    # Refused, never skipped: a host that reads one fails to start the
    # child.
    When the stdout line "<line>" is read
    Then reading it fails with reason HOST_REASON_HANDSHAKE_MALFORMED and line "<line>"

    Examples:
      | line                                           |
      | angzarr-handshake                              |
      | angzarr-handshake v1                           |
      | angzarr-handshake v2 unix:/run/app/order.sock  |
      | angzarr-handshake v1 tcp:127.0.0.1:5000        |
      | angzarr-handshake v1 unix:order.sock           |
      | angzarr-handshake  v1 unix:/run/app/order.sock |
      | angzarr-handshake v1  unix:/run/app/order.sock |

  @C-0759
  Scenario Outline: A handshake names a socket path of any UTF-8 characters
    When the stdout line of bytes "<bytes>" is read
    Then it is a handshake naming socket path "<path>"

    Examples:
      | bytes                                                 | path                |
      | angzarr-handshake v1 unix:/run/caf\xc3\xa9/order.sock   | /run/café/order.sock |
      | angzarr-handshake v1 unix:/run/\xe2\x82\xac/order.sock | /run/€/order.sock    |

  @C-0760
  Scenario Outline: A handshake naming a socket path that is not UTF-8 is malformed
    # Refused, never skipped, as any other malformed line is; no reader
    # decodes the path into another one.
    When the stdout line of bytes "<bytes>" is read
    Then reading it fails with reason HOST_REASON_HANDSHAKE_MALFORMED and line "<line>"

    Examples:
      | bytes                                             | line                                              |
      | angzarr-handshake v1 unix:/run/caf\xe9/order.sock  | angzarr-handshake v1 unix:/run/caf\xe9/order.sock  |
      | angzarr-handshake v1 unix:/run/\xc3/order.sock     | angzarr-handshake v1 unix:/run/\xc3/order.sock     |
      | angzarr-handshake v1 unix:/run/\xed\xa0\x80.sock   | angzarr-handshake v1 unix:/run/\xed\xa0\x80.sock   |
      | angzarr-handshake v1 unix:/run/a\x5cb\x09\xff.sock | angzarr-handshake v1 unix:/run/a\x5cb\x09\xff.sock |

  @C-0761
  Scenario Outline: A line that is not UTF-8 is not a handshake when its first word is not angzarr-handshake
    # Only a handshake's path is decoded: a banner in another encoding
    # before the handshake is skipped, as any other such line is.
    When the stdout line of bytes "<bytes>" is read
    Then it is not a handshake

    Examples:
      | bytes                                         |
      | listening on /run/caf\xe9/order.sock          |
      | angzarr-handshake\xe9 v1 unix:/run/order.sock |
      | \xff                                          |

  @C-0762
  Scenario: A child given a socket path that is not UTF-8 fails to start
    # No handshake could name the path: the child writes none, and the
    # host's read of its stdout ends with HOST_REASON_HANDSHAKE_CLOSED.
    Given a child serving an aggregate component for domain "order"
    And a parent that names a socket path that is not UTF-8 in ANGZARR_SOCKET
    When the parent launches the child
    Then the child exits with a status other than 0
    And the child has written no handshake line on stdout
