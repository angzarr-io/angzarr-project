Feature: Rules version - recording who decided, and choosing snapshots
  Every business binary has a full version, fixed when it is built (for
  example "1.4.2+build.7"). It tells its coordinator that version when it
  registers, together with its state type, and reports the same version with
  every answer. The coordinator records that version, unaltered, on every
  event and snapshot the answer produced, so each event names the build that
  decided it.

  The coordinator alone decides whether a stored snapshot may be used. It
  offers a snapshot only when the snapshot's state type is the registered
  state type and its version passes the domain's compatibility rule against
  the registered version. By default, versions are compatible when their
  major and minor numbers are equal; a version that is not a semantic
  version is compatible only with exactly the same version. A domain may
  replace that rule with an accept pattern and an optional reject pattern;
  a reject match always wins, and a pattern must match the whole version.
  A snapshot that is not offered costs nothing but time: business code gets
  the full history from sequence 0 instead.

  Background:
    Given an "order" aggregate registered with state type "/orders.v1.OrderState" and rules version "1.4.2+build.7"

  # ===========================================================================
  # Recording the version
  # ===========================================================================

  @rules_version
  @C-0518
  Scenario: Every event of an answer records the reported version in full
    When business code answers an AddItem command with ItemAdded and ShippingQuoted events, reporting rules version "1.4.2+build.7"
    Then the ItemAdded event records rules version "1.4.2+build.7"
    And the ShippingQuoted event records rules version "1.4.2+build.7"

  @rules_version
  @C-0519
  Scenario: A snapshot returned with an answer records the reported version in full
    When business code answers an AddItem command with an ItemAdded event and a snapshot, reporting rules version "1.4.2+build.7"
    Then the snapshot records rules version "1.4.2+build.7"
    And the snapshot records state type "/orders.v1.OrderState"

  @rules_version
  @C-0520
  Scenario: During a rolling deployment each event names the build that decided it
    Given two instances of the "order" business binary, at rules versions "1.4.2+build.7" and "1.5.0+build.9"
    When the instance at "1.4.2+build.7" decides an AddItem command for order "order-1"
    And the instance at "1.5.0+build.9" decides an AddItem command for order "order-1"
    Then the first ItemAdded event records rules version "1.4.2+build.7"
    And the second ItemAdded event records rules version "1.5.0+build.9"

  @rules_version
  @C-0521
  Scenario: A process manager's own events record the version it reported
    Given a process manager "Fulfillment" registered with rules version "2.0.1"
    When the process manager reacts to an OrderPlaced event with a FulfillmentStarted event, reporting rules version "2.0.1"
    Then the FulfillmentStarted event records rules version "2.0.1"

  # ===========================================================================
  # Choosing a snapshot: the default rule
  # ===========================================================================

  @snapshot_selection
  @C-0522
  Scenario Outline: A snapshot of the registered state type and the same major.minor is offered
    Given order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    And order "order-1" has events at sequences 6 and 7
    When the coordinator delivers an AddItem command for order "order-1"
    Then business code receives the snapshot at sequence 5
    And business code receives the events at sequences 6 and 7

    Examples:
      | snapshot version |
      | 1.4.2+build.7    |
      | 1.4.0            |
      | 1.4.9+build.12   |
      | 1.4.3-rc.1       |

  @snapshot_selection
  @C-0523
  Scenario Outline: A snapshot from another major.minor is not offered
    Given order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    And order "order-1" has events at sequences 0 to 7
    When the coordinator delivers an AddItem command for order "order-1"
    Then business code receives no snapshot
    And business code receives the events at sequences 0 to 7
    And the command succeeds

    Examples:
      | snapshot version |
      | 1.3.9            |
      | 1.5.0            |
      | 2.4.2            |
      | 0.4.2            |

  @snapshot_selection
  @C-0524
  Scenario: A snapshot of another state type is not offered, whatever its version
    Given order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.LegacyOrderState" recorded under rules version "1.4.2+build.7"
    And order "order-1" has events at sequences 0 to 7
    When the coordinator delivers an AddItem command for order "order-1"
    Then business code receives no snapshot
    And business code receives the events at sequences 0 to 7

  @snapshot_selection
  @C-0525
  Scenario Outline: Against a registered version that is not a semantic version, only the same version is offered
    Given an "order" aggregate registered with state type "/orders.v1.OrderState" and rules version "build-2026-10-19.3"
    And order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    When the coordinator delivers an AddItem command for order "order-1"
    Then the snapshot is <offered>

    Examples:
      | snapshot version   | offered     |
      | build-2026-10-19.3 | offered     |
      | build-2026-10-19.4 | not offered |
      | 1.4.2              | not offered |

  @snapshot_selection
  @C-0526
  Scenario Outline: A snapshot version that is not a semantic version is not offered against a semantic one
    Given order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    When the coordinator delivers an AddItem command for order "order-1"
    Then the snapshot is not offered

    Examples:
      | snapshot version |
      | 1.4              |
      | release-1.4.2    |
      |                  |

  # ===========================================================================
  # Choosing a snapshot: a domain's own rule
  # ===========================================================================

  @snapshot_selection
  @C-0527
  Scenario Outline: An accept pattern replaces the default rule
    Given the "order" domain accepts snapshot versions matching "1\.[34]\..*"
    And order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    When the coordinator delivers an AddItem command for order "order-1"
    Then the snapshot is <offered>

    Examples:
      | snapshot version | offered     |
      | 1.3.7            | offered     |
      | 1.4.2+build.7    | offered     |
      | 1.5.0            | not offered |

  @snapshot_selection
  @C-0528
  Scenario Outline: A reject match wins over an accept match
    Given the "order" domain accepts snapshot versions matching "1\..*"
    And the "order" domain rejects snapshot versions matching "1\.3\.0(\+.*)?"
    And order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    When the coordinator delivers an AddItem command for order "order-1"
    Then the snapshot is <offered>

    Examples:
      | snapshot version | offered     |
      | 1.3.1            | offered     |
      | 1.3.0            | not offered |
      | 1.3.0+build.2    | not offered |

  @snapshot_selection
  @C-0529
  Scenario Outline: A pattern must match the whole version
    Given the "order" domain accepts snapshot versions matching "1\.4"
    And order "order-1" has a snapshot at sequence 5 of state type "/orders.v1.OrderState" recorded under rules version "<snapshot version>"
    When the coordinator delivers an AddItem command for order "order-1"
    Then the snapshot is <offered>

    Examples:
      | snapshot version | offered     |
      | 1.4              | offered     |
      | 1.4.2            | not offered |
      | 21.4             | not offered |

  @snapshot_selection
  @C-0530
  Scenario: A pattern that needs lookaround is refused when the configuration loads
    Given coordinator configuration where the "order" domain accepts snapshot versions matching "1\.(?!3).*"
    When the coordinator loads its configuration
    Then the configuration is refused, naming the "order" domain's accept pattern
