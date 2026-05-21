# Allocated: EU-0200 .. EU-0253
# DOC: This file is referenced in docs/docs/examples/aggregates.mdx
#      Update documentation when making changes to player feature scenarios.

# docs:start:feature_overview
Feature: Player aggregate logic
  The Player aggregate manages a player's bankroll and table reservations.
  It's the source of truth for how much money a player has and where it's allocated.
# docs:end:feature_overview

  # Why this aggregate exists:
  # - Players can only sit at tables if they have funds to reserve
  # - Reserved funds are locked until the table session ends
  # - Withdrawals cannot touch reserved funds (preventing mid-game cashout)
  #
  # What breaks if this is wrong:
  # - Players could buy into tables they can't afford
  # - Funds could be double-spent across multiple tables
  # - Players could withdraw chips currently in play
  #
  # Patterns enabled by this aggregate:
  # - Two-phase reservation: ReserveFunds locks money, ReleaseFunds returns it. This
  #   pattern applies anywhere resources must be held pending confirmation (e-commerce
  #   inventory holds, ticket reservations, hotel bookings).
  # - Saga compensation: When JoinTable fails, FundsReserved must be undone via
  #   FundsReleased. The player aggregate handles the Notification and compensates.
  # - Balance tracking with allocation: Available vs reserved funds. Same pattern
  #   applies to inventory (available vs allocated), accounts (balance vs holds).
  #
  # Why poker exercises these patterns well:
  # - Fund reservation is explicit: $500 reserved for Table-1 is clearly separate
  #   from the $500 available balance - easy to verify in tests
  # - Compensation is visible: A rejected JoinTable must release exactly the reserved
  #   amount - the math is obvious and testable
  # - Multiple concurrent reservations: A player at 3 tables has 3 separate holds,
  #   exercising the allocation tracking thoroughly

  # ==========================================================================
  # Player Registration
  # ==========================================================================
  # Players must register before participating. Registration captures identity
  # and distinguishes human players from AI bots (for fair play tracking).

  # docs:start:registration_scenarios
  @EU-0200
  Scenario: Register a new human player
    Given no prior events for the player aggregate
    When I handle a RegisterPlayer command with name "Alice" and email "alice@example.com"
    Then the result is a angzarr_client.proto.examples.v1.PlayerRegistered event
    And the event has a timestamp registered_at
    And the player event has display_name "Alice"
    And the player event has email "alice@example.com"
    And the player event has player_type "HUMAN"
    And the player event has ai_model_id ""

  @EU-0201
  Scenario: Cannot register player twice
    Given a PlayerRegistered event for "Alice"
    When I handle a RegisterPlayer command with name "Alice2" and email "alice@example.com"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player already exists"
  # docs:end:registration_scenarios

  @EU-0202
  Scenario: Register an AI player
    Given no prior events for the player aggregate
    When I handle a RegisterPlayer command with name "Bot1" and email "bot1@example.com" as AI
    Then the result is a angzarr_client.proto.examples.v1.PlayerRegistered event
    And the event has a timestamp registered_at
    And the player event has email "bot1@example.com"
    And the player event has player_type "AI"
    And the player event has ai_model_id "gpt-4"

  # ==========================================================================
  # Deposits - Adding Funds to Bankroll
  # ==========================================================================
  # Deposits increase the player's bankroll. The full amount becomes available
  # for table buy-ins or withdrawals. Deposits are always allowed for registered
  # players (no upper limit by default).

  @EU-0203
  Scenario: Deposit funds to bankroll
    Given a PlayerRegistered event for "Alice"
    When I handle a DepositFunds command with amount 1000
    Then the result is a angzarr_client.proto.examples.v1.FundsDeposited event
    And the event has a timestamp deposited_at
    And the player event has amount 1000
    And the player event has new_balance 1000

  @EU-0204
  Scenario: Multiple deposits accumulate
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 500
    When I handle a DepositFunds command with amount 300
    Then the result is a angzarr_client.proto.examples.v1.FundsDeposited event
    And the event has a timestamp deposited_at
    And the player event has new_balance 800

  @EU-0205
  Scenario: Cannot deposit to non-existent player
    Given no prior events for the player aggregate
    When I handle a DepositFunds command with amount 1000
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  @EU-0206
  Scenario: Cannot deposit zero or negative
    Given a PlayerRegistered event for "Alice"
    And the command cover has domain "player" and correlation_id "deposit-flow-1"
    When I handle a DepositFunds command with amount 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "AMOUNT_MUST_BE_POSITIVE"
    And the rejection field "value" equals "0"
    # The router stamps the originating cover onto every rejection so the
    # caller can trace it back to (domain, correlation_id, root) without
    # threading context through handler signatures.
    And the rejection cover has domain "player" and correlation_id "deposit-flow-1"

  # Boundary: amount=1 must succeed. Catches `if amount <= 0` → `<= 1`
  # which would (wrongly) reject the smallest positive deposit.
  Scenario: Deposit of one chip succeeds at the lower boundary
    Given a PlayerRegistered event for "Alice"
    When I handle a DepositFunds command with amount 1
    Then the result is a angzarr_client.proto.examples.v1.FundsDeposited event
    And the player event has amount 1
    And the player event has new_balance 1

  # ==========================================================================
  # Withdrawals - Removing Funds from Bankroll
  # ==========================================================================
  # Withdrawals remove funds from the player's bankroll. Only AVAILABLE funds
  # can be withdrawn - reserved funds (chips at tables) are locked until
  # the player leaves the table. This prevents mid-session cashouts.

  @EU-0207
  Scenario: Withdraw funds from bankroll
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a WithdrawFunds command with amount 400
    Then the result is a angzarr_client.proto.examples.v1.FundsWithdrawn event
    And the event has a timestamp withdrawn_at
    And the player event has amount 400
    And the player event has new_balance 600

  @EU-0208
  Scenario: Cannot withdraw more than available
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 500
    When I handle a WithdrawFunds command with amount 600
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "INSUFFICIENT_AVAILABLE_BALANCE"
    And the rejection field "requested" equals "600"
    And the rejection field "available" equals "500"

  # Boundary: amount=1 must succeed. Catches `if amount <= 0` → `<= 1`.
  Scenario: Withdraw of one chip succeeds at the lower boundary
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 10
    When I handle a WithdrawFunds command with amount 1
    Then the result is a angzarr_client.proto.examples.v1.FundsWithdrawn event
    And the player event has amount 1
    And the player event has new_balance 9

  @EU-0209
  Scenario: Cannot withdraw with funds reserved
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 800 for table "table-1"
    When I handle a WithdrawFunds command with amount 300
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "INSUFFICIENT_AVAILABLE_BALANCE"
    And the rejection field "requested" equals "300"
    And the rejection field "available" equals "200"

  # ==========================================================================
  # Fund Reservation - Locking Funds for Table Buy-ins
  # ==========================================================================
  # When a player joins a table, funds are RESERVED (not spent). Reserved
  # funds are locked against withdrawal but still belong to the player.
  # This two-phase pattern (reserve → release) enables saga compensation:
  # if the table join fails, the reservation is released atomically.

  # docs:start:reservation_scenario
  @EU-0210
  Scenario: Reserve funds for table buy-in
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ReserveFunds command with amount 500 for table "table-1"
    Then the result is a angzarr_client.proto.examples.v1.FundsReserved event
    And the event has a timestamp reserved_at
    And the player event has amount 500
    And the player event has new_available_balance 500
    And the player event has new_reserved_balance 500
    And the player event has table_root "table-1"

  # Boundary: amount=1 must succeed. Catches `if amount <= 0` → `<= 1`.
  Scenario: Reserve of one chip succeeds at the lower boundary
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 10
    When I handle a ReserveFunds command with amount 1 for table "table-1"
    Then the result is a angzarr_client.proto.examples.v1.FundsReserved event
    And the player event has amount 1
  # docs:end:reservation_scenario

  @EU-0211
  Scenario: Cannot reserve more than available
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 500
    When I handle a ReserveFunds command with amount 600 for table "table-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "INSUFFICIENT_FUNDS"
    And the rejection field "requested" equals "600"
    And the rejection field "available" equals "500"

  @EU-0212
  Scenario: Cannot reserve for same table twice
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 500 for table "table-1"
    When I handle a ReserveFunds command with amount 200 for table "table-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "FUNDS_ALREADY_RESERVED_FOR_TABLE"
    # uuid5(NAMESPACE_OID, "table-1").bytes.hex() — byte-identical across Python and Rust.
    And the rejection field "table_root_hex" equals "eba6a19b488f5e1097a5a34a92553679"

  # ==========================================================================
  # Fund Release - Returning Reserved Funds
  # ==========================================================================
  # When a player leaves a table, their stack (remaining chips) is released
  # back to available balance. The release amount may differ from reservation
  # if the player won or lost chips during play.

  @EU-0213
  Scenario: Release reserved funds back to bankroll
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 500 for table "table-1"
    When I handle a ReleaseFunds command for table "table-1"
    Then the result is a angzarr_client.proto.examples.v1.FundsReleased event
    And the event has a timestamp released_at
    And the player event has amount 500
    And the player event has new_available_balance 1000
    And the player event has new_reserved_balance 0
    And the player event has table_root "table-1"

  @EU-0214
  Scenario: Cannot release non-existent reservation
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ReleaseFunds command for table "table-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "NO_FUNDS_RESERVED_FOR_TABLE"
    # uuid5(NAMESPACE_OID, "table-1").bytes.hex() — byte-identical across Python and Rust.
    And the rejection field "table_root_hex" equals "eba6a19b488f5e1097a5a34a92553679"

  # ==========================================================================
  # State Reconstruction
  # ==========================================================================
  # Player state is rebuilt by replaying all events in order. This verifies
  # that the event sequence correctly captures the full financial history.

  @EU-0215
  Scenario: Rebuild state with deposits and reservations
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 400 for table "table-1"
    When I rebuild the player state
    Then the player state has bankroll 1000
    And the player state has reserved_funds 400
    And the player state has available_balance 600

  # ==========================================================================
  # Compensation Flow - Releasing Reserved Funds
  # ==========================================================================
  # When a table join is rejected or a player leaves, reserved funds must be
  # released back to their available balance. This exercises the compensation
  # pattern where a failed operation triggers a compensating action.

  @EU-0216
  Scenario: Funds released when table join is rejected
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 500
    And a FundsReserved event with amount 200 for table "high-stakes"
    When I handle a ReleaseFunds command for table "high-stakes"
    Then the result is a angzarr_client.proto.examples.v1.FundsReleased event
    And the event has a timestamp released_at
    And the player event has amount 200
    And the player event has new_available_balance 500

  # ==========================================================================
  # Input Validation
  # ==========================================================================
  # Empty-string and non-positive-amount rejections. These fire on malformed
  # commands before any state-level check — verifying the validate() phase.

  @EU-0217
  Scenario: Cannot register with empty display_name
    Given no prior events for the player aggregate
    When I handle a RegisterPlayer command with name "" and email "alice@example.com"
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message equals "display_name is required"

  @EU-0218
  Scenario: Cannot register with empty email
    Given no prior events for the player aggregate
    When I handle a RegisterPlayer command with name "Alice" and email ""
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message equals "email is required"

  @EU-0219
  Scenario: Cannot deposit negative amount
    Given a PlayerRegistered event for "Alice"
    When I handle a DepositFunds command with amount -100
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "AMOUNT_MUST_BE_POSITIVE"
    And the rejection field "value" equals "-100"

  @EU-0220
  Scenario: Cannot withdraw from non-existent player
    Given no prior events for the player aggregate
    When I handle a WithdrawFunds command with amount 100
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  @EU-0221
  Scenario: Cannot withdraw zero amount
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a WithdrawFunds command with amount 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "AMOUNT_MUST_BE_POSITIVE"
    And the rejection field "value" equals "0"

  @EU-0222
  Scenario: Can withdraw the exact available balance
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 600 for table "table-1"
    When I handle a WithdrawFunds command with amount 400
    Then the result is a angzarr_client.proto.examples.v1.FundsWithdrawn event
    And the event has a timestamp withdrawn_at
    And the player event has new_balance 600

  @EU-0223
  Scenario: Cannot reserve for non-existent player
    Given no prior events for the player aggregate
    When I handle a ReserveFunds command with amount 500 for table "table-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  @EU-0224
  Scenario: Cannot reserve zero amount
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ReserveFunds command with amount 0 for table "table-1"
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "AMOUNT_MUST_BE_POSITIVE"
    And the rejection field "value" equals "0"

  @EU-0225
  Scenario: Insufficient funds error beats duplicate-reservation error
    # When a player has BOTH insufficient funds AND a prior reservation for the
    # same table, the insufficient-funds check fires first. Matches Go/Rust order.
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 100
    And a FundsReserved event with amount 50 for table "table-1"
    When I handle a ReserveFunds command with amount 500 for table "table-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the command is rejected with code "INSUFFICIENT_FUNDS"
    And the rejection field "requested" equals "500"
    And the rejection field "available" equals "50"

  @EU-0226
  Scenario: Reserve funds across multiple tables accumulates reserved balance
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 300 for table "table-1"
    When I handle a ReserveFunds command with amount 400 for table "table-2"
    Then the result is a angzarr_client.proto.examples.v1.FundsReserved event
    And the event has a timestamp reserved_at
    And the player event has new_reserved_balance 700
    And the player event has new_available_balance 300

  @EU-0227
  Scenario: Cannot release for non-existent player
    Given no prior events for the player aggregate
    When I handle a ReleaseFunds command for table "table-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  @EU-0228
  Scenario: Cannot release with empty table_root
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ReleaseFunds command for table ""
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message equals "table_root is required"

  @EU-0229
  Scenario: Release only affects the specified table
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 300 for table "table-1"
    And a FundsReserved event with amount 400 for table "table-2"
    When I handle a ReleaseFunds command for table "table-1"
    Then the result is a angzarr_client.proto.examples.v1.FundsReleased event
    And the event has a timestamp released_at
    And the player event has amount 300
    And the player event has new_reserved_balance 400
    # bankroll(1000) - new_reserved(400) = 600; catches bankroll +/- mutation
    And the player event has new_available_balance 600

  # ==========================================================================
  # Fund Transfer - Pot Payouts and Settlement
  # ==========================================================================
  # Transfers credit funds from another player (e.g. winning a pot). The event
  # carries hand_root and reason for audit trail.

  @EU-0230
  Scenario: Transfer funds increases bankroll and records audit metadata
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a TransferFunds command from "other" with amount 500 for hand "hand-1" reason "pot_win"
    Then the result is a angzarr_client.proto.examples.v1.FundsTransferred event
    And the event has a timestamp transferred_at
    And the player event has amount 500
    And the player event has new_balance 1500
    And the player event has reason "pot_win"
    And the player event has from_player_root "other"
    And the player event has hand_root "hand-1"
    And the player event has to_player_root for player "alice@example.com"

  @EU-0231
  Scenario: Cannot transfer to non-existent player
    Given no prior events for the player aggregate
    When I handle a TransferFunds command from "other" with amount 100 for hand "hand-1" reason "pot_win"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  @EU-0232
  Scenario: Cannot transfer zero amount
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a TransferFunds command from "other" with amount 0 for hand "hand-1" reason "pot_win"
    Then the command fails with status "INVALID_ARGUMENT"
    And the command is rejected with code "AMOUNT_MUST_BE_NON_ZERO"

  # ==========================================================================
  # Full Lifecycle Replays
  # ==========================================================================
  # Exercise the state rebuild over realistic event sequences — covers
  # apply_withdrawn/reserved/released/etc. in combination.

  @EU-0233
  Scenario: Reserve and release round-trip restores available balance
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 500 for table "table-1"
    And a FundsReleased event for table "table-1" with amount 500
    When I rebuild the player state
    Then the player state has bankroll 1000
    And the player state has reserved_funds 0
    And the player state has available_balance 1000

  @EU-0234
  Scenario: Rebuild state after deposit, withdraw, reserve, release sequence
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsWithdrawn event with amount 200
    And a FundsReserved event with amount 300 for table "table-1"
    And a FundsReleased event for table "table-1" with amount 300
    When I rebuild the player state
    Then the player state has bankroll 800
    And the player state has reserved_funds 0
    And the player state has available_balance 800

  # ==========================================================================
  # Buy-in Orchestration Commands (handled on the Player aggregate)
  # ==========================================================================
  # The Player-side buy-in flow: InitiateBuyIn reserves funds and emits
  # BuyInRequested; the PM + Table sequence lands, then ConfirmBuyIn or
  # ReleaseBuyIn finalises. The PM-level orchestrator scenarios live in
  # orchestration.feature.

  @EU-0235
  Scenario: InitiateBuyIn emits BuyInRequested with generated reservation_id
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 5000
    When I handle an InitiateBuyIn command for table "table-1" seat 3 amount 500
    Then the result is a angzarr_client.proto.examples.v1.BuyInRequested event
    And the event has a timestamp requested_at
    And the orchestration event has table_root "table-1"
    # Non-zero seat so the seat=cmd.seat assignment can't be silently dropped
    And the orchestration event has seat 3
    And the orchestration event has amount 500
    And the orchestration event has a reservation_id

  @EU-0236
  Scenario: InitiateBuyIn rejects for non-existent player
    Given no prior events for the player aggregate
    When I handle an InitiateBuyIn command for table "table-1" seat 0 amount 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  @EU-0237
  Scenario: InitiateBuyIn rejects when bankroll is insufficient
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 100
    When I handle an InitiateBuyIn command for table "table-1" seat 0 amount 500
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Insufficient funds"

  @EU-0238
  Scenario: ConfirmBuyIn rejects when no reservation is pending
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ConfirmBuyIn command for reservation "res-001"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending buy-in with this reservation_id"

  @EU-0239
  Scenario: ConfirmBuyIn emits BuyInConfirmed with pending table, seat, and amount
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 2000
    And a pending buy-in "res-001" for table "table-1" seat 2 amount 500
    When I handle a ConfirmBuyIn command for reservation "res-001"
    Then the result is a angzarr_client.proto.examples.v1.BuyInConfirmed event
    And the event has a timestamp confirmed_at
    And the orchestration event has reservation_id "res-001"
    And the orchestration event has table_root "table-1"
    And the orchestration event has seat 2
    And the orchestration event has amount 500

  @EU-0240
  Scenario: ReleaseBuyIn emits BuyInReservationReleased with reason
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 2000
    And a pending buy-in "res-001" for table "table-1" seat 0 amount 500
    When I handle a ReleaseBuyIn command for reservation "res-001" reason "timeout"
    Then the result is a angzarr_client.proto.examples.v1.BuyInReservationReleased event
    And the event has a timestamp released_at
    And the orchestration event has reservation_id "res-001"
    And the orchestration event has reason "timeout"

  @EU-0241
  Scenario: Rebuild state after full buy-in lifecycle deducts bankroll and clears pending
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a pending buy-in "res-001" for table "table-1" seat 0 amount 500
    And a BuyInConfirmed event for reservation "res-001" table "table-1"
    When I rebuild the player state
    Then the player state has bankroll 500
    And the player state has reserved_funds 0
    And the player state has no pending buy-in "res-001"

  # ==========================================================================
  # Tournament Registration Orchestration Commands (Player side)
  # ==========================================================================

  @EU-0242
  Scenario: InitiateTournamentRegistration emits RegistrationRequested
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle an InitiateTournamentRegistration command for tournament "trn-1"
    Then the result is a angzarr_client.proto.examples.v1.RegistrationRequested event
    And the event has a timestamp requested_at
    And the orchestration event has tournament_root "trn-1"
    And the orchestration event has a reservation_id
    And the orchestration event has a reservation_id

  @EU-0243
  Scenario: ConfirmRegistrationFee rejects when no registration is pending
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ConfirmRegistrationFee command for reservation "res-001"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending registration with this reservation_id"

  @EU-0244
  Scenario: ConfirmRegistrationFee emits RegistrationFeeConfirmed with tournament and fee
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a pending registration "res-001" for tournament "trn-1" fee 100
    When I handle a ConfirmRegistrationFee command for reservation "res-001"
    Then the result is a angzarr_client.proto.examples.v1.RegistrationFeeConfirmed event
    And the event has a timestamp confirmed_at
    And the orchestration event has reservation_id "res-001"
    And the orchestration event has tournament_root "trn-1"
    And the orchestration event has fee 100

  @EU-0245
  Scenario: ReleaseRegistrationFee emits RegistrationFeeReleased with reason
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a pending registration "res-001" for tournament "trn-1" fee 100
    When I handle a ReleaseRegistrationFee command for reservation "res-001" reason "tournament full"
    Then the result is a angzarr_client.proto.examples.v1.RegistrationFeeReleased event
    And the event has a timestamp released_at
    And the orchestration event has reservation_id "res-001"
    And the orchestration event has reason "tournament full"

  @EU-0246
  Scenario: Rebuild state after full registration lifecycle deducts the fee
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 500
    And a pending registration "res-001" for tournament "trn-1" fee 100
    And a RegistrationFeeConfirmed event for reservation "res-001" tournament "trn-1"
    When I rebuild the player state
    Then the player state has bankroll 400
    And the player state has reserved_funds 0
    And the player state has no pending registration "res-001"

  # ==========================================================================
  # Rebuy Orchestration Commands (Player side)
  # ==========================================================================

  @EU-0247
  Scenario: InitiateRebuy emits RebuyRequested with tournament, table, and seat
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle an InitiateRebuy command for tournament "trn-1" table "table-1" seat 2
    Then the result is a angzarr_client.proto.examples.v1.RebuyRequested event
    And the event has a timestamp requested_at
    And the orchestration event has tournament_root "trn-1"
    And the orchestration event has table_root "table-1"
    And the orchestration event has seat 2
    And the orchestration event has a reservation_id

  @EU-0248
  Scenario: ConfirmRebuyFee rejects when no rebuy is pending
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle a ConfirmRebuyFee command for reservation "res-001"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending rebuy with this reservation_id"

  @EU-0249
  Scenario: ConfirmRebuyFee emits RebuyFeeConfirmed with fee (chips_added populated later by tournament)
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a pending rebuy "res-001" for tournament "trn-1" table "table-1" seat 2 fee 200 chips 500
    When I handle a ConfirmRebuyFee command for reservation "res-001"
    Then the result is a angzarr_client.proto.examples.v1.RebuyFeeConfirmed event
    And the event has a timestamp confirmed_at
    And the orchestration event has reservation_id "res-001"
    And the orchestration event has tournament_root "trn-1"
    And the orchestration event has fee 200
    And the orchestration event has chips_added 0

  @EU-0250
  Scenario: ReleaseRebuyFee emits RebuyFeeReleased with reason
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a pending rebuy "res-001" for tournament "trn-1" table "table-1" seat 2 fee 200 chips 500
    When I handle a ReleaseRebuyFee command for reservation "res-001" reason "denied"
    Then the result is a angzarr_client.proto.examples.v1.RebuyFeeReleased event
    And the event has a timestamp released_at
    And the orchestration event has reservation_id "res-001"
    And the orchestration event has reason "denied"

  @EU-0251
  Scenario: Rebuild state after full rebuy lifecycle deducts the fee
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a pending rebuy "res-001" for tournament "trn-1" table "table-1" seat 2 fee 200 chips 500
    And a RebuyFeeConfirmed event for reservation "res-001"
    When I rebuild the player state
    Then the player state has bankroll 800
    And the player state has reserved_funds 0
    And the player state has no pending rebuy "res-001"

  # ==========================================================================
  # Empty-input precondition rejections
  # ==========================================================================

  Scenario: InitiateBuyIn rejects with empty table_root
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle an InitiateBuyIn command for table "" seat 0 amount 100
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "table_root is required"

  Scenario: InitiateBuyIn rejects with zero amount
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle an InitiateBuyIn command for table "tbl-1" seat 0 amount 0
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message equals "amount must be positive"

  Scenario: InitiateBuyIn rejects with negative amount
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    When I handle an InitiateBuyIn command for table "tbl-1" seat 0 amount -50
    Then the command fails with status "INVALID_ARGUMENT"
    And the error message equals "amount must be positive"

  # Boundary: amount=1 must succeed. Catches `if amount <= 0` → `<= 1`.
  Scenario: InitiateBuyIn at amount 1 succeeds at the lower boundary
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 10
    When I handle an InitiateBuyIn command for table "tbl-1" seat 0 amount 1
    Then the result is a angzarr_client.proto.examples.v1.BuyInRequested event
    And the orchestration event has amount 1

  # Boundary: amount == available_balance must succeed.
  # Catches `if amount > state.available_balance` → `>=` (would reject equal).
  Scenario: InitiateBuyIn with amount equal to available balance succeeds
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 500
    When I handle an InitiateBuyIn command for table "tbl-1" seat 0 amount 500
    Then the result is a angzarr_client.proto.examples.v1.BuyInRequested event
    And the orchestration event has amount 500

  Scenario: ConfirmBuyIn rejects with empty reservation_id
    Given a PlayerRegistered event for "Alice"
    When I handle a ConfirmBuyIn command for reservation ""
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "reservation_id is required"

  Scenario: ReleaseBuyIn rejects with empty reservation_id
    Given a PlayerRegistered event for "Alice"
    When I handle a ReleaseBuyIn command for reservation "" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "reservation_id is required"

  Scenario: ReleaseBuyIn rejects when no reservation is pending
    Given a PlayerRegistered event for "Alice"
    When I handle a ReleaseBuyIn command for reservation "res-001" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending buy-in with this reservation_id"

  Scenario: ConfirmBuyIn rejects against empty reservation state
    Given no prior events for the player aggregate
    When I handle a ConfirmBuyIn command for reservation "res-001"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending buy-in with this reservation_id"

  Scenario: ReleaseBuyIn rejects against empty reservation state
    Given no prior events for the player aggregate
    When I handle a ReleaseBuyIn command for reservation "res-001" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending buy-in with this reservation_id"

  Scenario: InitiateTournamentRegistration rejects with empty tournament_root
    Given a PlayerRegistered event for "Alice"
    When I handle an InitiateTournamentRegistration command for tournament ""
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "tournament_root is required"

  Scenario: InitiateTournamentRegistration rejects for non-existent player
    Given no prior events for the player aggregate
    When I handle an InitiateTournamentRegistration command for tournament "trn-1"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  Scenario: ConfirmRegistrationFee rejects with empty reservation_id
    Given a PlayerRegistered event for "Alice"
    When I handle a ConfirmRegistrationFee command for reservation ""
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "reservation_id is required"

  Scenario: ConfirmRegistrationFee rejects against empty reservation state
    Given no prior events for the player aggregate
    When I handle a ConfirmRegistrationFee command for reservation "res-001"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending registration with this reservation_id"

  Scenario: ReleaseRegistrationFee rejects with empty reservation_id
    Given a PlayerRegistered event for "Alice"
    When I handle a ReleaseRegistrationFee command for reservation "" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "reservation_id is required"

  Scenario: ReleaseRegistrationFee rejects when no registration is pending
    Given a PlayerRegistered event for "Alice"
    When I handle a ReleaseRegistrationFee command for reservation "res-001" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending registration with this reservation_id"

  Scenario: ReleaseRegistrationFee rejects against empty reservation state
    Given no prior events for the player aggregate
    When I handle a ReleaseRegistrationFee command for reservation "res-001" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending registration with this reservation_id"

  Scenario: InitiateRebuy rejects with empty tournament_root
    Given a PlayerRegistered event for "Alice"
    When I handle an InitiateRebuy command for tournament "" table "tbl-1" seat 0
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "tournament_root is required"

  Scenario: InitiateRebuy rejects with empty table_root
    Given a PlayerRegistered event for "Alice"
    When I handle an InitiateRebuy command for tournament "trn-1" table "" seat 0
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "table_root is required"

  Scenario: InitiateRebuy rejects for non-existent player
    Given no prior events for the player aggregate
    When I handle an InitiateRebuy command for tournament "trn-1" table "tbl-1" seat 0
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "Player does not exist"

  Scenario: ConfirmRebuyFee rejects with empty reservation_id
    Given a PlayerRegistered event for "Alice"
    When I handle a ConfirmRebuyFee command for reservation ""
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "reservation_id is required"

  Scenario: ConfirmRebuyFee rejects against empty reservation state
    Given no prior events for the player aggregate
    When I handle a ConfirmRebuyFee command for reservation "res-001"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending rebuy with this reservation_id"

  Scenario: ReleaseRebuyFee rejects with empty reservation_id
    Given a PlayerRegistered event for "Alice"
    When I handle a ReleaseRebuyFee command for reservation "" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "reservation_id is required"

  Scenario: ReleaseRebuyFee rejects when no rebuy is pending
    Given a PlayerRegistered event for "Alice"
    When I handle a ReleaseRebuyFee command for reservation "res-001" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending rebuy with this reservation_id"

  Scenario: ReleaseRebuyFee rejects against empty reservation state
    Given no prior events for the player aggregate
    When I handle a ReleaseRebuyFee command for reservation "res-001" reason "timeout"
    Then the command fails with status "FAILED_PRECONDITION"
    And the error message equals "No pending rebuy with this reservation_id"

  # ==========================================================================
  # Saga Rejection Compensation (#[rejected] handler)
  # ==========================================================================
  # When saga-emitted JoinTable is rejected by the Table aggregate, the
  # framework delivers a RejectionNotification whose rejected_command carries
  # the table_root on its Cover. The player aggregate's rejection handler
  # extracts that root and emits FundsReleased for the matching reservation,
  # compensating the prior FundsReserved. These scenarios pin the observable
  # outcome of the compensation path.

  @EU-0252
  Scenario: JoinTable rejection releases the reserved funds for the target table
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 400 for table "table-1"
    When I handle a JoinTable rejection notification for table "table-1"
    Then the result is a angzarr_client.proto.examples.v1.FundsReleased event
    And the player event has amount 400
    And the player event has new_reserved_balance 0

  @EU-0253
  Scenario: JoinTable rejection emits zero amount when no matching reservation exists
    Given a PlayerRegistered event for "Alice"
    And a FundsDeposited event with amount 1000
    And a FundsReserved event with amount 100 for table "table-1"
    When I handle a JoinTable rejection notification for table "unknown-table"
    Then the result is a angzarr_client.proto.examples.v1.FundsReleased event
    And the player event has amount 0
