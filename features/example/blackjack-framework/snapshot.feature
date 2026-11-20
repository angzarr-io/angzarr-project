# Allocated: EU-1590 .. EU-1599
Feature: Table and wallet snapshots
  Rebuilding a long-lived table from its first event gets slower with every
  round, so the table is periodically saved as a snapshot and rebuilt from
  the latest snapshot plus the events after it.

  Why this matters:
  - a table rebuilt from a snapshot must be exactly the table rebuilt from
    the beginning, or play would diverge after a restart

  Keeping a lasting snapshot where each shoe began waits on the snapshot
  ruling in docs/design/blackjack-latest-proto-rulings.md.

  @EU-1590
  Scenario: A table rebuilt from its latest snapshot equals one replayed from the start
    Given table "Main" created with shoe seed 7 has played 10 rounds with two players
    And table "Main" was saved as a snapshot after round 6
    When table "Main" is rebuilt from that snapshot and the events after it
    Then the rebuilt table equals table "Main" replayed from its first event

  @EU-1594
  Scenario: A wallet rebuilt from a snapshot equals one replayed from the start
    Given "Alice" has a history of 30 deposits, holds and withdrawals
    And "Alice"'s wallet was saved as a snapshot after the 20th
    When "Alice"'s wallet is rebuilt from that snapshot and the events after it
    Then the rebuilt wallet equals "Alice"'s wallet replayed from its first event
