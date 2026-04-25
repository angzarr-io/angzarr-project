Feature: Cross-language wire-format parity
  Both clients must produce byte-identical proto-encoded output for the
  same logical input. Drift between languages on framework-stamped fields
  (e.g. PageHeader.sequence_type) is caught here before it reaches a
  cross-language runtime where one side fails to decode the other's bytes.

  These scenarios pin a SHA-256 of the deterministically-encoded output.
  When both languages independently produce the same hash for the same
  scenario, wire parity holds. The hashes themselves are computed once
  and locked; bumping a hash requires bumping it on both sides in tandem.

  Scenario: Destinations.stamp_command on a single-page CommandBook
    Given a CommandBook with cover.domain "saga-x" and cover.root bytes 00..0f and correlation_id "corr-1"
    And a single CommandPage with command type_url "type.googleapis.com/example.Foo" and payload bytes 01020304
    And destination_sequences mapping "inventory" to 5
    When I stamp the command for domain "inventory"
    Then the deterministically-encoded CommandBook hashes to SHA-256 "8a6da2dfa422553d73fcd840f6ad501c91ac6ffcac2f591183146ab6c042ace9"
