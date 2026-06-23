# Allocated: EU-0260 .. EU-0289

Feature: Reservation lifecycle for buy-ins, registrations, and rebuys
  # Rule: N/A — a reservation is a two-phase fund-commitment record, a cardroom/app concept, not a codified hand rule
  A reservation records one in-flight two-phase fund commitment. Each of the three
  flows — table buy-in, tournament registration, and rebuy — follows the same shape:
  initiating opens a pending record with a generated identifier, confirming closes
  it on success, and releasing closes it on failure.

  # Why this exists:
  # - The reservation is the record of intent that lets a multi-step funding flow
  #   be confirmed or compensated as one coherent lifecycle.
  # - It records intent only. Whether the player can afford the commitment is the
  #   player's own concern, settled when the funds are actually reserved — a buy-in
  #   a player cannot afford fails as an orchestration outcome, not here.
  #
  # Patterns exercised here:
  # - Two-phase commit: initiate (open) -> confirm (settle) | release (compensate).
  #   The same pattern applies to any reserve-then-commit resource flow.

  # ==========================================================================
  # Buy-in reservations
  # ==========================================================================

  @EU-0260
  Scenario: Initiating a buy-in records a pending reservation
    When Alice initiates a buy-in for seat 3 at table "table-1" for 500 chips
    Then a pending buy-in is recorded for seat 3 at table "table-1" for 500 chips
    And the buy-in carries a generated reservation identifier
    And the buy-in is timestamped

  @EU-0261
  Scenario: A buy-in requires a table
    When Alice initiates a buy-in for seat 0 at an empty table name for 100 chips
    Then the buy-in is refused because a table is required

  @EU-0262
  Scenario: A buy-in must be positive
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for 0 chips
    Then the buy-in is refused because the amount must be positive

  @EU-0263
  Scenario: A buy-in cannot be negative
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for -50 chips
    Then the buy-in is refused because the amount must be positive

  @EU-0264
  Scenario: A buy-in of one chip is allowed
    When Alice initiates a buy-in for seat 0 at table "tbl-1" for 1 chip
    Then a pending buy-in is recorded for seat 0 at table "tbl-1" for 1 chip

  @EU-0265
  Scenario: Confirming a buy-in requires a pending reservation
    When Alice's buy-in "res-001" is confirmed
    Then the confirmation is refused because no buy-in with that reservation is pending

  @EU-0266
  Scenario: Confirming a buy-in requires a reservation identifier
    When Alice's buy-in with an empty reservation identifier is confirmed
    Then the confirmation is refused because a reservation identifier is required

  @EU-0267
  Scenario: Confirming a buy-in records the seat, table, and amount
    Given a pending buy-in "res-001" for seat 2 at table "table-1" for 500 chips
    When Alice's buy-in "res-001" is confirmed
    Then the buy-in "res-001" is confirmed for seat 2 at table "table-1" for 500 chips
    And the confirmation is timestamped

  @EU-0268
  Scenario: Releasing a pending buy-in records the reason
    Given a pending buy-in "res-001" for seat 0 at table "table-1" for 500 chips
    When Alice's buy-in "res-001" is released because of "timeout"
    Then the buy-in "res-001" is released with reason "timeout"
    And the release is timestamped

  @EU-0269
  Scenario: Releasing a buy-in requires a reservation identifier
    When Alice's buy-in with an empty reservation identifier is released because of "timeout"
    Then the release is refused because a reservation identifier is required

  @EU-0270
  Scenario: Releasing a buy-in requires a pending reservation
    When Alice's buy-in "res-001" is released because of "timeout"
    Then the release is refused because no buy-in with that reservation is pending

  # ==========================================================================
  # Tournament registration reservations
  # ==========================================================================

  @EU-0271
  Scenario: Initiating a tournament registration records a pending reservation
    When Alice initiates registration for tournament "trn-1"
    Then a pending tournament registration is recorded for tournament "trn-1"
    And the registration carries a generated reservation identifier
    And the registration is timestamped

  @EU-0272
  Scenario: A tournament registration requires a tournament
    When Alice initiates registration for an empty tournament name
    Then the registration is refused because a tournament is required

  @EU-0273
  Scenario: Confirming a registration fee requires a pending registration
    When Alice's tournament registration "res-001" is confirmed
    Then the confirmation is refused because no registration with that reservation is pending

  @EU-0274
  Scenario: Confirming a registration fee requires a reservation identifier
    When Alice's tournament registration with an empty reservation identifier is confirmed
    Then the confirmation is refused because a reservation identifier is required

  @EU-0275
  Scenario: Confirming a registration fee records the tournament and fee
    Given a pending tournament registration "res-001" for tournament "trn-1" with fee 100
    When Alice's tournament registration "res-001" is confirmed
    Then the tournament registration "res-001" is confirmed for tournament "trn-1" with fee 100
    And the confirmation is timestamped

  @EU-0276
  Scenario: Releasing a pending registration records the reason
    Given a pending tournament registration "res-001" for tournament "trn-1" with fee 100
    When Alice's tournament registration "res-001" is released because of "tournament full"
    Then the tournament registration "res-001" is released with reason "tournament full"
    And the release is timestamped

  @EU-0277
  Scenario: Releasing a registration fee requires a reservation identifier
    When Alice's tournament registration with an empty reservation identifier is released because of "timeout"
    Then the release is refused because a reservation identifier is required

  @EU-0278
  Scenario: Releasing a registration fee requires a pending registration
    When Alice's tournament registration "res-001" is released because of "timeout"
    Then the release is refused because no registration with that reservation is pending

  # ==========================================================================
  # Rebuy reservations
  # ==========================================================================

  @EU-0279
  Scenario: Initiating a rebuy records a pending reservation
    When Alice initiates a rebuy for tournament "trn-1" at table "table-1" seat 2
    Then a pending rebuy is recorded for tournament "trn-1" at table "table-1" seat 2
    And the rebuy carries a generated reservation identifier
    And the rebuy is timestamped

  @EU-0280
  Scenario: A rebuy requires a tournament
    When Alice initiates a rebuy for an empty tournament name at table "tbl-1" seat 0
    Then the rebuy is refused because a tournament is required

  @EU-0281
  Scenario: A rebuy requires a table
    When Alice initiates a rebuy for tournament "trn-1" at an empty table name seat 0
    Then the rebuy is refused because a table is required

  @EU-0282
  Scenario: Confirming a rebuy fee requires a pending rebuy
    When Alice's rebuy "res-001" is confirmed
    Then the confirmation is refused because no rebuy with that reservation is pending

  @EU-0283
  Scenario: Confirming a rebuy fee requires a reservation identifier
    When Alice's rebuy with an empty reservation identifier is confirmed
    Then the confirmation is refused because a reservation identifier is required

  @EU-0284
  Scenario: Confirming a rebuy fee records the fee
    Given a pending rebuy "res-001" for tournament "trn-1" at table "table-1" seat 2 with fee 200
    When Alice's rebuy "res-001" is confirmed
    Then the rebuy "res-001" is confirmed for tournament "trn-1" with fee 200
    And the confirmation is timestamped

  @EU-0285
  Scenario: Releasing a pending rebuy records the reason
    Given a pending rebuy "res-001" for tournament "trn-1" at table "table-1" seat 2 with fee 200
    When Alice's rebuy "res-001" is released because of "denied"
    Then the rebuy "res-001" is released with reason "denied"
    And the release is timestamped

  @EU-0286
  Scenario: Releasing a rebuy fee requires a reservation identifier
    When Alice's rebuy with an empty reservation identifier is released because of "timeout"
    Then the release is refused because a reservation identifier is required

  @EU-0287
  Scenario: Releasing a rebuy fee requires a pending rebuy
    When Alice's rebuy "res-001" is released because of "timeout"
    Then the release is refused because no rebuy with that reservation is pending
