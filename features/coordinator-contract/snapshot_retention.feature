Feature: Snapshot retention
  Snapshot.retention decides which snapshots survive when a newer snapshot
  of the same aggregate (domain, edition, root) is written:

  - RETENTION_TRANSIENT: deleted once a newer snapshot exists.
  - RETENTION_PERSIST: kept indefinitely (business milestones).
  - RETENTION_DEFAULT (zero value): a checkpoint every 16 events — kept when
    it covers a whole number of 16-event blocks, i.e. (sequence + 1) is a
    multiple of 16; otherwise treated as TRANSIENT.

  The newest snapshot is never deleted. The retention a handler sets on the
  snapshot it returns is persisted unchanged. Reads use the newest snapshot
  regardless of retention.

  Background:
    Given an "order" aggregate "order-1" with events at sequences 0 through 99

  @C-0450
  Scenario: A transient snapshot is deleted when a newer snapshot is written
    Given "order-1" has a RETENTION_TRANSIENT snapshot at sequence 20
    When a snapshot at sequence 40 is written
    Then "order-1" has no snapshot at sequence 20
    And "order-1" has a snapshot at sequence 40

  @C-0451
  Scenario: A persistent snapshot survives newer snapshots
    Given "order-1" has a RETENTION_PERSIST snapshot at sequence 20
    When a snapshot at sequence 40 is written
    And a snapshot at sequence 60 is written
    Then "order-1" has a snapshot at sequence 20

  @C-0452
  Scenario Outline: A default snapshot is kept only on a 16-event checkpoint
    Given "order-1" has a RETENTION_DEFAULT snapshot at sequence <sequence>
    When a snapshot at sequence 90 is written
    Then the snapshot at sequence <sequence> is <outcome>

    Examples:
      | sequence | outcome |
      | 15       | kept    |
      | 31       | kept    |
      | 20       | deleted |
      | 47       | kept    |
      | 50       | deleted |

  @C-0453
  Scenario: The newest snapshot is never deleted
    Given "order-1" has a RETENTION_TRANSIENT snapshot at sequence 20
    When no newer snapshot is written
    Then "order-1" has a snapshot at sequence 20

  @C-0454
  Scenario: The retention a handler sets is persisted unchanged
    When the command handler returns a snapshot at sequence 50 with retention RETENTION_PERSIST
    Then the stored snapshot at sequence 50 has retention RETENTION_PERSIST

  @C-0455
  Scenario: An unset retention is persisted as RETENTION_DEFAULT
    When the command handler returns a snapshot at sequence 50 with no retention set
    Then the stored snapshot at sequence 50 has retention RETENTION_DEFAULT

  @C-0456
  Scenario: Loading uses the newest snapshot whatever its retention
    Given "order-1" has a RETENTION_PERSIST snapshot at sequence 20
    And "order-1" has a RETENTION_TRANSIENT snapshot at sequence 60
    When "order-1" is loaded
    Then the loaded book carries the snapshot at sequence 60
    And the loaded book contains pages at sequences 61 through 99

  @C-0457
  Scenario: Retention is scoped to one aggregate and edition
    Given "order-1" has a RETENTION_TRANSIENT snapshot at sequence 20
    And an "order" aggregate "order-2" has a RETENTION_TRANSIENT snapshot at sequence 10
    When a snapshot of "order-1" at sequence 40 is written
    Then "order-2" has a snapshot at sequence 10
