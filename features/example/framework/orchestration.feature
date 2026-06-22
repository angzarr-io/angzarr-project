# Allocated: EU-0600 .. EU-0617
Feature: Cross-domain orchestration outcomes
  Some business flows require a decision that spans multiple domains. Orchestrators
  check state across multiple domains before committing the outcome, so a player's
  request can be accepted or refused in a single coherent response.

  # ==========================================================================
  # Buy-in coordination - Player and Table together
  # ==========================================================================
  # A buy-in only succeeds when the seat is available at the table and the
  # amount fits the table's buy-in range. The two views are reconciled before
  # the player's funds are committed.

  @EU-0600
  Scenario: A buy-in within the table's range is accepted at an open seat
    Given table "table-1" has seat 0 available with a buy-in range of 200 to 2000
    And Alice has requested a buy-in for seat 0 with amount 500
    When Alice's buy-in is processed
    Then Alice is offered seat 0 at table "table-1"
    And the buy-in is recorded as initiated

  @EU-0601
  Scenario: A buy-in below the table minimum is refused
    Given table "table-1" has seat 0 available with a buy-in range of 200 to 2000
    And Alice has requested a buy-in for seat 0 with amount 100
    When Alice's buy-in is processed
    Then Alice is not offered a seat
    And the buy-in is refused because the amount is outside the allowed range

  @EU-0602
  Scenario: A buy-in above the table maximum is refused
    Given table "table-1" has seat 0 available with a buy-in range of 200 to 2000
    And Alice has requested a buy-in for seat 0 with amount 5000
    When Alice's buy-in is processed
    Then Alice is not offered a seat
    And the buy-in is refused because the amount is outside the allowed range

  @EU-0603
  Scenario: A buy-in for an occupied seat is refused
    Given table "table-1" has seat 0 occupied by another player
    And Alice has requested a buy-in for seat 0 with amount 500
    When Alice's buy-in is processed
    Then Alice is not offered a seat
    And the buy-in is refused because the seat is already taken

  @EU-0604
  Scenario: A buy-in at a full table is refused
    Given table "table-1" is full with 9 players
    And Alice has requested a buy-in for any seat with amount 500
    When Alice's buy-in is processed
    Then Alice is not offered a seat
    And the buy-in is refused because the table is full

  @EU-0605
  Scenario: A buy-in is completed once the player is seated
    Given Alice has a pending buy-in at table "table-1"
    When Alice is seated at the table
    Then Alice's buy-in is confirmed
    And the buy-in is recorded as completed

  @EU-0606
  Scenario: A buy-in releases the player's funds when seating is refused by the table
    Given Alice has a pending buy-in at table "table-1"
    When the table refuses to seat Alice
    Then Alice's reserved buy-in funds are released
    And the buy-in is refused because seating was rejected

  # ==========================================================================
  # Tournament registration coordination - Player and Tournament together
  # ==========================================================================
  # A tournament registration only succeeds when the tournament is open and has
  # capacity. The tournament's status is reconciled with the player's request
  # before the entry fee is committed.

  @EU-0607
  Scenario: A registration into an open tournament with capacity is accepted
    Given tournament "trn-1" is open for registration with capacity available
    And Alice has requested registration with fee 1000
    When Alice's registration is processed
    Then Alice is enrolled in tournament "trn-1"
    And the registration is recorded as initiated

  @EU-0608
  Scenario: A registration into a full tournament is refused
    Given tournament "trn-1" is full
    And Alice has requested registration with fee 1000
    When Alice's registration is processed
    Then Alice is not enrolled
    And the registration is refused because registration is closed

  @EU-0609
  Scenario: A registration into a tournament with registration closed is refused
    Given tournament "trn-1" has registration closed
    And Alice has requested registration with fee 1000
    When Alice's registration is processed
    Then Alice is not enrolled
    And the registration is refused because registration is closed

  @EU-0610
  Scenario: A registration is completed once the player is enrolled
    Given Alice has a pending registration for tournament "trn-1"
    When Alice is enrolled in the tournament
    Then Alice's registration fee is confirmed
    And the registration is recorded as completed

  @EU-0611
  Scenario: A registration releases the player's fee when enrollment is refused by the tournament
    Given Alice has a pending registration for tournament "trn-1"
    When the tournament refuses to enroll Alice
    Then Alice's reserved registration fee is released
    And the registration is refused because enrollment was rejected

  # ==========================================================================
  # Rebuy coordination - Player, Tournament, and Table together
  # ==========================================================================
  # A rebuy is the most cross-cutting flow: the tournament must be in its rebuy
  # window, the player must be seated at a table, and the player must be
  # eligible. All three views are reconciled before the fee is committed.

  @EU-0612
  Scenario: A rebuy during the rebuy window for a seated, eligible player is accepted
    Given tournament "trn-1" is in its rebuy window and Alice is eligible
    And Alice is seated at table "table-1" in seat 2
    And Alice has requested a rebuy for amount 1000
    When Alice's rebuy is processed
    Then Alice's rebuy is submitted to tournament "trn-1"
    And the rebuy is recorded as initiated

  @EU-0613
  Scenario: A rebuy outside the rebuy window is refused
    Given tournament "trn-1" has its rebuy window closed
    And Alice is seated at table "table-1" in seat 2
    And Alice has requested a rebuy for amount 1000
    When Alice's rebuy is processed
    Then Alice's rebuy is not submitted
    And the rebuy is refused because the tournament is not currently running

  @EU-0614
  Scenario: A rebuy for a player who is not seated is refused
    Given tournament "trn-1" is in its rebuy window and Alice is eligible
    And Alice is not seated at any table in the tournament
    And Alice has requested a rebuy for amount 1000
    When Alice's rebuy is processed
    Then Alice's rebuy is not submitted
    And the rebuy is refused because Alice is not seated

  @EU-0615
  Scenario: Once a rebuy is approved, chips are added at the table
    Given Alice has a pending rebuy at table "table-1" in tournament "trn-1"
    When the tournament approves Alice's rebuy
    Then Alice's rebuy chips are added at the table

  @EU-0616
  Scenario: A rebuy is completed once the chips are at the table
    Given Alice's rebuy chips have been added at table "table-1" in tournament "trn-1"
    When the chips are settled at the table
    Then Alice's rebuy fee is confirmed
    And the rebuy is recorded as completed

  @EU-0617
  Scenario: A rebuy releases the player's fee when the tournament denies it
    Given Alice has a pending rebuy at table "table-1" in tournament "trn-1"
    When the tournament denies Alice's rebuy
    Then Alice's reserved rebuy fee is released
    And the rebuy is refused because the rebuy was denied
