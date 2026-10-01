Feature: Destinations query surface
  Destinations is the per-saga / per-PM set of output domains the component
  declares (ComponentOptions.output_domain together with output_domains, in
  declaration order). It holds no sequences: emitted commands are deferred
  and appended at the destination head. Every client exposes the same query
  surface so users can write the same code against any language.

  These scenarios pin the canonical method names on the public API.
  Per-language implementation specifics (deprecated aliases, exact
  warning text, internal storage) belong in unit tests, not here.

  @C-0132
  Scenario: has_domain returns true for a registered domain
    Given a Destinations for a component declaring output domains "inventory" and "billing"
    Then has_domain "inventory" returns true
    And has_domain "billing" returns true

  @C-0133
  Scenario: has_domain returns false for an unregistered domain
    Given a Destinations for a component declaring output domain "inventory"
    Then has_domain "shipping" returns false
    And has_domain "" returns false

  @C-0134
  Scenario: domains lists every registered destination
    Given a Destinations for a component declaring output domains "inventory", "billing" and "shipping"
    Then domains contains "inventory"
    And domains contains "billing"
    And domains contains "shipping"
    And domains has 3 entries

  @C-0135
  Scenario: domains preserves declaration order
    Every client iterates destinations in declaration order, not in
    hash-random order, so a storage-type swap can't silently drift.

    Given a Destinations for a component declaring output domains "zulu", "alpha" and "mike"
    Then domains in order are "zulu", "alpha", "mike"
