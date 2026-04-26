# Allocated: C-0115 .. C-0120
#
# Cross-language contract for the `testing` subpackage: UUID byte-equality
# under the shared DEFAULT_TEST_NAMESPACE, builder-shape parity for Cover /
# EventBook, and ScenarioContext reset.
Feature: Testing helpers

  @C-0115
  Scenario: DEFAULT_TEST_NAMESPACE is shared across languages
    Then DEFAULT_TEST_NAMESPACE equals the UUID "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

  @C-0116
  Scenario Outline: uuid_for produces the same bytes in every language
    When I call uuid_for with the name "<name>"
    Then the 16 returned bytes match the hex "<hex>"

    Examples:
      | name     | hex                              |
      | alice    | 8e415de542f65dbc93694846af13f94b |
      | player-1 | 6d9f1c70074953cf8330ccfdf16aa72f |
      | table-1  | de2b7ae84b68570ba3e61cc8610dcfea |
      | order-42 | bf1cb62ec5f35fd986552136859f9b17 |
      | empty-str| 209192ada8d65340b7f90f0af561b918 |

  @C-0117
  Scenario: uuid_for, uuid_str_for, and uuid_obj_for agree on the same name
    When I call uuid_for with the name "alice"
    And I call uuid_str_for with the name "alice"
    And I call uuid_obj_for with the name "alice"
    Then the bytes, string, and object all encode the same UUID

  @C-0118
  Scenario: make_cover stores domain, root, and correlation_id
    Given a 16-byte root derived from the name "alice"
    When I call make_cover with domain "player" and correlation_id "corr-99"
    Then the cover's domain is "player"
    And the cover's correlation_id is "corr-99"
    And the cover's root bytes match the derived root

  @C-0119
  Scenario: make_event_book defaults next_sequence to the page count
    Given a 16-byte root derived from the name "alice"
    And a cover with domain "player" for that root
    When I call make_event_book with that cover, no pages, and no explicit next_sequence
    Then the resulting event book has next_sequence equal to 0

  @C-0120
  Scenario: ScenarioContext.reset clears all state
    Given a ScenarioContext with domain "player" and root bytes for "alice"
    When I reset the scenario context
    Then the context's domain is empty
    And the context's root is empty
    And the context's events list is empty
