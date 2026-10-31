Feature: Component host - serving its registered component over gRPC
  Every client provides a reusable, fully generic gRPC component host. An
  application registers its one component (generated component code bound
  to the angzarr-router binding; one business process is one component)
  and, optionally, its own extra gRPC services;
  the host serves them next to the gRPC health service, which doubles as
  the readiness signal the coordinator sidecar and Kubernetes probes use.

  The host knows framework concepts only. It contains no example or
  business-specific types or services; everything domain-specific is
  registered by the application. Dispatch inside a component is the
  router's and is specified by angzarr-router's conformance suite, not here.

  Fixtures use the generic client-tier vocabulary: an "order" aggregate
  component.

  @C-0497
  Scenario: The host serves a registered component's framework service
    Given a component host with an aggregate component for domain "order" registered
    When the host starts on a TCP port
    Then CommandHandlerService is served on that port
    And a ContextualCommand for domain "order" sent to CommandHandlerService.Handle reaches the order component

  @C-0499
  Scenario Outline: The host takes its transport from the environment
    Given the transport environment selects <transport> at "<address>"
    And a component host with an aggregate component for domain "order" registered
    When the host starts
    Then the host listens on <transport> at "<address>"

    Examples:
      | transport   | address                     |
      | TCP         | 127.0.0.1:0                 |
      | Unix socket | /tmp/angzarr-host-test.sock |

  @C-0500
  Scenario: The host reports SERVING only once it serves its component
    Given a component host with an aggregate component for domain "order" registered
    When the host starts on a TCP port
    Then the overall server's health status is SERVING only after the component's service is listening
    And the gRPC health service reports SERVING for CommandHandlerService

  @C-0501
  Scenario: The host reports NOT_SERVING once shutdown begins
    Given a started component host with an aggregate component for domain "order" registered
    When shutdown begins
    Then the gRPC health service reports NOT_SERVING for the overall server
    And in-flight calls complete before the server stops

  @C-0502
  Scenario: A Unix-socket host removes its socket file on shutdown
    Given the transport environment selects Unix socket at "/tmp/angzarr-host-test.sock"
    And a started component host with an aggregate component for domain "order" registered
    When the host shuts down
    Then "/tmp/angzarr-host-test.sock" no longer exists

  @C-0503
  Scenario: An application plugs its own gRPC service into the host
    Given a component host with an aggregate component for domain "order" registered
    And an application-defined gRPC service OrderReportService registered on the host
    When the host starts on a TCP port
    Then OrderReportService is served on that port alongside CommandHandlerService
    And the gRPC health service reports SERVING for OrderReportService

  @C-0504
  Scenario: A host with no registered component refuses to start
    # A client whose host API cannot represent a host with no component
    # (e.g. a Rust typestate builder, refused at compile time) satisfies
    # this scenario.
    Given a component host with no component registered
    When the host starts
    Then starting fails with a configuration error

  @C-0579
  Scenario: A host given a second component refuses to start
    # One business process is one component (decision 14.19). A client whose
    # host API cannot represent a second component (e.g. a Rust typestate
    # builder, refused at compile time) satisfies this scenario.
    Given a component host with an aggregate component for domain "order" registered
    And a second component, an aggregate for domain "payment", registered on the same host
    When the host starts
    Then starting fails with a configuration error naming both components
    And no service is served

  @C-0743
  Scenario: A host refuses a descriptor whose rules version is not the one its component reports
    # Decision 14.42, amended: a descriptor generated or written by hand is
    # checked alike; the coordinator would refuse every answer of a
    # component whose descriptor names another version.
    Given a component host whose aggregate component "Order" for domain "order" reports rules version "1.4.2"
    When the component is registered with a descriptor carrying rules version "1.4.1"
    Then the registration fails with reason HOST_REASON_DESCRIPTOR_RULES_VERSION_MISMATCH, component "Order", described "1.4.1" and reported "1.4.2"
    And no component is registered
