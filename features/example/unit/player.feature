# Allocated: EU-0200 .. EU-0253
# DOC: This file is referenced in docs/docs/examples/aggregates.mdx
#      Update documentation when making changes to player feature scenarios.

# docs:start:feature_overview
Feature: Player bankroll and table reservations
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
  Scenario: Reserving funds for a table buy-in
    Given Alice is registered
    And Alice has 1000 chips
    When Alice reserves 500 chips for table "table-1"
    Then Alice has reserved 500 chips for table "table-1"
    And Alice's available balance is 500
    And the reservation is timestamped

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
  Scenario: A player cannot reserve for the same table twice
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 500 chips for table "table-1"
    When Alice reserves 200 chips for table "table-1"
    Then the reservation is refused because Alice has already reserved for that table

  # ==========================================================================
  # Fund Release - Returning Reserved Funds
  # ==========================================================================
  # When a player leaves a table, the player's stack (remaining chips) is
  # released back to the available balance. The release amount may differ
  # from the reservation if the player won or lost chips during play.

  @EU-0213
  Scenario: Releasing reserved funds returns them to the available balance
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has reserved 500 chips for table "table-1"
    When Alice's funds for table "table-1" are released
    Then 500 chips are returned to Alice's available balance
    And Alice's available balance is 1000
    And Alice no longer has a reservation for table "table-1"
    And the release is timestamped

  @EU-0214
  Scenario: A release without a reservation is refused
    Given Alice is registered
    And Alice has 1000 chips
    When Alice's funds for table "table-1" are released
    Then the release is refused because Alice has no reservation for that table

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
  # Buy-in Orchestration (Player side)
  # ==========================================================================
  # The Player-side buy-in flow: initiating a buy-in reserves funds and records
  # a pending reservation; the table flow then either confirms (deducts the
  # bankroll) or releases (returns the funds). The cross-aggregate sequencing
  # lives in orchestration.feature.

  @EU-0235
  Scenario: Initiating a buy-in records a pending reservation
    Given Alice is registered
    And Alice has 5000 chips
    When Alice initiates a buy-in for seat 3 at table "table-1" for 500 chips
    Then a pending buy-in is recorded for seat 3 at table "table-1" for 500 chips
    And the buy-in carries a generated reservation identifier
    And the buy-in is timestamped

  @EU-0236
  Scenario: An unregistered player cannot initiate a buy-in
    Given Alice has not yet registered
    When Alice initiates a buy-in for seat 0 at table "table-1" for 500 chips
    Then the buy-in is refused because Alice does not exist

  @EU-0237
  Scenario: A buy-in requires sufficient bankroll
    Given Alice is registered
    And Alice has 100 chips
    When Alice initiates a buy-in for seat 0 at table "table-1" for 500 chips
    Then the buy-in is refused because Alice has insufficient funds

  @EU-0238
  Scenario: Confirming a buy-in requires a pending reservation
    Given Alice is registered
    And Alice has 1000 chips
    When Alice's buy-in "res-001" is confirmed
    Then the confirmation is refused because no buy-in with that reservation is pending

  @EU-0239
  Scenario: Confirming a buy-in records the seat, table, and amount
    Given Alice is registered
    And Alice has 2000 chips
    And Alice has a pending buy-in "res-001" for seat 2 at table "table-1" for 500 chips
    When Alice's buy-in "res-001" is confirmed
    Then Alice's buy-in "res-001" is confirmed for seat 2 at table "table-1" for 500 chips
    And the confirmation is timestamped

  @EU-0240
  Scenario: Releasing a pending buy-in records the reason
    Given Alice is registered
    And Alice has 2000 chips
    And Alice has a pending buy-in "res-001" for seat 0 at table "table-1" for 500 chips
    When Alice's buy-in "res-001" is released because of "timeout"
    Then Alice's buy-in "res-001" is released with reason "timeout"
    And the release is timestamped

  @EU-0241
  Scenario: After a full buy-in lifecycle, the bankroll is debited and the pending reservation cleared
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has a pending buy-in "res-001" for seat 0 at table "table-1" for 500 chips
    And Alice's buy-in "res-001" has been confirmed
    Then Alice's total bankroll is 500
    And Alice's reserved funds are 0
    And Alice has no pending buy-in "res-001"

  # ==========================================================================
  # Tournament Registration Orchestration (Player side)
  # ==========================================================================

  @EU-0242
  Scenario: Initiating a tournament registration records a pending reservation
    Given Alice is registered
    And Alice has 1000 chips
    When Alice initiates registration for tournament "trn-1"
    Then a pending tournament registration is recorded for tournament "trn-1"
    And the registration carries a generated reservation identifier
    And the registration is timestamped

  @EU-0243
  Scenario: Confirming a registration fee requires a pending registration
    Given Alice is registered
    And Alice has 1000 chips
    When Alice's tournament registration "res-001" is confirmed
    Then the confirmation is refused because no registration with that reservation is pending

  @EU-0244
  Scenario: Confirming a registration fee records the tournament and fee
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has a pending tournament registration "res-001" for tournament "trn-1" with fee 100
    When Alice's tournament registration "res-001" is confirmed
    Then Alice's tournament registration "res-001" is confirmed for tournament "trn-1" with fee 100
    And the confirmation is timestamped

  @EU-0245
  Scenario: Releasing a pending registration records the reason
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has a pending tournament registration "res-001" for tournament "trn-1" with fee 100
    When Alice's tournament registration "res-001" is released because of "tournament full"
    Then Alice's tournament registration "res-001" is released with reason "tournament full"
    And the release is timestamped

  @EU-0246
  Scenario: After a full registration lifecycle, the bankroll is debited the registration fee
    Given Alice is registered
    And Alice has 500 chips
    And Alice has a pending tournament registration "res-001" for tournament "trn-1" with fee 100
    And Alice's tournament registration "res-001" has been confirmed
    Then Alice's total bankroll is 400
    And Alice's reserved funds are 0
    And Alice has no pending tournament registration "res-001"

  # ==========================================================================
  # Rebuy Orchestration (Player side)
  # ==========================================================================

  @EU-0247
  Scenario: Initiating a rebuy records a pending reservation
    Given Alice is registered
    And Alice has 1000 chips
    When Alice initiates a rebuy for tournament "trn-1" at table "table-1" seat 2
    Then a pending rebuy is recorded for tournament "trn-1" at table "table-1" seat 2
    And the rebuy carries a generated reservation identifier
    And the rebuy is timestamped

  @EU-0248
  Scenario: Confirming a rebuy fee requires a pending rebuy
    Given Alice is registered
    And Alice has 1000 chips
    When Alice's rebuy "res-001" is confirmed
    Then the confirmation is refused because no rebuy with that reservation is pending

  @EU-0249
  Scenario: Confirming a rebuy fee records the fee
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has a pending rebuy "res-001" for tournament "trn-1" at table "table-1" seat 2 with fee 200 and 500 chips
    When Alice's rebuy "res-001" is confirmed
    Then Alice's rebuy "res-001" is confirmed for tournament "trn-1" with fee 200
    And the confirmation is timestamped
    # chips_added is populated later by the tournament side, not here

  @EU-0250
  Scenario: Releasing a pending rebuy records the reason
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has a pending rebuy "res-001" for tournament "trn-1" at table "table-1" seat 2 with fee 200 and 500 chips
    When Alice's rebuy "res-001" is released because of "denied"
    Then Alice's rebuy "res-001" is released with reason "denied"
    And the release is timestamped

  @EU-0251
  Scenario: After a full rebuy lifecycle, the bankroll is debited the rebuy fee
    Given Alice is registered
    And Alice has 1000 chips
    And Alice has a pending rebuy "res-001" for tournament "trn-1" at table "table-1" seat 2 with fee 200 and 500 chips
    And Alice's rebuy "res-001" has been confirmed
    Then Alice's total bankroll is 800
    And Alice's reserved funds are 0
    And Alice has no pending rebuy "res-001"

  # ==========================================================================
  # Empty-input precondition rejections
  # ==========================================================================

  Scenario: A buy-in requires a table
    Given Alice is registered
    And Alice has 1000 chips
    When Alice initiates a buy-in for seat 0 at an empty table name for 100 chips
    Then the buy-in is refused because a table is required

  Scenario: A buy-in must be positive
    Given Alice is registered
    And Alice has 1000 chips
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for 0 chips
    Then the buy-in is refused because the amount must be positive

  Scenario: A buy-in cannot be negative
    Given Alice is registered
    And Alice has 1000 chips
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for -50 chips
    Then the buy-in is refused because the amount must be positive

  Scenario: A buy-in of one chip is allowed
    Given Alice is registered
    And Alice has 10 chips
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for 1 chip
    Then a pending buy-in is recorded for seat 0 at table "tbl-1" for 1 chip

  Scenario: A buy-in for exactly the available balance is allowed
    Given Alice is registered
    And Alice has 500 chips
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for 500 chips
    Then a pending buy-in is recorded for seat 0 at table "tbl-1" for 500 chips

  Scenario: Confirming a buy-in requires a reservation identifier
    Given Alice is registered
    When Alice's buy-in with an empty reservation identifier is confirmed
    Then the confirmation is refused because a reservation identifier is required

  Scenario: Releasing a buy-in requires a reservation identifier
    Given Alice is registered
    When Alice's buy-in with an empty reservation identifier is released because of "timeout"
    Then the release is refused because a reservation identifier is required

  Scenario: Releasing a buy-in requires a pending reservation
    Given Alice is registered
    When Alice's buy-in "res-001" is released because of "timeout"
    Then the release is refused because no buy-in with that reservation is pending

  Scenario: An unregistered player cannot confirm a buy-in
    Given Alice has not yet registered
    When Alice's buy-in "res-001" is confirmed
    Then the confirmation is refused because no buy-in with that reservation is pending

  Scenario: An unregistered player cannot release a buy-in
    Given Alice has not yet registered
    When Alice's buy-in "res-001" is released because of "timeout"
    Then the release is refused because no buy-in with that reservation is pending

  Scenario: A tournament registration requires a tournament
    Given Alice is registered
    When Alice initiates registration for an empty tournament name
    Then the registration is refused because a tournament is required

  Scenario: An unregistered player cannot initiate a tournament registration
    Given Alice has not yet registered
    When Alice initiates registration for tournament "trn-1"
    Then the registration is refused because Alice does not exist

  Scenario: Confirming a registration fee requires a reservation identifier
    Given Alice is registered
    When Alice's tournament registration with an empty reservation identifier is confirmed
    Then the confirmation is refused because a reservation identifier is required

  Scenario: An unregistered player cannot confirm a registration fee
    Given Alice has not yet registered
    When Alice's tournament registration "res-001" is confirmed
    Then the confirmation is refused because no registration with that reservation is pending

  Scenario: Releasing a registration fee requires a reservation identifier
    Given Alice is registered
    When Alice's tournament registration with an empty reservation identifier is released because of "timeout"
    Then the release is refused because a reservation identifier is required

  Scenario: Releasing a registration fee requires a pending registration
    Given Alice is registered
    When Alice's tournament registration "res-001" is released because of "timeout"
    Then the release is refused because no registration with that reservation is pending

  Scenario: An unregistered player cannot release a registration fee
    Given Alice has not yet registered
    When Alice's tournament registration "res-001" is released because of "timeout"
    Then the release is refused because no registration with that reservation is pending

  Scenario: A rebuy requires a tournament
    Given Alice is registered
    When Alice initiates a rebuy for an empty tournament name at table "tbl-1" seat 0
    Then the rebuy is refused because a tournament is required

  Scenario: A rebuy requires a table
    Given Alice is registered
    When Alice initiates a rebuy for tournament "trn-1" at an empty table name seat 0
    Then the rebuy is refused because a table is required

  Scenario: An unregistered player cannot initiate a rebuy
    Given Alice has not yet registered
    When Alice initiates a rebuy for tournament "trn-1" at table "tbl-1" seat 0
    Then the rebuy is refused because Alice does not exist

  Scenario: Confirming a rebuy fee requires a reservation identifier
    Given Alice is registered
    When Alice's rebuy with an empty reservation identifier is confirmed
    Then the confirmation is refused because a reservation identifier is required

  Scenario: An unregistered player cannot confirm a rebuy fee
    Given Alice has not yet registered
    When Alice's rebuy "res-001" is confirmed
    Then the confirmation is refused because no rebuy with that reservation is pending

  Scenario: Releasing a rebuy fee requires a reservation identifier
    Given Alice is registered
    When Alice's rebuy with an empty reservation identifier is released because of "timeout"
    Then the release is refused because a reservation identifier is required

  Scenario: Releasing a rebuy fee requires a pending rebuy
    Given Alice is registered
    When Alice's rebuy "res-001" is released because of "timeout"
    Then the release is refused because no rebuy with that reservation is pending

  Scenario: An unregistered player cannot release a rebuy fee
    Given Alice has not yet registered
    When Alice's rebuy "res-001" is released because of "timeout"
    Then the release is refused because no rebuy with that reservation is pending

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
