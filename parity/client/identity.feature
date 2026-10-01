Feature: Deterministic aggregate identity
  As a framework user
  I want business keys to map to stable aggregate root UUIDs
  So that the same (domain, key) pair produces the same root across languages,
  services, and restarts

  Aggregate roots come from UUIDv5 hashing — same inputs, same bytes, every
  time. The base `compute_root(domain, business_key)` is the primitive:
  uuid5(NAMESPACE_OID, domain + ":" + business_key). Domain names contain
  no ':', so the separator makes every (domain, key) pair hash a distinct
  name. The per-domain helpers (`customer_root`, `order_root`, …) are thin
  wrappers that supply a domain tag. `inventory_product_root` is the one
  exception — it hashes the bare product id under the DNS namespace.

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

  @C-0111
  Scenario Outline: per-domain root helpers match known cross-language fixtures
    When I call "<helper>" with "<input>"
    Then the resulting UUID equals "<uuid>"

    Examples:
      | helper                 | input       | uuid                                 |
      | customer_root          | alice@x.com | 3c10f075-111d-5830-8cc9-20b4c9fa0d50 |
      | product_root           | SKU-001     | 681304c3-053d-5c3d-aa39-382ffa1d69e4 |
      | order_root             | ord-42      | c20a5dda-4d41-5a65-bb75-22cdc453ca0f |
      | inventory_root         | prod-7      | 4c6f96b7-93e0-5068-baca-82bf69330a56 |
      | cart_root              | cust-9      | 7766d323-0b4c-544c-96f0-fbae9c3e6424 |
      | fulfillment_root       | ord-42      | ac7115c0-196d-50e1-8e6b-b64408ad1478 |
      | inventory_product_root | sku-xyz     | 8c6baabf-71a0-5b46-b953-ec3bdac0a995 |

  @C-0112
  Scenario: inventory_product_root uses the DNS namespace, not compute_root
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
    And the bytes match the hex "3c10f075111d58308cc920b4c9fa0d50"
