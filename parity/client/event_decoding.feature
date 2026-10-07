Feature: Event Decoding - Payload Deserialization
  Events are stored as google.protobuf.Any with type_url and value.
  Decoding extracts typed messages from the Any wrapper by type name. Every
  client emits type URLs as "/" + the fully-qualified message name
  (TYPE_URL_PREFIX = "/") and accepts any prefix: a type URL names the
  message whose fully-qualified name is the text after its last "/".
  Names are compared exactly. This is fundamental for state building and
  projections.

  # ==========================================================================
  # Basic Decoding
  # ==========================================================================

  @C-0365
  Scenario: Decode event with matching type URL
    Given an event with type_url "/orders.OrderCreated"
    And valid protobuf bytes for OrderCreated
    When I decode the event as OrderCreated
    Then decoding should succeed
    And I should get an OrderCreated message

  @C-0366
  Scenario: Decode rejects type-name suffix that isn't the full name
    # decode_event compares the FULL type name after the last "/"
    # ("orders.OrderCreated") with the requested name; "OrderCreated"
    # is a different name, not a suffix match.
    Given an event with type_url "/orders.OrderCreated"
    When I decode the event with full_type_name "OrderCreated"
    Then decoding should return None/null

  @C-0367
  Scenario: Decode returns None for type mismatch
    Given an event with type_url "/orders.ItemAdded"
    When I decode the event as OrderCreated
    Then decoding should return None/null
    And no error should be raised

  # ==========================================================================
  # EventPage Structure
  # ==========================================================================

  @C-0368
  Scenario: EventPage contains sequence
    Given an EventPage at sequence 5
    Then event.sequence should be 5

  @C-0369
  Scenario: EventPage contains created_at timestamp
    Given an EventPage with timestamp
    Then event.created_at should be a valid timestamp
    And the timestamp should be parseable

  @C-0370
  Scenario: EventPage payload is Event variant
    Given an EventPage with Event payload
    Then event.payload should be Event variant
    And the Event should contain the Any wrapper

  @C-0371
  Scenario: EventPage payload can be PayloadReference
    Given an EventPage with offloaded payload
    Then event.payload should be PayloadReference variant
    And the reference should contain storage details

  # ==========================================================================
  # Type URL Handling
  # ==========================================================================

  @C-0372
  Scenario Outline: Type URLs match by the full name after the last slash, whatever the prefix
    Given an event with type_url "<type_url>"
    When I match against "myapp.events.v1.OrderCreated"
    Then the match should succeed

    Examples:
      | type_url                                         |
      | /myapp.events.v1.OrderCreated                    |
      | type.googleapis.com/myapp.events.v1.OrderCreated |
      | example.com/types/myapp.events.v1.OrderCreated   |
      | myapp.events.v1.OrderCreated                     |

  @C-0373
  Scenario: Versioned type names are distinct
    # Exact name matching: "myapp.events.v1.OrderCreated" and
    # "myapp.events.v2.OrderCreated" are different names.
    Given events with type_urls:
      | /myapp.events.v1.OrderCreated                    |
      | type.googleapis.com/myapp.events.v2.OrderCreated |
    When I match against "myapp.events.v1.OrderCreated"
    Then only the v1 event should match

  @C-0474
  Scenario: A packed event is emitted with the bare slash prefix
    When I pack an OrderCreated event from package "orders"
    Then the event's type_url is "/orders.OrderCreated"

  # ==========================================================================
  # Payload Bytes
  # ==========================================================================

  @C-0374
  Scenario: Payload bytes are valid protobuf
    Given an event with properly encoded payload
    When I decode the payload bytes
    Then the protobuf message should deserialize correctly
    And all fields should be populated

  @C-0375
  Scenario: Empty payload bytes
    Given an event with empty payload bytes
    When I decode the payload
    Then the message should have default values
    And no error should occur (empty protobuf is valid)

  @C-0376
  Scenario: Corrupted payload bytes
    Given an event with corrupted payload bytes
    When I attempt to decode
    Then decoding should fail
    And an error should indicate deserialization failure

  # ==========================================================================
  # Nil/None Handling
  # ==========================================================================

  @C-0377
  Scenario: EventPage with no payload
    Given an EventPage with payload = None
    When I attempt to decode
    Then decoding should return None/null
    And no crash should occur

  @C-0378
  Scenario: Event with no value bytes
    Given an Event Any with empty value
    When I decode
    Then the result should be a default message
    And no error should occur

  # ==========================================================================
  # Helper Functions
  # ==========================================================================

  @C-0379
  Scenario: decode_event helper function
    # Renamed parameter from `type_suffix` to `full_type_name` per
    # finding #25 — exact matching, not suffix.
    Given the decode_event<T>(event, full_type_name) function
    When I call decode_event(event, "orders.OrderCreated")
    Then if type matches, Some(T) is returned
    And if type doesn't match, None is returned

  @C-0380
  Scenario: events_from_response helper
    Given a CommandResponse with events
    When I call events_from_response(response)
    Then I should get a slice/list of EventPages

  @C-0381
  Scenario: events_from_response with no events
    Given a CommandResponse with no events
    When I call events_from_response(response)
    Then I should get an empty slice/list

  # ==========================================================================
  # Batch Processing
  # ==========================================================================

  @C-0382
  Scenario: Decode multiple events of same type
    Given 5 events all of type "ItemAdded"
    When I decode each as ItemAdded
    Then all 5 should decode successfully
    And each should have correct data

  @C-0383
  Scenario: Decode mixed event types
    Given events: OrderCreated, ItemAdded, ItemAdded, OrderShipped
    When I decode by type
    Then OrderCreated should decode as OrderCreated
    And ItemAdded events should decode as ItemAdded
    And OrderShipped should decode as OrderShipped

  @C-0384
  Scenario: Filter events by type
    Given events: OrderCreated, ItemAdded, ItemAdded, OrderShipped
    When I filter for "ItemAdded" events
    Then I should get 2 events
    And both should be ItemAdded type
