Feature: Child supervision - how a host keeps its children healthy
  A host (angzarr-embedded) supervises every child it launches once the
  child's health reports SERVING on the socket path the host chose
  (docs/design/child-protocol.md, sections 2 and 8; decisions 14.63 and
  14.80: there is no handshake line): it sends the child a grpc.health.v1 Check for the overall server
  every check interval, with a deadline; a child unhealthy (a check not
  answered SERVING within its deadline, or its watch reporting other than
  SERVING) is sent no new call, and one unhealthy for its whole grace is
  restarted, up to the host's restart limit, past which it stays down.

  Every host runs these scenarios against its own supervisor, with the
  host's clock in the test's hands: "the check interval passes" and "the
  grace passes" advance it, never wait for it. A child that hangs is a test
  child that blocks on purpose.

  Fixtures use the generic client-tier vocabulary: an "order" aggregate
  component, its check interval 1000 ms, its deadline 100 ms, its grace
  1500 ms.

  @C-0763
  Scenario: A host checks a healthy child's health every check interval
    Given a host supervising a child serving an aggregate component for domain "order"
    When the check interval passes
    Then the host has sent the child a gRPC health Check for the overall server
    And a command for domain "order" is answered by the same child

  @C-0764
  Scenario: A wedged child, its health watch still SERVING, is restarted once its grace has passed
    Given a host supervising a child serving an aggregate component for domain "order"
    And the child answers no health Check, its health watch still reporting SERVING
    When the check interval passes and its Check's deadline passes
    Then a command for domain "order" fails retryably without reaching the child
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another
    And a command for domain "order" is answered by the new child

  @C-0765
  Scenario: A child reporting NOT_SERVING past its grace is restarted
    Given a host supervising a child serving an aggregate component for domain "order"
    And the child's health reports NOT_SERVING
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another

  @C-0766
  Scenario: A child healthy again within its grace is not restarted
    Given a host supervising a child serving an aggregate component for domain "order"
    And the child answers no health Check, its health watch still reporting SERVING
    When the check interval passes and its Check's deadline passes
    And the child answers its health Check SERVING again
    And the grace passes, a check at a time
    Then a command for domain "order" is answered by the same child

  @C-0767
  Scenario: A child restarted as often as the restart limit stays down
    Given a host supervising a child serving an aggregate component for domain "order", its restart limit 1
    And every child of it answers no health Check
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another
    When the grace passes, a check at a time
    Then the host has stopped the child and launched none
    And a command for domain "order" fails retryably

  @C-0769
  Scenario: A child healthy for the whole reset window clears its component's restart count
    Given a host supervising a child serving an aggregate component for domain "order", its restart limit 1
    And every child of it answers no health Check
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another
    When the new child answers every health Check SERVING for the whole reset window, a check at a time
    And it answers no health Check again, and the grace passes, a check at a time
    Then the host has stopped the child and launched another

  @C-0770
  Scenario: A child unhealthy within the reset window keeps its component's restart count
    Given a host supervising a child serving an aggregate component for domain "order", its restart limit 1
    And every child of it answers no health Check
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another
    When the new child answers SERVING for less than the reset window, then no health Check, and the grace passes, a check at a time
    Then the host has stopped the child and launched none

  @C-0768
  Scenario: A command in flight on a child the host restarts fails retryably and is not sent again
    Given a host supervising a child serving an aggregate component for domain "order"
    And a command for domain "order" in flight that the child never answers
    And the child answers no health Check, its health watch still reporting SERVING
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another
    And the command in flight has failed retryably
    And no child has been sent the command a second time

  @C-0869
  Scenario Outline: A child not SERVING on the host's path within the start limit fails its start
    # Readiness is health SERVING on the path the host chose, within the
    # host's time limit for a start (decision 14.80); the fixture's start
    # limit is 5000 ms.
    Given a host starting a child serving an aggregate component for domain "order"
    And the child <behaviour>
    When the start limit passes, a check at a time
    Then the host fails the start with reason EMBEDDED_REASON_CHILD_NOT_SERVING
    And the failure's args are component "order", status "<status>" and timeout_ms "5000"
    And the host has stopped the child and removed the socket file at the path it chose

    Examples:
      | behaviour                                     | status      |
      | answers every health Check NOT_SERVING        | NOT_SERVING |
      | never listens on the path                     | none        |

  @C-0870
  Scenario: A child that exits before it reports SERVING fails its start
    Given a host starting a child serving an aggregate component for domain "order"
    And the child exits with status 3 before any health Check is answered
    When the host starts the child
    Then the host fails the start with reason EMBEDDED_REASON_CHILD_NOT_SERVING
    And the failure's args are component "order", status "none" and timeout_ms "5000"
