Feature: Projector dispatch
  As a projector author
  I want events fanned out to my handlers for side-effect projection
  So that read models and external outputs are updated

  Background:
    Given a projector "Output" consuming domains "order"
    And the projector handles OrderCreated by appending to a write log
    And the router is built with the Output projector

  Scenario: Each event in the book triggers a handler call
    When an EventBook with three OrderCreated events is dispatched
    Then the write log contains 3 entries

  Scenario: Unknown event types are silently skipped
    When an EventBook mixing OrderCreated and OrderCompleted is dispatched
    Then the write log contains only OrderCreated entries

  Scenario: Events from undeclared domains do not fire handlers
    When an EventBook in domain "inventory" is dispatched
    Then the write log remains empty
