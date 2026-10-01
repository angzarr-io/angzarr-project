# Allocated: EU-1590 .. EU-1599
Feature: Table and wallet snapshots
  Rebuilding a long-lived table from its first event gets slower with every
  round, so the table is periodically saved as a snapshot and rebuilt from
  the latest snapshot plus the events after it. Routine snapshots are
  replaced by newer ones; the snapshot taken when a new shoe is shuffled is
  kept for good, marking where each shoe began.

  Why this matters:
  - a table rebuilt from a snapshot must be exactly the table rebuilt from
    the beginning, or play would diverge after a restart
  - the start of every shoe stays available for audits of the cards dealt
    from it, however many routine snapshots come after

  @EU-1590
  Scenario: A table rebuilt from its latest snapshot equals one replayed from the start
    Given table "Main" created with shoe seed 7 has played 10 rounds with two players
    And table "Main" was saved as a snapshot after round 6
    When table "Main" is rebuilt from that snapshot and the events after it
    Then the rebuilt table equals table "Main" replayed from its first event

  @EU-1591
  Scenario: Creating a table keeps a lasting snapshot of its first shoe
    Given table "Main" does not exist
    When table "Main" is created with 3 seats, 1 deck and shoe seed 42
    Then table "Main" is saved as a snapshot that is kept for good

  @EU-1592
  Scenario: Replacing the shoe keeps a lasting snapshot of the new shoe
    Given table "Main"'s first shoe was shuffled from seed 42 and has 10 cards left
    And "Alice" sits at seat 0 of table "Main" and has bet 20
    When the round is dealt
    Then table "Main" is saved as a snapshot that is kept for good
    And the snapshot holds shoe 2 before any of its cards were dealt

  @EU-1593
  Scenario: A routine snapshot is replaced by the next one
    Given table "Main" saves a routine snapshot every 20 events
    And "Alice" sits at seat 0 of table "Main"
    When enough rounds are played for table "Main" to reach a routine snapshot
    Then that snapshot is marked to be replaced by the next one

  @EU-1594
  Scenario: A wallet rebuilt from a snapshot equals one replayed from the start
    Given "Alice" has a history of 30 deposits, holds and withdrawals
    And "Alice"'s wallet was saved as a snapshot after the 20th
    When "Alice"'s wallet is rebuilt from that snapshot and the events after it
    Then the rebuilt wallet equals "Alice"'s wallet replayed from its first event
