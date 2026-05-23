# Allocated: EA-0001 .. EA-0005
Feature: Cluster Acceptance
  Cluster-tier acceptance scenarios. These are only meaningful when run
  against a deployed angzarr cluster (standalone docker-compose or k8s):
  they exercise network serialization, pod lifecycle, cross-service
  request routing, and observable read-model lag.

  In-process integration scenarios (single-process sagas, PMs, projectors)
  live in features/example/unit/ and are NOT duplicated here.

  How to run:
  - Start a cluster (standalone.yaml or kind bootstrap) and export
    PLAYER_URL / TABLE_URL / HAND_URL to the service endpoints.
  - The consumer runner selects the networked backend automatically when
    those URLs are set and skips these scenarios otherwise.

  # CLUSTER-ONLY: validated against deployed standalone.yaml

  Background:
    Given the poker cluster is reachable

  # ===========================================================================
  # Smoke - End-to-end happy path proves the deployed topology wires up.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @wip
  @e2e @smoke @cluster
  @EA-0001
  Scenario: Smoke end-to-end hand completes across services
    Given registered players with bankroll:
      | name  | bankroll |
      | Alice | 1000     |
      | Bob   | 1000     |
    When I create a Texas Hold'em table "Main" with blinds 5/10
    And player "Alice" joins table "Main" at seat 0 with buy-in 500
    And player "Bob" joins table "Main" at seat 1 with buy-in 500
    And a hand starts at table "Main"
    Then within 5 seconds:
      | domain | event_type  |
      | table  | HandStarted |
      | hand   | CardsDealt  |

  # ===========================================================================
  # Saga propagation latency over the real wire.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @wip
  @saga @latency @cluster
  @EA-0002
  Scenario: Cross-service saga propagates within realistic bound
    Given a table "Main" with 2 seated players
    When I start a hand at table "Main"
    Then within 5 seconds hand domain has CardsDealt event
    And the hand has the same hand_number as the table event

  # ===========================================================================
  # Event durability - state survives a service restart via replay.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @wip
  @durability @cluster
  @EA-0003
  Scenario: Player state survives a service restart
    Given a registered player "Alice" with bankroll 1000
    When the player service restarts
    Then within 10 seconds player "Alice" is reachable
    And player "Alice" has bankroll 1000

  # ===========================================================================
  # Read-model eventual-consistency bound observed from outside the process.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  # Tagged @wip until an external read surface exists. The previous
  # impl polled the in-test bookkeeping mirror (which the When step had
  # already set), so the assertion never observed the actual read model
  # — see ACCEPTANCE_REMEDIATION_PLAN.md Pattern J.
  @wip
  @projector @consistency @cluster @wip
  @EA-0004
  Scenario: Player display reflects a deposit within bound
    Given a registered player "Alice" with bankroll 0
    When I deposit 500 chips to player "Alice"
    Then within 3 seconds the player display reports bankroll 500

  # ===========================================================================
  # Cross-domain request routing - one service issues a request that lands
  # on a different aggregate's service over the wire.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @wip
  @routing @pm @cluster
  @EA-0005
  Scenario: A cross-domain request reaches the correct service
    Given a table "Main" with seated players:
      | name  | seat | stack |
      | Alice | 0    | 500   |
      | Bob   | 1    | 500   |
    When a hand starts at table "Main"
    Then within 5 seconds:
      | domain | event_type  |
      | table  | HandStarted |
      | hand   | CardsDealt  |
    And the deal-cards request was handled by the hand service
