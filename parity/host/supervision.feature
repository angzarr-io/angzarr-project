Feature: Child supervision - how a host keeps its children healthy
  A host (angzarr-embedded) supervises every child it launches once the
  child has handshaken (docs/design/child-protocol.md, section 8; decision
  14.63): it sends the child a grpc.health.v1 Check for the overall server
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

  @C-0768
  Scenario: A command in flight on a child the host restarts fails retryably and is not sent again
    Given a host supervising a child serving an aggregate component for domain "order"
    And a command for domain "order" in flight that the child never answers
    And the child answers no health Check, its health watch still reporting SERVING
    When the grace passes, a check at a time
    Then the host has stopped the child and launched another
    And the command in flight has failed retryably
    And no child has been sent the command a second time
