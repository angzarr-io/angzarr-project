Feature: Counter aggregate dispatch
  The CounterAggregate (fixture/FIXTURE.md) proves the dispatch mechanisms
  every router implements identically, the Rust one and the Python one:
  prior events fold into state, commands emit events with historical
  context (answered as payloads only, HandleResponse.events: the
  coordinator wraps them and stamps sequences and meta, decision 14.78),
  business rules refuse with a typed refusal (decision 14.95), and
  unclassified or unknown commands surface as coded errors. Ported from angzarr-router's
  own conformance features, so this tier is the router's complete contract
  (decision 14.42). The router guards no envelope: the coordinator builds
  every delivery well formed.

  @counter
  @C-0693
  Scenario Outline: Increasing a new counter records that many events
    Given a new counter
    When the operator increases the counter by <amount>
    Then <amount> increases are recorded
    And the answer's events are Increased payloads alone, with no sequence, cover or metadata

    Examples:
      | amount |
      | 1      |
      | 2      |
      | 5      |

  @counter
  @C-0694
  Scenario: A prior increase folds in before the next command
    Given a counter that has already recorded 1 increase
    When the operator increases the counter by 2
    Then 2 increases are recorded
    And the handler saw prior history, at next sequence 1

  @counter
  @C-0695
  Scenario: Increasing by zero is refused with its typed refusal and records nothing
    # IncreaseBy names its one refusal, ValueNotPositive, which declares
    # INVALID_ARGUMENT (fixture/counter.proto; decision 14.95).
    Given a new counter
    When the operator increases the counter by 0
    Then the command is refused INVALID_ARGUMENT with reason ANGZARR_REASON_COMMAND_REFUSED
    And the refusal's error info carries refusal_type "test.counter.ValueNotPositive"
    And the refusal's status details carry the ValueNotPositive with n 0
    And no events are recorded

  @counter
  @C-0696
  Scenario: An unclassified failure surfaces as a coded error
    Given a new counter
    When the operator triggers a hard failure
    Then the command fails INTERNAL with ANGZARR_REASON_UNHANDLED_HANDLER_ERROR

  @counter
  @C-0697
  Scenario: An unknown command is reported before any rebuild
    Given a new counter
    When an unhandled command is dispatched
    Then the command fails with ANGZARR_REASON_UNKNOWN_COMMAND_TYPE
    And the refusal is INTERNAL naming the type URL "type.googleapis.com/test.counter.Reserve"

  @counter
  @C-0698
  Scenario: A persisted event the fold cannot fold fails the command as a handler bug
    Given a counter whose history holds a corrupt event
    When the operator increases the counter by 1
    Then the command fails INTERNAL with ANGZARR_REASON_FOLD_FAILED

  @counter
  @C-0699
  Scenario: A fresh counter supplies no prior-history evidence to the handler
    Given a new counter
    When the operator increases the counter by 1
    Then the handler saw no prior history, at next sequence 0

  @counter
  @C-0700
  Scenario: Prior events are reported to the handler as historical evidence
    Given a counter that has already recorded 2 increases
    When the operator increases the counter by 1
    Then the handler saw prior history, at next sequence 2

  @counter
  @C-0701
  Scenario: A starting state seeds the fold, and the pages after it fold onto it
    # The coordinator delivers only the pages after the snapshot (decision
    # 14.40); the router folds every page it is given.
    Given a counter delivered a starting state of 10 at sequence 10 and one Increased event at sequence 11
    When the operator increases the counter by 1
    Then the handler saw a counter of 11, at next sequence 12

  @counter
  @C-0702
  Scenario Outline: Commands and events route by fully-qualified name under any type-URL prefix
    Given a counter that has already recorded 2 increases under the "<prefix>" type-URL prefix
    When the operator increases the counter by 1 under the "<prefix>" type-URL prefix
    Then the handler saw a counter of 2, at next sequence 2

    Examples:
      | prefix               |
      | type.googleapis.com/ |
      | /                    |
      | example.com/types/   |
