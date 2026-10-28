Feature: Editions are per-stream forks, propagated by angzarr
  An edition is a set of per-stream forks (decision 14.32). Forking an
  origin stream (D, main, R) into edition X appends an EditionForked event
  to (D, X, R) at main's next sequence for that stream; (D, X, R) reads
  main's events below that fork sequence, then X's own. angzarr propagates
  the fork, through the same data flow as any event, to the streams the
  forked stream's reactions feed: eventually consistent, not lazy. There
  is no edition registry: an edition is known while any fork event of it
  exists. Scenarios tagged @proposed follow the drafter's proposals in
  14.32, flagged for the owner.

  Background:
    Given a "player" aggregate "p-1" with 5 events on the main timeline
    And a saga "PlayerToTable" translating from "player" to "table" that has delivered commands from "player" "p-1" to "table" "t-1"
    And a "table" aggregate "t-1" with 3 events on the main timeline

  @editions
  @C-0628
  Scenario: Forking an origin stream appends the fork event at main's next sequence
    When ForkStream forks "player" "p-1" into edition "what-if"
    Then "player" "p-1" in edition "what-if" holds an EditionForked event at sequence 5
    And the EditionForked event names edition "what-if" and parent_sequence 5, with no propagated_from
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

  @editions @proposed
  @C-0630
  Scenario: angzarr propagates a fork along the recorded reaction edges
    When ForkStream forks "player" "p-1" into edition "what-if"
    Then within a bounded time "table" "t-1" in edition "what-if" holds an EditionForked event at sequence 3
    And its propagated_from names the fork event of "player" "p-1" in edition "what-if"
    And no saga business code was called for either fork event

  @editions @proposed
  @C-0631
  Scenario: Propagation is idempotent and ends at streams already forked
    Given "table" "t-1" is already forked into edition "what-if"
    And a saga "TableToPlayer" translating from "table" to "player" that has delivered commands from "table" "t-1" to "player" "p-1"
    When ForkStream forks "player" "p-1" into edition "what-if"
    Then "table" "t-1" in edition "what-if" holds exactly one EditionForked event
    And "player" "p-1" in edition "what-if" holds exactly one EditionForked event

  @editions @proposed
  @C-0632
  Scenario: Propagation stops at its hop bound
    Given a chain of sagas whose recorded edges lead 10 hops downstream from "player" "p-1"
    And the propagation hop bound is 8
    When ForkStream forks "player" "p-1" into edition "what-if"
    Then the streams up to 8 hops downstream are forked in "what-if"
    And the streams beyond 8 hops are not forked until a command reaches them

  @editions @proposed
  @C-0633
  Scenario: A command to a stream no fork has reached forks it on demand
    Given "player" "p-1" is forked into edition "what-if"
    And "table" "t-9" with 4 events on the main timeline has no edge from "player" "p-1"
    When a command is sent to "table" "t-9" in edition "what-if"
    Then "table" "t-9" in edition "what-if" first gains an EditionForked event at sequence 4 with on_demand set
    And the command is then handled in edition "what-if"

  @editions @proposed
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
    And the fork has propagated to "table" "t-1"
    When ListEditions is called
    Then the answer lists edition "what-if" with one origin, the fork of "player" "p-1", and 2 forked streams

  @editions @proposed
  @C-0637
  Scenario: Deleting an edition removes its rows, and propagation stops there
    Given "player" "p-1" is forked into edition "what-if"
    When DeleteEdition deletes "what-if" before the fork reaches "table" "t-1"
    Then no event, snapshot or projection of edition "what-if" remains in any store
    And the propagation step for "table" "t-1" finds its upstream fork gone and forks nothing
    And the main timelines of "player" "p-1" and "table" "t-1" are unchanged

  @editions
  @C-0638
  Scenario: The time-based option forks every stream at one commit position
    Given the stores keep a global commit position
    And "table" "t-1" on the main timeline gains 1 event after commit position 100
    When ForkStream forks "player" "p-1" into edition "snapshot" at commit position 100
    Then every fork of edition "snapshot", propagated or on demand, carries commit position 100
    And "table" "t-1" in edition "snapshot" reads only main's events committed at or before position 100

  @editions @proposed
  @C-0639
  Scenario: A process manager's instance stream is forked like any domain's
    Given a process manager "BuyIn" owning domain "buy-in" with an instance for correlation "0192a6b0-0000-7000-8000-000000000030"
    And a saga "PlayerToBuyIn" that has delivered commands from "player" "p-1" to "buy-in" "0192a6b0-0000-7000-8000-000000000030"
    When ForkStream forks "player" "p-1" into edition "what-if"
    Then within a bounded time "buy-in" "0192a6b0-0000-7000-8000-000000000030" in edition "what-if" holds an EditionForked event
    And the propagation continues through the sagas from "buy-in"
