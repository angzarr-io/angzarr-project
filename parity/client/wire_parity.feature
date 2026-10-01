Feature: Cross-language wire-format parity
  Every client must produce byte-identical proto-encoded output for the
  same logical input. Drift between languages on framework-stamped fields
  (e.g. PageHeader.sequence_type) is caught here before it reaches a
  cross-language runtime where one side fails to decode the other's bytes.

  These scenarios pin a SHA-256 of the deterministically-encoded output
  (proto canonical field order, no unknown fields). The hashes are computed
  once and locked; changing one requires changing it in every client.

  Destinations.stamp_command turns a saga/PM-emitted CommandBook into a
  deferred command: every page header becomes angzarr_deferred with
  source = the triggering EventBook's cover, source_seq = the triggering
  event's sequence and command_index = the command's emission position.
  source_component is left empty (the coordinator stamps it). The command
  has no expected version: no explicit sequence is set, and the supplied
  destination head (5) appears nowhere in the output.

  Background:
    Given a source cover with domain "order", root bytes 00..0f and correlation_id "corr-1"
    And a CommandBook with cover.domain "inventory", cover.root bytes 10..1f and correlation_id "corr-1"
    And a single CommandPage with command type_url "type.googleapis.com/example.Foo" and payload bytes 01020304
    And destination_sequences mapping "inventory" to 5

  @C-0182
  Scenario: Destinations.stamp_command on the first command of an invocation
    When I stamp the command for domain "inventory" from source event sequence 3 at command index 0
    Then the deterministically-encoded CommandBook hashes to SHA-256 "a79987223c3ece4657c21aa2b5c6f748a3032ba601d4f8f85e4bb9a0ac503758"

  @C-0183
  Scenario: Destinations.stamp_command on a later command of an invocation
    When I stamp the command for domain "inventory" from source event sequence 3 at command index 1
    Then the deterministically-encoded CommandBook hashes to SHA-256 "a0ea9bae4f5492fe3a62aba851fe39c36dadc619cbe2702e1be0c1dd0b20efc1"
