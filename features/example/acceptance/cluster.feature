# Allocated: EA-0001 .. EA-0005
Feature: Cluster Acceptance
  Cluster-tier acceptance scenarios. These are only meaningful when run
  against a deployed angzarr cluster (standalone docker-compose or k8s):
  they exercise network serialization, pod lifecycle, inter-coordinator
  routing, and observable read-model lag.

  In-process integration scenarios (single-process sagas, PMs, projectors)
  live in features/example/unit/ and are NOT duplicated here.

  How to run:
  - Start a cluster (standalone.yaml or kind bootstrap) and export
    PLAYER_URL / TABLE_URL / HAND_URL to the coordinator endpoints.
  - The consumer runner selects the gRPC backend automatically when those
    URLs are set and skips these scenarios otherwise.

  # CLUSTER-ONLY: validated against deployed standalone.yaml

  Background:
    Given the poker cluster is reachable via gRPC

  # ===========================================================================
  # Smoke - End-to-end happy path proves the deployed topology wires up.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @e2e @smoke @cluster
  @EA-0001
  Scenario: Smoke end-to-end hand completes across coordinators
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
  @saga @latency @cluster
  @EA-0002
  Scenario: Cross-coordinator saga propagates within realistic bound
    Given a table "Main" with 2 seated players
    When I send a StartHand command to table "Main"
    Then within 5 seconds hand domain has CardsDealt event
    And the hand has the same hand_number as the table event

  # ===========================================================================
  # Event durability - state survives a coordinator restart via replay.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @durability @cluster
  @EA-0003
  Scenario: Player aggregate state survives coordinator restart
    Given a registered player "Alice" with bankroll 1000
    When the player coordinator is restarted
    Then within 10 seconds player "Alice" is reachable
    And player "Alice" has bankroll 1000

  # ===========================================================================
  # Projector eventual-consistency bound observed from outside the process.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @projector @consistency @cluster
  @EA-0004
  Scenario: Projector reflects state-changing command within bound
    Given a registered player "Alice" with bankroll 0
    When I deposit 500 chips to player "Alice"
    Then within 3 seconds the player projection shows bankroll 500

  # ===========================================================================
  # Cross-domain command routing - PM issues a command on a different
  # aggregate's coordinator over the wire.
  # ===========================================================================

  # CLUSTER-ONLY: validated against deployed standalone.yaml
  @routing @pm @cluster
  @EA-0005
  Scenario: PM-issued command routes to a different coordinator
    Given a table "Main" with seated players:
      | name  | seat | stack |
      | Alice | 0    | 500   |
      | Bob   | 1    | 500   |
    When a hand starts at table "Main"
    Then within 5 seconds:
      | domain | event_type  |
      | table  | HandStarted |
      | hand   | CardsDealt  |
    And the DealCards command was routed to the hand coordinator
