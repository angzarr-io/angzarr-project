Feature: Destinations query surface
  Destinations is the per-saga / per-PM map from output domain to its
  next sequence. Both clients expose the same query surface so users
  can write the same code against either language.

  These scenarios pin the canonical method names on the public API.
  Per-language implementation specifics (deprecated aliases, exact
  warning text, internal storage) belong in unit tests, not here.

  @C-0132
  Scenario: has_domain returns true for a registered domain
    Given a Destinations built from sequences mapping "inventory" to 5 and "billing" to 0
    Then has_domain "inventory" returns true
    And has_domain "billing" returns true

  @C-0133
  Scenario: has_domain returns false for an unregistered domain
    Given a Destinations built from sequences mapping "inventory" to 5
    Then has_domain "shipping" returns false
    And has_domain "" returns false

  @C-0134
  Scenario: domains lists every registered destination
    Given a Destinations built from sequences mapping "inventory" to 5 and "billing" to 0 and "shipping" to 7
    Then domains contains "inventory"
    And domains contains "billing"
    And domains contains "shipping"
    And domains has 3 entries

  @C-0135
  Scenario: domains preserves insertion order
    Both languages must iterate destinations in the order they were
    inserted, not in hash-random order. This pins the contract so a
    storage-type swap can't silently drift.

    Given a Destinations built from an ordered sequence list "zulu" then "alpha" then "mike"
    Then domains in order are "zulu", "alpha", "mike"
