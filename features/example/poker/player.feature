# Allocated: EU-0200 .. EU-0253
# DOC: This file is referenced in docs/docs/examples/aggregates.mdx
#      Update documentation when making changes to player feature scenarios.

# docs:start:feature_overview
Feature: Player bankroll and table reservations
  # Rule: N/A — player bankroll/registration is a cardroom/app concept, not a codified hand rule
  A player manages a bankroll and table reservations. The player is the source
  of truth for how much money the player has and where it is allocated.
# docs:end:feature_overview

  # Why this exists:
  # - Players can only sit at tables if they have funds to reserve
  # - Reserved funds are locked until the table session ends
  # - Withdrawals cannot touch reserved funds (preventing mid-game cashout)
  #
  # What breaks if this is wrong:
  # - Players could buy into tables they can't afford
  # - Funds could be double-spent across multiple tables
  # - Players could withdraw chips currently in play
  #
  # Patterns exercised here:
  # - Two-phase reservation: reserving locks money, releasing returns it. This
  #   pattern applies anywhere resources must be held pending confirmation
  #   (e-commerce inventory holds, ticket reservations, hotel bookings).
  # - Compensation: when a table join is rejected, the reservation must be
  #   undone exactly.
  # - Balance tracking with allocation: available vs reserved funds. Same
  #   pattern applies to inventory (available vs allocated), bank accounts
  #   (balance vs holds).
  #
  # Why poker exercises these patterns well:
  # - Fund reservation is explicit: 500 chips reserved for Table-1 is clearly
  #   separate from the 500 available - easy to verify in tests
  # - Compensation is visible: a rejected table join must release exactly the
  #   reserved amount - the math is obvious and testable
  # - Multiple concurrent reservations: a player at 3 tables has 3 separate
  #   holds, exercising the allocation tracking thoroughly

  # ==========================================================================
  # Player Registration
  # ==========================================================================
  # Players must register before participating. Registration captures identity
  # and distinguishes human players from AI bots (for fair play tracking).

  # docs:start:registration_scenarios
  @EU-0200
  Scenario: A new human player registers
    Given Alice has not yet registered
    When Alice registers with email "alice@example.com"
    Then Alice is registered as a human player
    And Alice's registration is timestamped

  @EU-0201
  Scenario: A player cannot register twice
    Given Alice is registered
    When Alice tries to register again with email "alice@example.com"
    Then registration is refused because Alice already exists
  # docs:end:registration_scenarios

  @EU-0202
  Scenario: An AI player registers
    Given Bot1 has not yet registered
    When Bot1 registers as an AI with email "bot1@example.com" and model "gpt-4"
    Then Bot1 is registered as an AI player using the "gpt-4" model
    And Bot1's registration is timestamped

  # ==========================================================================
  # Deposits - Adding Funds to Bankroll
  # ==========================================================================
  # Deposits increase the player's bankroll. The full amount becomes available
  # for table buy-ins or withdrawals. Deposits are always allowed for registered
  # players (no upper limit by default).

  @EU-0203
  Scenario: Depositing funds increases the bankroll
    Given Alice is registered
    When Alice deposits 1000 chips
    Then Alice's balance is 1000
    And the deposit is timestamped

  @EU-0204
  Scenario: Successive deposits accumulate
    Given Alice is registered
    And Alice has 500 chips
    When Alice deposits 300 chips
    Then Alice's balance is 800

  @EU-0205
  Scenario: An unregistered player cannot deposit
    Given Alice has not yet registered
    When Alice deposits 1000 chips
    Then the deposit is refused because Alice does not exist

  @EU-0206
  Scenario: A deposit must be positive
    Given Alice is registered
    When Alice deposits 0 chips
    Then the deposit is refused because the amount must be positive

  Scenario: A deposit of one chip is allowed
    Given Alice is registered
    When Alice deposits 1 chip
    Then Alice's balance is 1

  # ==========================================================================
  # Withdrawals - Removing Funds from Bankroll
  # ==========================================================================
  # Withdrawals remove funds from the player's bankroll. Only AVAILABLE funds
  # can be withdrawn - reserved funds (chips at tables) are locked until
  # the player leaves the table. This prevents mid-session cashouts.

  @EU-0207
  Scenario: Withdrawing funds reduces the bankroll
    Given Alice is registered
    And Alice has 1000 chips
    When Alice withdraws 400 chips
    Then Alice's balance is 600
    And the withdrawal is timestamped

  @EU-0208
  Scenario: A player cannot withdraw more than the available balance
    Given Alice is registered
    And Alice has 500 chips
    When Alice withdraws 600 chips
    Then the withdrawal is refused because Alice has 500 available but requested 600

  Scenario: A withdrawal of one chip is allowed
    Given Alice is registered
    And Alice has 10 chips
    When Alice withdraws 1 chip
    Then Alice's balance is 9

  @EU-0209
  Scenario: Reserved funds cannot be withdrawn
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 800 chips for table "table-1"
    When Alice withdraws 300 chips
    Then the withdrawal is refused because Alice has 200 available but requested 300

  # ==========================================================================
  # Fund Reservation - Locking Funds for Table Buy-ins
  # ==========================================================================
  # When a player joins a table, funds are RESERVED (not spent). Reserved
  # funds are locked against withdrawal but still belong to the player.
  # This two-phase pattern (reserve -> release) enables compensation:
  # if the table join fails, the reservation is released atomically.

  # docs:start:reservation_scenario
  @EU-0210
  Scenario: Reserve funds for table buy-in
    Given Alice is registered
    And Alice has 1000 chips
    When Alice reserves 500 chips for table "table-1"
    Then Alice has reserved 500 chips for table "table-1"
    And the reservation is timestamped
    And Alice's reserved funds are 500
    And Alice's available balance is 500

  Scenario: A reservation of one chip is allowed
    Given Alice is registered
    And Alice has 10 chips
    When Alice reserves 1 chip for table "table-1"
    Then Alice has reserved 1 chip for table "table-1"
  # docs:end:reservation_scenario

  @EU-0211
  Scenario: A reservation cannot exceed the available balance
    Given Alice is registered
    And Alice has 500 chips
    When Alice reserves 600 chips for table "table-1"
    Then the reservation is refused because Alice has 500 available but requested 600

  @EU-0212
  Scenario: Cannot reserve for the same table twice
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 500 chips for table "table-1"
    When Alice reserves 200 chips for table "table-1"
    Then the reservation is refused because Alice already has funds reserved for table "table-1"

  # ==========================================================================
  # Fund Release - Returning Reserved Funds
  # ==========================================================================
  # When a player leaves a table, the player's stack (remaining chips) is
  # released back to the available balance. The release amount may differ
  # from the reservation if the player won or lost chips during play.

  @EU-0213
  Scenario: Release reserved funds back to bankroll
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 500 chips for table "table-1"
    When Alice's funds for table "table-1" are released
    Then 500 chips are returned to Alice's available balance
    And the release is timestamped
    And Alice's reserved funds are 0
    And Alice's available balance is 1000

  @EU-0214
  Scenario: Cannot release a non-existent reservation
    Given Alice is registered
    And Alice has 1000 chips
    When Alice's funds for table "table-1" are released
    Then the release is refused because Alice has no funds reserved for table "table-1"

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # The player's balances must be derivable from the player's history. This
  # verifies that the recorded events together capture the full financial
  # position.

  @EU-0215
  Scenario: A player's balances follow from deposits and reservations
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 400 chips for table "table-1"
    Then Alice's total bankroll is 1000
    And Alice's reserved funds are 400
    And Alice's available balance is 600

  # ==========================================================================
  # Compensation Flow - Releasing Reserved Funds
  # ==========================================================================
  # When a table join is rejected or a player leaves, reserved funds must be
  # returned to their available balance. This exercises the compensation
  # pattern where a failed operation triggers a compensating action.

  @EU-0216
  Scenario: Reserved funds are returned when a table join is rejected
    Given Alice is registered
    And Alice has 500 chips
    And Alice has reserved 200 chips for table "high-stakes"
    When Alice's funds for table "high-stakes" are released
    Then 200 chips are returned to Alice's available balance
    And Alice's available balance is 500

  # ==========================================================================
  # Input Validation
  # ==========================================================================
  # Empty inputs and non-positive amounts are refused before any state-level
  # check.

  @EU-0217
  Scenario: A player cannot register with an empty name
    Given Alice has not yet registered
    When Alice registers with an empty name and email "alice@example.com"
    Then registration is refused because a name is required

  @EU-0218
  Scenario: A player cannot register with an empty email
    Given Alice has not yet registered
    When Alice registers with an empty email
    Then registration is refused because an email is required

  @EU-0219
  Scenario: A deposit cannot be negative
    Given Alice is registered
    When Alice deposits -100 chips
    Then the deposit is refused because the amount must be positive

  @EU-0220
  Scenario: An unregistered player cannot withdraw
    Given Alice has not yet registered
    When Alice withdraws 100 chips
    Then the withdrawal is refused because Alice does not exist

  @EU-0221
  Scenario: A withdrawal must be positive
    Given Alice is registered
    And Alice has 1000 chips
    When Alice withdraws 0 chips
    Then the withdrawal is refused because the amount must be positive

  @EU-0222
  Scenario: A player can withdraw exactly the available balance
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 600 chips for table "table-1"
    When Alice withdraws 400 chips
    Then Alice's balance is 600

  @EU-0223
  Scenario: An unregistered player cannot reserve
    Given Alice has not yet registered
    When Alice reserves 500 chips for table "table-1"
    Then the reservation is refused because Alice does not exist

  @EU-0224
  Scenario: A reservation must be positive
    Given Alice is registered
    And Alice has 1000 chips
    When Alice reserves 0 chips for table "table-1"
    Then the reservation is refused because the amount must be positive

  @EU-0225
  Scenario: Insufficient-funds is reported ahead of duplicate-reservation
    Given Alice is registered
    And Alice has 100 chips
    And Alice has reserved 50 chips for table "table-1"
    When Alice reserves 500 chips for table "table-1"
    Then the reservation is refused because Alice has 50 available but requested 500

  @EU-0226
  Scenario: Reservations at multiple tables accumulate
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 300 chips for table "table-1"
    When Alice reserves 400 chips for table "table-2"
    Then Alice's reserved funds are 700
    And Alice's available balance is 300

  @EU-0227
  Scenario: An unregistered player cannot release
    Given Alice has not yet registered
    When Alice's funds for table "table-1" are released
    Then the release is refused because Alice does not exist

  @EU-0228
  Scenario: A release must name a table
    Given Alice is registered
    And Alice has 1000 chips
    When Alice's funds for an empty table name are released
    Then the release is refused because a table is required

  @EU-0229
  Scenario: A release only affects the named table
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 300 chips for table "table-1"
    And Alice has reserved 400 chips for table "table-2"
    When Alice's funds for table "table-1" are released
    Then 300 chips are returned to Alice's available balance
    And Alice's reserved funds are 400
    And Alice's available balance is 600

  # ==========================================================================
  # Fund Transfer - Pot Payouts and Settlement
  # ==========================================================================
  # Transfers credit funds from another player (e.g. winning a pot). The
  # transfer records the source player, hand, and reason for the audit trail.

  @EU-0230
  Scenario: A transfer credits the recipient and is annotated for audit
    Given Alice is registered
    And Alice has 1000 chips
    When 500 chips are transferred to Alice from "other" for hand "hand-1" with reason "pot_win"
    Then Alice's balance is 1500
    And the transfer is recorded as coming from "other" for hand "hand-1" with reason "pot_win"
    And the transfer is timestamped

  @EU-0231
  Scenario: A transfer to an unregistered player is refused
    Given Alice has not yet registered
    When 100 chips are transferred to Alice from "other" for hand "hand-1" with reason "pot_win"
    Then the transfer is refused because Alice does not exist

  @EU-0232
  Scenario: A transfer of zero is refused
    Given Alice is registered
    And Alice has 1000 chips
    When 0 chips are transferred to Alice from "other" for hand "hand-1" with reason "pot_win"
    Then the transfer is refused because the amount must be non-zero

  # ==========================================================================
  # Full Lifecycle Replays
  # ==========================================================================
  # Realistic event sequences that exercise the full balance projection over
  # combined deposits, withdrawals, reservations, and releases.

  @EU-0233
  Scenario: A reserve-then-release round-trip restores the available balance
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 500 chips for table "table-1"
    And Alice's reservation for table "table-1" has been released in full
    Then Alice's total bankroll is 1000
    And Alice's reserved funds are 0
    And Alice's available balance is 1000

  @EU-0234
  Scenario: Balances after deposit, withdrawal, reserve, release
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has withdrawn 200 chips
    And Alice has reserved 300 chips for table "table-1"
    And Alice's reservation for table "table-1" has been released in full
    Then Alice's total bankroll is 800
    And Alice's reserved funds are 0
    And Alice's available balance is 800

  # ==========================================================================
  # Compensation on Table-Join Rejection
  # ==========================================================================
  # When a table join is rejected, the player's reservation for that table
  # must be released - the exact reserved amount. If no reservation exists
  # for the rejecting table, the compensation is a no-op.

  @EU-0252
  Scenario: A rejected table join releases the reservation for the target table
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 400 chips for table "table-1"
    When Alice's join attempt at table "table-1" is rejected
    Then 400 chips are returned to Alice's available balance
    And Alice no longer has a reservation for table "table-1"

  @EU-0253
  Scenario: A rejected table join with no matching reservation is a no-op release
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 100 chips for table "table-1"
    When Alice's join attempt at table "unknown-table" is rejected
    Then no chips are returned to Alice's available balance
