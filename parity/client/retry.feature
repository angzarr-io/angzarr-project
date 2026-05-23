# Allocated: C-0127 .. C-0131
#
# Cross-language contract for ExponentialBackoffRetry + the
# CommandRejectedError.precondition_failed factory.
Feature: Retry policy and command rejection factories

  @C-0127
  Scenario: default_retry_policy matches the cross-language spec
    When I obtain the default retry policy
    Then the policy has min_delay 100 ms
    And the policy has max_delay 5000 ms
    And the policy has max_attempts 10
    And the policy has jitter enabled

  @C-0128
  Scenario: ExponentialBackoffRetry execute returns the first ok
    Given an ExponentialBackoffRetry with max_attempts 5 and jitter disabled
    And an operation that fails 2 times then returns 42
    When I execute the operation through the retry policy
    Then the returned value is 42
    And the operation was called 3 times

  @C-0129
  Scenario: ExponentialBackoffRetry execute returns the last error after max_attempts
    Given an ExponentialBackoffRetry with max_attempts 3 and jitter disabled
    And an operation that always fails
    When I execute the operation through the retry policy
    Then the operation was called 3 times
    And the result is an error

  @C-0130
  Scenario: on_retry callback fires between attempts but not after the last
    Given an ExponentialBackoffRetry with max_attempts 3 and jitter disabled
    And an on_retry callback that counts invocations
    And an operation that always fails
    When I execute the operation through the retry policy
    Then the on_retry callback was invoked 2 times

  @C-0131
  Scenario: CommandRejectedError.precondition_failed marks FAILED_PRECONDITION
    When I construct a CommandRejectedError via precondition_failed with reason "bad state"
    Then the error's is_precondition_failed predicate is true
    And the error's is_invalid_argument predicate is false
    And the error's is_not_found predicate is false
