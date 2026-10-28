Feature: Editions are per-stream forks, and the fork travels with the data
  An edition is a set of per-stream forks (decision 14.32). Forking an
  origin stream (D, main, R) into edition X appends an EditionForked event
  to (D, X, R) at main's next sequence for that stream; (D, X, R) reads
  main's events below that fork sequence, then X's own. The fork travels
  with the data: a saga's command in X that reaches a stream with no fork
  in X forks it on arrival. A command from outside to an unforked stream is
  refused until propagated. There is no edition registry: an edition is
  known while any fork event of it exists. Scenarios tagged @proposed
  follow the drafter's proposals flagged in 14.32.

  Background:
    Given a "player" aggregate "p-1" with 5 events on the main timeline
    And a saga "PlayerToTable" translating from "player" to "table" that sends SeatPlayer to "table" "t-1" on PlayerReady
    And a "table" aggregate "t-1" with 3 events on the main timeline

  @editions
  @C-0628
  Scenario: Forking an origin stream appends the fork event at main's next sequence
    When ForkStream forks "player" "p-1" into edition "what-if"
    Then "player" "p-1" in edition "what-if" holds an EditionForked event at sequence 5
    And the EditionForked event names edition "what-if" and parent_sequence 5, with no propagated_from and no forked_by
    And the main timeline of "player" "p-1" is unchanged

  @editions
  @C-0629
  Scenario: A forked stream reads main below its fork sequence, then its own events
    Given "player" "p-1" is forked into edition "what-if" at sequence 5
    And "player" "p-1" on the main timeline gains 2 more events
    And "player" "p-1" in edition "what-if" gains 1 event of its own
    When "player" "p-1" is loaded in edition "what-if"
    Then the loaded history is main's events 0 to 4, then the fork event at 5, then the edition's own event at 6
    And none of main's events at or after sequence 5 are in it

  @editions
  @C-0630
  Scenario: A saga command arriving at an unforked stream forks it, then is handled
    Given "player" "p-1" is forked into edition "what-if" at sequence 5
    And "table" "t-1" has no fork in edition "what-if"
    When "player" "p-1" records PlayerReady in edition "what-if"
    Then "table" "t-1" in edition "what-if" first gains an EditionForked event at sequence 3
    And its propagated_from names the fork event of "player" "p-1" in edition "what-if"
    And its forked_by is the SeatPlayer command's command_id
    And the SeatPlayer command is then handled in edition "what-if"
    And no saga business code was called for either fork event

  @editions
  @C-0631
  Scenario: A stream is forked once, whatever arrives later
    Given "player" "p-1" is forked into edition "what-if"
    And "table" "t-1" was forked in edition "what-if" by an earlier SeatPlayer
    When "player" "p-1" records PlayerReady again in edition "what-if"
    Then "table" "t-1" in edition "what-if" still holds exactly one EditionForked event
    And the new SeatPlayer command is handled in edition "what-if"

  # C-0632 (a propagation hop bound) is retired: the fork travels with the
  # data, which is its only bound (decision 14.32).

  @editions @proposed
  @C-0633
  Scenario Outline: An outside input to a stream not forked in the edition is refused until propagated
    Given "player" "p-1" is forked into edition "what-if"
    And "table" "t-9" with 4 events on the main timeline has no fork in edition "what-if"
    When a client sends <input> to "table" "t-9" in edition "what-if"
    Then the client is answered FAILED_PRECONDITION with reason EDITION_NOT_FORKED
    And "table" "t-9" holds no event in edition "what-if"

    Examples:
      | input       |
      | a command   |
      | a fact      |

  @editions
  @C-0634
  Scenario: A query of a stream not yet forked reads main and forks nothing
    Given "player" "p-1" is forked into edition "what-if"
    And "table" "t-9" with 4 events on the main timeline is not forked in "what-if"
    When "table" "t-9" is queried in edition "what-if"
    Then the result is main's 4 events of "table" "t-9"
    And "table" "t-9" holds no event in edition "what-if"

  @editions
  @C-0635
  Scenario Outline: An unknown edition is refused
    Given <history>
    When a command is sent to "player" "p-1" in edition "what-if"
    Then the command is refused NOT_FOUND
    And nothing is written in edition "what-if"

    Examples:
      | history                                                                      |
      | no fork event of edition "what-if" exists anywhere                           |
      | edition "what-if" was forked and then deleted with DeleteEdition             |

  @editions
  @C-0636
  Scenario: Editions are listed from the fork events, with no registry
    Given "player" "p-1" is forked into edition "what-if"
    And a SeatPlayer command has forked "table" "t-1" in edition "what-if"
    When ListEditions is called
    Then the answer lists edition "what-if" with one origin, the fork of "player" "p-1", and 2 forked streams

  @editions
  @C-0637
  Scenario: Deleting an edition removes its rows in every store
    Given "player" "p-1" is forked into edition "what-if"
    And a SeatPlayer command has forked "table" "t-1" in edition "what-if"
    When DeleteEdition deletes "what-if"
    Then no event, fork event, snapshot or projection of edition "what-if" remains in any store
    And the main timelines of "player" "p-1" and "table" "t-1" are unchanged

  @editions @proposed
  @C-0640
  Scenario: A saga command racing a delete does not resurrect the edition
    Given "player" "p-1" is forked into edition "what-if"
    And "player" "p-1" recorded PlayerReady in edition "what-if", and its SeatPlayer is still in the saga's outbox
    When DeleteEdition deletes "what-if"
    And the SeatPlayer command then reaches "table" "t-1"
    Then the arrival fork finds the fork of "player" "p-1" gone, and the command is refused NOT_FOUND
    And the saga's coordinator discards the command, logged and not dead-lettered
    And "table" "t-1" holds no event in edition "what-if"

  @editions
  @C-0638
  Scenario: The time-based option forks every stream at one commit position
    Given the stores keep a global commit position
    And "table" "t-1" on the main timeline gains 1 event after commit position 100
    When ForkStream forks "player" "p-1" into edition "snapshot" at commit position 100
    And "player" "p-1" records PlayerReady in edition "snapshot"
    Then the arrival fork of "table" "t-1" in edition "snapshot" carries commit position 100
    And "table" "t-1" in edition "snapshot" reads only main's events committed at or before position 100

  @editions
  @C-0639
  Scenario: A process manager's instance stream is forked like any domain's
    Given a process manager "BuyIn" owning domain "buy-in" with an instance for correlation "0192a6b0-0000-7000-8000-000000000030"
    And a saga "PlayerToBuyIn" that sends a command to "buy-in" "0192a6b0-0000-7000-8000-000000000030" on PlayerReady
    And "player" "p-1" is forked into edition "what-if"
    When "player" "p-1" records PlayerReady in edition "what-if"
    Then "buy-in" "0192a6b0-0000-7000-8000-000000000030" in edition "what-if" first gains an EditionForked event
    And the command is then handled in edition "what-if"
