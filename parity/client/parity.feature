# Allocated: C-0089 .. C-0106
Feature: Public API parity
  As a maintainer of angzarr's client libraries
  I want every language-idiomatic binding to export the same canonical set of public names
  So that cross-language documentation, examples, and mental models transfer without translation

  The scenarios below describe the canonical cross-language public surface.
  Each language may render a symbol in its idiomatic form (class vs enum
  variant, class decorator vs proc-macro attribute, method vs free function,
  wrapper class vs extension trait). Parity is name-level: every name below
  must resolve to a callable, type, or constant at the client library's
  public root in every language, via the language's idiomatic import/use
  mechanism.

  Background:
    Given the angzarr client library is importable at its public root

  @C-0089
  Scenario: Client types are exported
    Then the "CommandHandlerClient" symbol is exported
    And the "QueryClient" symbol is exported
    And the "SpeculativeClient" symbol is exported
    And the "DomainClient" symbol is exported

  @C-0090
  Scenario: Router runtime types are exported
    Then the "Router" symbol is exported
    And the "BuildError" symbol is exported
    And the "DispatchError" symbol is exported
    And the "CommandHandlerRouter" symbol is exported
    And the "SagaRouter" symbol is exported
    And the "ProcessManagerRouter" symbol is exported
    And the "ProjectorRouter" symbol is exported
    And the "UpcasterRouter" symbol is exported

  @C-0091
  Scenario: Handler kind declarations are exported
    Then the "command_handler" kind declaration is exported
    And the "saga" kind declaration is exported
    And the "process_manager" kind declaration is exported
    And the "projector" kind declaration is exported
    And the "upcaster" kind declaration is exported

  @C-0092
  Scenario: Method markers are exported
    Then the "handles" method marker is exported
    And the "applies" method marker is exported
    And the "rejected" method marker is exported
    And the "state_factory" method marker is exported
    And the "upcasts" method marker is exported

  @C-0093
  Scenario: Handler response types are exported
    Then the "SagaHandlerResponse" symbol is exported
    And the "ProcessManagerResponse" symbol is exported
    And the "RejectionHandlerResponse" symbol is exported

  @C-0094
  Scenario: gRPC server adapters are exported
    Then the "CommandHandlerGrpc" symbol is exported
    And the "SagaGrpc" symbol is exported
    And the "ProcessManagerGrpc" symbol is exported
    And the "ProjectorGrpc" symbol is exported
    And the "UpcasterGrpc" symbol is exported

  @C-0095
  Scenario: Canonical error types are exported
    # ClientError is the umbrella type; CommandRejectedError is the business
    # rejection carrier. Kind-specific variants (connection, transport, gRPC,
    # invalid-argument, invalid-timestamp) are rendered per-language — as
    # distinct exception classes in Python, as enum variants on ClientError in
    # Rust. Introspection is tested via @C-0096 predicates, not type identity.
    Then the "ClientError" symbol is exported
    And the "CommandRejectedError" symbol is exported

  @C-0096
  Scenario: Error introspection predicates are exposed
    Then the client exposes the "is_not_found" error predicate
    And the client exposes the "is_precondition_failed" error predicate
    And the client exposes the "is_invalid_argument" error predicate
    And the client exposes the "is_connection_error" error predicate

  @C-0097
  Scenario: Canonical domain constants are exported
    Then the "UNKNOWN_DOMAIN" constant is exported
    And the "WILDCARD_DOMAIN" constant is exported
    And the "DEFAULT_EDITION" constant is exported
    And the "META_ANGZARR_DOMAIN" constant is exported
    And the "PROJECTION_DOMAIN_PREFIX" constant is exported
    And the "PROJECTION_TYPE_URL" constant is exported
    And the "TYPE_URL_PREFIX" constant is exported
    And the "INVENTORY_PRODUCT_NAMESPACE" constant is exported

  @C-0098
  Scenario: Identity helpers are exported
    Then the "compute_root" symbol is exported
    And the "customer_root" symbol is exported
    And the "product_root" symbol is exported
    And the "order_root" symbol is exported
    And the "inventory_root" symbol is exported
    And the "inventory_product_root" symbol is exported
    And the "cart_root" symbol is exported
    And the "fulfillment_root" symbol is exported
    And the "to_proto_bytes" symbol is exported

  @C-0099
  Scenario: Testing helpers are exported
    Then the "make_timestamp" symbol is exported
    And the "make_cover" symbol is exported
    And the "make_event_page" symbol is exported
    And the "make_event_book" symbol is exported
    And the "make_command_page" symbol is exported
    And the "make_command_book" symbol is exported
    And the "uuid_for" symbol is exported
    And the "uuid_str_for" symbol is exported
    And the "uuid_obj_for" symbol is exported
    And the "DEFAULT_TEST_NAMESPACE" constant is exported
    And the "ScenarioContext" symbol is exported

  @C-0100
  Scenario: Retry policy types are exported
    Then the "RetryPolicy" symbol is exported
    And the "ExponentialBackoffRetry" symbol is exported
    And the "default_retry_policy" symbol is exported

  @C-0101
  Scenario: Validation helpers are exported
    Then the "require_exists" symbol is exported
    And the "require_not_exists" symbol is exported
    And the "require_positive" symbol is exported
    And the "require_non_negative" symbol is exported
    And the "require_not_empty" symbol is exported
    And the "require_not_empty_str" symbol is exported
    And the "require_status" symbol is exported
    And the "require_status_not" symbol is exported

  @C-0102
  Scenario: Compensation helpers are exported
    Then the "CompensationContext" symbol is exported
    And the "delegate_to_framework" symbol is exported
    And the "emit_compensation_events" symbol is exported
    And the "pm_delegate_to_framework" symbol is exported
    And the "pm_emit_compensation_events" symbol is exported

  # @C-0103 (Event-packing helpers) was removed: `new_event_book` /
  # `new_event_book_multi` had no production callers in any client or
  # example. Audit finding #57 already removed `pack_event` / `pack_events`
  # for the same reason; this completes that cleanup. User code returns
  # events via the proc-macro / decorator-driven dispatch, not these
  # helpers. Slot intentionally vacant — do not reuse.

  @C-0104
  Scenario: Fluent builders are exported
    Then the "CommandBuilder" symbol is exported
    And the "QueryBuilder" symbol is exported

  @C-0105
  Scenario: Destinations type is exported
    Then the "Destinations" symbol is exported

  @C-0106
  Scenario: Server utilities are exported
    Then the "configure_logging" symbol is exported
    And the "get_transport_config" symbol is exported
    And the "create_server" symbol is exported
    And the "run_server" symbol is exported
    And the "cleanup_socket" symbol is exported
