# Allocated: C-0107 .. C-0114
Feature: Deterministic aggregate identity
  As a framework user
  I want business keys to map to stable aggregate root UUIDs
  So that the same (domain, key) pair produces the same root across languages,
  services, and restarts

  Aggregate roots come from UUIDv5 hashing — same inputs, same bytes, every
  time. The base `compute_root(domain, business_key)` is the primitive; the
  per-domain helpers (`customer_root`, `order_root`, …) are thin wrappers
  that supply a domain tag. `inventory_product_root` is the one exception —
  it hashes under the DNS namespace directly, so callers keying off product
  catalog entries skip the "angzarr" prefix.

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
      | cart   | alice  | f520dbd7-0692-5a5a-b315-48c73f2fff1b |
      | order  | ord-42 | 1e941e06-245c-5be9-9885-45852f029d0d |
      | order  |        | b6408065-482a-5d1a-9aac-ef4bb488f3b7 |

  @C-0111
  Scenario Outline: per-domain root helpers match known cross-language fixtures
    When I call "<helper>" with "<input>"
    Then the resulting UUID equals "<uuid>"

    Examples:
      | helper                 | input       | uuid                                 |
      | customer_root          | alice@x.com | 9141d644-0602-5762-a8b9-d74e7d5a3d45 |
      | product_root           | SKU-001     | 25541820-eb7c-559d-9d00-834865d6ba57 |
      | order_root             | ord-42      | 1e941e06-245c-5be9-9885-45852f029d0d |
      | inventory_root         | prod-7      | af78f0ed-83a9-58aa-9f7b-53b253dd7242 |
      | cart_root              | cust-9      | 26e1f44e-eac8-550f-a738-4473dca718e5 |
      | fulfillment_root       | ord-42      | ea29617a-0b9d-5c36-aefb-aec161b3cb34 |
      | inventory_product_root | sku-xyz     | 8c6baabf-71a0-5b46-b953-ec3bdac0a995 |

  @C-0112
  Scenario: inventory_product_root uses the DNS namespace (not the "angzarr" prefix)
    When I call compute_root with domain "inventory_product" and key "sku-xyz"
    And I call inventory_product_root with "sku-xyz"
    Then the two UUIDs differ

  @C-0113
  Scenario: INVENTORY_PRODUCT_NAMESPACE is the RFC 4122 DNS namespace UUID
    Then INVENTORY_PRODUCT_NAMESPACE equals the UUID "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

  @C-0114
  Scenario: to_proto_bytes returns the UUID's 16-byte representation
    When I call customer_root with "alice@x.com"
    And I pass the resulting UUID through to_proto_bytes
    Then the byte length is 16
    And the bytes match the hex "9141d64406025762a8b9d74e7d5a3d45"
