Feature: Component discovery - the coordinator asks the business process what it is
  One coordinator serves one business process, and a business process is
  one component: one aggregate, saga, process manager or projector. The
  coordinator learns which component by asking the business process, over
  the same connection it uses to deliver work. The answer describes the
  component: its name, its kind, the domains it reacts to, its state type
  and its build version. The component is registered while the coordinator
  holds its description from the latest answer.

  The coordinator asks when it first connects and again every time the
  connection comes back up. It delivers nothing while it holds no
  description, and it reports itself ready only once it holds one.

  Background:
    Given an "order" business binary built as version "1.4.2+build.7" hosting the "order" aggregate

  @discovery
  @C-0561
  Scenario: The coordinator is ready only after the business process has described itself
    Given a coordinator that has not yet connected to the "order" business binary
    Then the coordinator reports itself not ready
    When the coordinator connects to the "order" business binary
    Then the coordinator asks it to describe its component
    And the "order" aggregate is registered at rules version "1.4.2+build.7"
    And the coordinator reports itself ready

  @discovery
  @C-0562
  Scenario Outline: Nothing reaches the component before the coordinator holds its description
    Given a coordinator whose request to describe the "order" business binary has not yet been answered
    When <work> arrives for the "order" aggregate
    Then business code is not invoked
    And <consequence>

    Examples:
      | work                                | consequence                                               |
      | a command from a caller who waits   | the caller is answered with UNAVAILABLE status            |
      | a fact from a caller who waits      | the caller is answered with UNAVAILABLE status            |
      | a command sent without waiting      | the command stays queued until the aggregate is registered |
      | a saga's command                    | the command stays queued until the aggregate is registered |

  @discovery
  @C-0563
  Scenario: A reconnected business process is described again before it gets more work
    Given the "order" aggregate is registered at rules version "1.4.2+build.7"
    And the "order" business binary restarts as version "1.5.0+build.9"
    When the coordinator's connection to the "order" business binary comes back up
    Then the coordinator asks it to describe its component again
    And the "order" aggregate is registered at rules version "1.5.0+build.9"
    And the next AddItem command is delivered only after that answer

  @discovery
  @C-0564
  Scenario: A business process that describes a component without a version is never delivered to
    Given an "order" business binary built without a version
    When the coordinator connects to the "order" business binary
    Then the "order" aggregate is not registered
    And the coordinator reports itself not ready
    And the coordinator logs an error naming the business process and the "order" aggregate
    And an alert is raised
    And no command for the "order" aggregate reaches business code

  @discovery
  @C-0566
  Scenario: A failing describe request is logged every time and alerted only after the grace period
    Given the coordinator's describe alert grace period is 2 minutes
    And the "order" business binary does not answer requests to describe its component
    When the coordinator has been trying to connect for 1 minute
    Then the coordinator has logged an error for every failed request
    And the coordinator reports itself not ready
    And no alert has been raised
    When the coordinator has been trying to connect for 3 minutes
    Then an alert is raised

  @discovery
  @C-0567
  Scenario: The describe alert grace period defaults to 2 minutes
    Given a coordinator configured without a describe alert grace period
    Then its describe alert grace period is 2 minutes

