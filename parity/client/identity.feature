Feature: Deterministic aggregate identity
  As a framework user
  I want business keys to map to stable aggregate root UUIDs
  So that the same (domain, key) pair produces the same root across languages,
  services, and restarts

  Aggregate roots come from UUIDv5 hashing — same inputs, same bytes, every
  time. `compute_root(domain, business_key)` =
  uuid5(ANGZARR_ROOT_NAMESPACE, domain + ":" + business_key) (decision
  9.2). Domain names contain no ':', so the separator makes every (domain,
  key) pair hash a distinct name. compute_root is the only identity derivation the client provides;
  domain-specific wrappers (e.g. `customer_root(email)`) belong in the
  applications and examples that need them.

  @C-0107
  Scenario: compute_root is deterministic
    When I call compute_root with domain "cart" and key "alice"
    And I call compute_root with domain "cart" and key "alice" a second time
    Then both calls return the same UUID

  @C-0108
  Scenario: compute_root distinguishes domains
    When I call compute_root with domain "cart" and key "alice"
    And I call compute_root with domain "order" and key "alice"
    Then the two UUIDs differ

  @C-0109
  Scenario: compute_root distinguishes business keys
    When I call compute_root with domain "cart" and key "alice"
    And I call compute_root with domain "cart" and key "bob"
    Then the two UUIDs differ

  @C-0110
  Scenario Outline: compute_root matches known cross-language fixtures
    When I call compute_root with domain "<domain>" and key "<key>"
    Then the resulting UUID equals "<uuid>"

    Examples:
      | domain | key    | uuid                                 |
      | cart   | alice  | 3cfe0a31-d58d-5190-af30-5459ccc221f7 |
      | order  | ord-42 | 8ad34c5c-88df-52d4-8d28-acfd0d93e443 |
      | order  |        | ea82cbbb-bdd2-506f-bf90-652a2c4c2125 |

  @C-0485
  Scenario: compute_root separates domain and key, so shifted boundaries differ
    When I call compute_root with domain "ab" and key "c"
    And I call compute_root with domain "a" and key "bc"
    Then the two UUIDs differ
    And the first UUID equals "c208d221-29c2-58f8-93fa-e72d9f818374"
    And the second UUID equals "456e2a8f-e675-5d30-8865-5ef7c175149c"

  @C-0513
  Scenario: compute_root refuses a domain containing ':'
    When I call compute_root with domain "bad:domain" and key "k"
    Then the error should be an invalid argument error

  @C-0114
  Scenario: to_proto_bytes returns the UUID's 16-byte representation
    When I call compute_root with domain "customer" and key "alice@x.com"
    And I pass the resulting UUID through to_proto_bytes
    Then the byte length is 16
    And the bytes match the hex "e013c1a3f7285251a10306ea351ead23"
