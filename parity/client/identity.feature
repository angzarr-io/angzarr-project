Feature: Deterministic aggregate identity
  As a framework user
  I want business keys to map to stable aggregate root UUIDs
  So that the same (domain, key) pair produces the same root across languages,
  services, and restarts

  Aggregate roots come from UUIDv5 hashing — same inputs, same bytes, every
  time. `compute_root(domain, business_key)` =
  uuid5(NAMESPACE_OID, domain + ":" + business_key). Domain names contain
  no ':', so the separator makes every (domain, key) pair hash a distinct
  name. compute_root is the only identity derivation the client provides;
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
      | cart   | alice  | 92ab9191-4f7d-5ff2-adcf-93a1e494c055 |
      | order  | ord-42 | c20a5dda-4d41-5a65-bb75-22cdc453ca0f |
      | order  |        | 45d20a3f-923e-581e-8943-c731efc6d1c2 |

  @C-0485
  Scenario: compute_root separates domain and key, so shifted boundaries differ
    When I call compute_root with domain "ab" and key "c"
    And I call compute_root with domain "a" and key "bc"
    Then the two UUIDs differ
    And the first UUID equals "59dbfa29-d911-506c-ab4d-37807c015aaa"
    And the second UUID equals "5a62a278-cbda-5121-9f05-8532f1462612"

  @C-0114
  Scenario: to_proto_bytes returns the UUID's 16-byte representation
    When I call compute_root with domain "customer" and key "alice@x.com"
    And I pass the resulting UUID through to_proto_bytes
    Then the byte length is 16
    And the bytes match the hex "3c10f075111d58308cc920b4c9fa0d50"
