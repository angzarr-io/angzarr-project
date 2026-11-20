# docs:start:error_handling_contract
Feature: Error Handling - Client Error Introspection
  Client errors provide structured information for retry logic,
  user feedback, and debugging. Errors are categorized by type
  (connection, validation, business rule) with introspection methods.

  Proper error handling enables:
  - Automatic retry on transient failures
  - User-friendly text, rendered where it is displayed from a catalog
    keyed by the error's code (decision 14.37: an error is a code and an
    argument map, never rendered English)
  - Re-reading and deciding again after a stale expected sequence (the
    coordinator's ExpectedSequenceMismatch refusal; there is no conflict
    resolution, decisions 14.92 and 14.94)
  - Debugging and logging
# docs:end:error_handling_contract

  # ==========================================================================
  # Error Categories
  # ==========================================================================

  @C-0341
  Scenario: Connection error is identifiable
    Given the server is unreachable
    When I attempt a client operation
    Then the error should be a connection error
    And is_connection_error should return true
    And the error's code and args should name the connection failure

  @C-0342
  Scenario: Transport error is identifiable
    Given the connection drops mid-request
    When I attempt a client operation
    Then the error should be a transport error
    And is_connection_error should return true

  @C-0343
  Scenario: gRPC error wraps server status
    Given the server returns a gRPC error
    When I attempt a client operation
    Then the error should be a gRPC error
    And the underlying Status should be accessible

  @C-0344
  Scenario: Invalid argument error from client validation
    When I build a command without required fields
    Then the error should be an invalid argument error
    And is_invalid_argument should return true
    And the error's code and args should name what's missing

  @C-0345
  Scenario: Invalid timestamp error
    When I build a query with invalid timestamp format
    Then the error should be an invalid timestamp error
    And the error's code and args should name the format problem

  # ==========================================================================
  # gRPC Error Introspection
  # ==========================================================================

  @C-0346
  Scenario: NOT_FOUND error is identifiable
    Given the aggregate does not exist
    When I query events for the aggregate
    Then is_not_found should return true
    And code should return NOT_FOUND

  @C-0347
  Scenario: FAILED_PRECONDITION error is identifiable
    # A set expected sequence other than the head is refused by the
    # coordinator before business code, as a typed refusal (decision 14.94).
    Given the server stream's head is next_sequence 5
    When I execute a mock command with expected sequence 3
    Then is_precondition_failed should return true
    And code should return FAILED_PRECONDITION
    And the error's reason is ANGZARR_REASON_COMMAND_REFUSED with refusal_type "io.angzarr.v1.ExpectedSequenceMismatch"
    And the status details carry an ExpectedSequenceMismatch with expected 3 and head 5

  @C-0348
  Scenario: INVALID_ARGUMENT error from server
    When I send a malformed request to the server
    Then is_invalid_argument should return true
    And code should return INVALID_ARGUMENT

  @C-0349
  Scenario: PERMISSION_DENIED error
    Given the client lacks required permissions
    When I attempt a restricted operation
    Then code should return PERMISSION_DENIED
    And the error's code and args should name the access denial

  @C-0350
  Scenario: INTERNAL error from server
    Given the server has an internal error
    When I attempt a client operation
    Then code should return INTERNAL
    And the error should indicate server-side failure

  @C-0351
  Scenario: DEADLINE_EXCEEDED error
    Given the operation times out
    When I attempt a client operation
    Then code should return DEADLINE_EXCEEDED

  # ==========================================================================
  # Error Methods
  # ==========================================================================

  @C-0352
  Scenario: message renders the error from the catalog by its code
    Given any client error
    When I call message() on the error
    Then I should get the catalog's text for the error's code, filled with its args
    And no text in it came from the server

  @C-0353
  Scenario: code returns gRPC code for gRPC errors
    Given a gRPC error with status NOT_FOUND
    When I call code() on the error
    Then I should get Some(NOT_FOUND)

  @C-0354
  Scenario: code returns None for non-gRPC errors
    Given a connection error
    When I call code() on the error
    Then I should get None

  @C-0355
  Scenario: status returns full Status for gRPC errors
    Given a gRPC error with detailed status
    When I call status() on the error
    Then I should get the full gRPC Status
    And I can access the status code, its message (the reason key), and details

  @C-0356
  Scenario: status returns None for non-gRPC errors
    Given an invalid argument error
    When I call status() on the error
    Then I should get None

  # ==========================================================================
  # Boolean Predicates
  # ==========================================================================

  @C-0357
  Scenario: is_not_found for various error types
    Given different error types
    Then NOT_FOUND gRPC error should have is_not_found true
    And connection error should have is_not_found false
    And INTERNAL gRPC error should have is_not_found false

  @C-0358
  Scenario: is_precondition_failed for various error types
    Given different error types
    Then FAILED_PRECONDITION gRPC error should have is_precondition_failed true
    And NOT_FOUND gRPC error should have is_precondition_failed false
    And connection error should have is_precondition_failed false

  @C-0359
  Scenario: is_invalid_argument from both sources
    Given different error types
    Then INVALID_ARGUMENT gRPC error should have is_invalid_argument true
    And ClientError::InvalidArgument should have is_invalid_argument true
    And NOT_FOUND gRPC error should have is_invalid_argument false

  @C-0360
  Scenario: is_connection_error for connection types
    Given different error types
    Then connection error should have is_connection_error true
    And transport error should have is_connection_error true
    And gRPC error should have is_connection_error false

  # ==========================================================================
  # Retry Logic Support
  # ==========================================================================

  @C-0361
  Scenario: Identify retryable errors
    Given various error types
    Then connection errors should be retryable
    And UNAVAILABLE gRPC errors should be retryable
    And RESOURCE_EXHAUSTED should be retryable with backoff
    And INVALID_ARGUMENT should NOT be retryable
    And FAILED_PRECONDITION should NOT be retried as sent: the caller re-reads and decides again

  @C-0362
  Scenario: Extract retry information from error
    Given an error with retry-after metadata
    When I inspect the error details
    Then I should be able to extract retry timing hints

  # ==========================================================================
  # Reason keys by layer
  # ==========================================================================

  @C-0872
  Scenario Outline: A reason key is read as its value's full name, its layer's prefix included
    # Keys are named by layer, never by role (decision 14.104): core's
    # AngzarrReason, the embedded transport's EmbeddedReason, the
    # distributed transport's DistributedReason. The key on the wire is the
    # value's full name, never its number.
    Given a gRPC error with status <status> whose ErrorInfo reason is <key>
    When I inspect the error's reason key
    Then the key is <key>
    And it is the value of enum <enum> in package "<package>"
    And the key's status is the google.rpc.Code <status>

    Examples:
      | key                                          | enum              | package                             | status           |
      | ANGZARR_REASON_HANDLER_UNAVAILABLE           | AngzarrReason     | io.angzarr.v1                       | UNAVAILABLE      |
      | EMBEDDED_REASON_PROBE_INPUT                  | EmbeddedReason    | io.angzarr.transport.embedded.v1    | INVALID_ARGUMENT |
      | DISTRIBUTED_REASON_DEAD_LETTER_NOT_FOUND     | DistributedReason | io.angzarr.transport.distributed.v1 | NOT_FOUND        |

  @C-0873
  Scenario Outline: A key has one string whichever component raises it
    # Who raises a key is in its comment, never in its string (decision
    # 14.104): the router raises ANGZARR_REASON_COMMAND_REFUSED for a
    # handler's refusal, the coordinator for its ExpectedSequenceMismatch.
    Given a command refused by <raiser> with the typed refusal "<refusal>"
    When I inspect the error
    Then its reason key is ANGZARR_REASON_COMMAND_REFUSED with refusal_type "<refusal>"
    And code should return FAILED_PRECONDITION

    Examples:
      | raiser                 | refusal                                 |
      | the handler's router   | orders.v1.OrderClosed                   |
      | the coordinator        | io.angzarr.v1.ExpectedSequenceMismatch  |

  @C-0874
  Scenario: A key's number is never what identifies it
    # The numbers are bookkeeping only (docs/design/reason-keys.md §3).
    Given a gRPC error whose ErrorInfo reason is ANGZARR_REASON_STORE_UNAVAILABLE
    When I compare it with the key ANGZARR_REASON_STORE_UNAVAILABLE
    Then they are the same key, compared by name
    And no number of the key is read from the error

  # ==========================================================================
  # Error Display
  # ==========================================================================

  @C-0363
  Scenario: Error implements Display
    Given any client error
    When I convert the error to string
    Then I should get the error's code followed by its args
    And it carries no rendered text

  @C-0364
  Scenario: Error implements Debug
    Given any client error
    When I debug-format the error
    Then I should get detailed diagnostic information
