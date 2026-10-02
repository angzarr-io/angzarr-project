Feature: Public API parity
  As a maintainer of angzarr's client libraries
  I want every language-idiomatic binding to export the same canonical set of public names
  So that cross-language documentation, examples, and mental models transfer without translation

  A client library provides: thin consumer clients (CommandHandlerClient,
  QueryClient, SpeculativeClient, DomainClient) and their fluent builders;
  errors and retry policy; compute_root; the `testing` namespace; access to
  the angzarr-router binding for generated component code; and a reusable
  gRPC component host. It does not provide a dispatch engine of its own
  (decorators, Router builders, handler adapters, compensation helpers):
  dispatch is the router's, specified by angzarr-router's conformance suite.

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
    And the "TYPE_URL_PREFIX" constant is exported with value "/"

  @C-0098
  Scenario: Identity helpers are exported
    # compute_root is the only identity derivation; domain-specific
    # wrappers belong in applications and examples, not the client.
    Then the "compute_root" symbol is exported
    And the "to_proto_bytes" symbol is exported

  @C-0099
  Scenario: Testing helpers are exported from the testing module only
    # Test utilities live in a `testing` module/namespace (Python
    # angzarr_client.testing, Rust a `testing` module behind a test-only
    # feature, Go a testing subpackage, …), gated from the production API:
    # reachable there, not from the client's root.
    Then the "make_timestamp" symbol is exported from the testing module
    And the "make_cover" symbol is exported from the testing module
    And the "make_event_page" symbol is exported from the testing module
    And the "make_event_book" symbol is exported from the testing module
    And the "make_command_page" symbol is exported from the testing module
    And the "make_command_book" symbol is exported from the testing module
    And the "uuid_for" symbol is exported from the testing module
    And the "uuid_str_for" symbol is exported from the testing module
    And the "uuid_obj_for" symbol is exported from the testing module
    And the "DEFAULT_TEST_NAMESPACE" constant is exported from the testing module
    And the "ScenarioContext" symbol is exported from the testing module
    And none of the testing helpers is exported from the client's root

  @C-0100
  Scenario: Retry policy types are exported
    Then the "RetryPolicy" symbol is exported
    And the "ExponentialBackoffRetry" symbol is exported
    And the "default_retry_policy" symbol is exported

  @C-0104
  Scenario: Fluent builders are exported
    Then the "CommandBuilder" symbol is exported
    And the "QueryBuilder" symbol is exported

  @C-0494
  Scenario: The router binding is reachable for generated component code
    # Generated component code (angzarr-cli codegen) registers handlers with
    # the angzarr-router binding through the client; the binding is reached
    # through the client's `router` module/namespace.
    Then the router binding is exported from the router module
    And the client's root exports no dispatch-engine API: no handler decorators, Router builders, handler gRPC adapters or compensation helpers

  @C-0495
  Scenario: The component host is exported
    Then the "ComponentHost" symbol is exported
    And the "configure_logging" symbol is exported
    And the "get_transport_config" symbol is exported

  @C-0496
  Scenario: The client contains no example or business-specific types or services
    # The client is generic framework code. Application and example types,
    # domain-specific helpers and application gRPC services live in the
    # application; an application plugs its extra services into the host
    # (see hosting.feature).
    Then no exported symbol, module or gRPC service of the client names an example or business concept
    And the component host serves only framework services and the services an application registers
