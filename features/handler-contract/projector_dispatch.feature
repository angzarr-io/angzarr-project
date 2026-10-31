Feature: Counter projector dispatch
  The CounterProjector (fixture/FIXTURE.md) proves the read-side dispatch
  mechanisms every router implements identically: every delivered event
  folds into one projection instance, and a delivery from an undeclared
  domain folds nothing. Ported from angzarr-router's own conformance
  features; the coordinator delivers every book with its cover (decision
  14.42).

  A projector lists every domain it reads; there is no wildcard domain
  (decision 14.53), so C-0714 (a projector declaring the "*" domain
  folding every domain) is retired.

  @projector
  @C-0712
  Scenario Outline: Every delivered event folds into one projection
    Given a counter projection
    When <count> events are delivered in domain "counter"
    Then the projection records <count> events

    Examples:
      | count |
      | 1     |
      | 3     |
      | 5     |

  @projector
  @C-0713
  Scenario: A delivery from an undeclared domain folds nothing
    Given a counter projection
    When 3 events are delivered in domain "inventory"
    Then the projection records nothing
