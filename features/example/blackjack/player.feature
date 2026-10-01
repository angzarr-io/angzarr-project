# Allocated: EU-1400 .. EU-1439
Feature: Player wallet
  The player's wallet holds every chip that is not on a table. Money reaches
  a table in two steps: first part of the bankroll is held for a specific
  table, then the hold is spent once the table has the chips. A hold that
  does not go through is released and nothing has moved. Chips come back
  from a table only when the player cashes out.

  Why this matters:
  - a player can never buy in or top up with money they do not have
  - money on its way to a table can be neither withdrawn nor spent twice
  - every transfer is safe to repeat, because the services that ask for it
    may deliver the same request more than once
  - the wallet always explains its own balance: deposits minus withdrawals,
    minus what went to tables, plus what came back (ledger rule L1)

  Amounts are chips. "Available" is the bankroll minus open holds.

  # ==========================================================================
  # Identity
  # ==========================================================================
  # Rule: N/A — wallet identity is an application concept, not a house rule

  @EU-1400
  Scenario: Registering opens an empty wallet
    Given player "Alice" has not registered
    When "Alice" registers with display name "Alice" and email "alice@example.com"
    Then "Alice" is registered as "Alice"
    And "Alice" has a bankroll of 0 with 0 available

  @EU-1401
  Scenario: A player cannot register twice
    Given player "Alice" is registered
    When "Alice" registers with display name "Alice" and email "alice@example.com"
    Then the registration is refused because "Alice" already exists

  @EU-1402
  Scenario: A player needs a display name
    Given player "Alice" has not registered
    When "Alice" registers with display name "" and email "alice@example.com"
    Then the registration is refused because a display name is required

  @EU-1403
  Scenario: A player can change their display name
    Given player "Alice" is registered
    When "Alice" changes her display name to "Ace"
    Then "Alice" is registered as "Ace"

  @EU-1404
  Scenario: An unregistered player cannot change their profile
    Given player "Alice" has not registered
    When "Alice" changes her display name to "Ace"
    Then the change is refused because "Alice" is not registered

  @EU-1405
  Scenario: A player migrated from the old system keeps their identity but no money
    # Imports are written without triggering any other service; see the
    # cluster scenario for what that means downstream.
    Given player "Carol" has not registered
    When "Carol" is imported from the old system as "Carol" with email "carol@example.com" and legacy id "L-77"
    Then "Carol" is registered as "Carol"
    And "Carol" has a bankroll of 0 with 0 available

  @EU-1406
  Scenario: An existing player cannot be imported over
    Given player "Alice" is registered
    When "Alice" is imported from the old system as "Alice" with email "alice@example.com" and legacy id "L-1"
    Then the import is refused because "Alice" already exists

  # ==========================================================================
  # Deposits and withdrawals
  # ==========================================================================
  # Rule: L1

  @EU-1407
  Scenario: Deposits increase the bankroll
    Given player "Alice" is registered
    When "Alice" deposits 1000
    Then "Alice" has a bankroll of 1000 with 1000 available
    And the wallet of "Alice" balances

  @EU-1408
  Scenario Outline: A deposit must be positive
    Given player "Alice" is registered
    When "Alice" deposits <amount>
    Then the deposit is refused because the amount must be positive

    Examples:
      | amount |
      | 0      |
      | -50    |

  @EU-1409
  Scenario: An unregistered player cannot deposit
    Given player "Alice" has not registered
    When "Alice" deposits 1000
    Then the deposit is refused because "Alice" is not registered

  @EU-1410
  Scenario: Withdrawals decrease the bankroll
    Given player "Alice" is registered with 1000 deposited
    When "Alice" withdraws 400
    Then "Alice" has a bankroll of 600 with 600 available
    And the wallet of "Alice" balances

  @EU-1411
  Scenario: A withdrawal cannot touch held funds
    Given player "Alice" is registered with 1000 deposited
    And 700 of "Alice"'s funds are held for a buy-in at table "Main"
    When "Alice" withdraws 400
    Then the withdrawal is refused because "Alice" has only 300 available
    And "Alice" has a bankroll of 1000 with 300 available

  @EU-1412
  Scenario: A withdrawal must be positive
    Given player "Alice" is registered with 1000 deposited
    When "Alice" withdraws 0
    Then the withdrawal is refused because the amount must be positive

  # ==========================================================================
  # Buy-in holds (requested by the buy-in process)
  # ==========================================================================
  # Rule: L1

  @EU-1413
  Scenario: Holding funds reduces what is available but not the bankroll
    Given player "Alice" is registered with 1000 deposited
    When 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    Then "Alice" has a bankroll of 1000 with 500 available
    And "Alice" has an open hold "B1" of 500 for table "Main"
    And the wallet of "Alice" balances

  @EU-1414
  Scenario: A hold larger than the available balance is refused
    Given player "Alice" is registered with 1000 deposited
    And 700 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    When 500 of "Alice"'s funds are held for buy-in "B2" at table "Side"
    Then the hold is refused because "Alice" has only 300 available
    And "Alice" has no hold "B2"

  @EU-1415
  Scenario: Repeating an identical hold changes nothing
    # The buy-in process may deliver the same request twice.
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    When 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    Then the request succeeds without any change to the wallet
    And "Alice" has a bankroll of 1000 with 500 available

  @EU-1416
  Scenario: Reusing a hold for a different amount is refused
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    When 300 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    Then the hold is refused because buy-in "B1" is already held for a different amount

  @EU-1417
  Scenario: Capturing a hold spends it
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    When the hold "B1" of "Alice" is captured
    Then "Alice" has a bankroll of 500 with 500 available
    And "Alice" has no open hold "B1"
    And "Alice" has sent 500 to tables in total
    And the wallet of "Alice" balances

  @EU-1418
  Scenario: Capturing the same hold again changes nothing
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds were held for buy-in "B1" at table "Main" and captured
    When the hold "B1" of "Alice" is captured
    Then the request succeeds without any change to the wallet
    And "Alice" has a bankroll of 500 with 500 available

  @EU-1419
  Scenario: A hold that was never placed cannot be captured
    Given player "Alice" is registered with 1000 deposited
    When the hold "B9" of "Alice" is captured
    Then the capture is refused because there is no hold "B9"

  @EU-1420
  Scenario: Releasing a hold restores what is available
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    When the hold "B1" of "Alice" is released because "the seat was refused"
    Then "Alice" has a bankroll of 1000 with 1000 available
    And "Alice" has no open hold "B1"
    And the wallet of "Alice" balances

  @EU-1421
  Scenario: Releasing a hold that is already closed changes nothing
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds were held for buy-in "B1" at table "Main" and released
    When the hold "B1" of "Alice" is released because "the seat was refused"
    Then the request succeeds without any change to the wallet

  @EU-1422
  Scenario: A captured hold cannot be held again
    # A late duplicate of the original request must not earmark the money a
    # second time.
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds were held for buy-in "B1" at table "Main" and captured
    When 500 of "Alice"'s funds are held for buy-in "B1" at table "Main"
    Then the request succeeds without any change to the wallet
    And "Alice" has a bankroll of 500 with 500 available

  # ==========================================================================
  # Top-ups (requested by the player, carried out by the table)
  # ==========================================================================
  # Rule: L1

  @EU-1423
  Scenario: Requesting a top-up holds the money for the table
    Given player "Alice" is registered with 1000 deposited
    When "Alice" asks to top up 200 at table "Main" with request "T1"
    Then "Alice" has a bankroll of 1000 with 800 available
    And "Alice" has an open hold "T1" of 200 for table "Main"
    And a top-up of 200 for table "Main" is requested

  @EU-1424
  Scenario: Repeating a top-up request changes nothing
    Given player "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    When "Alice" asks to top up 200 at table "Main" with request "T1"
    Then the request succeeds without any change to the wallet

  @EU-1425
  Scenario: A top-up beyond the available balance is refused
    Given player "Alice" is registered with 100 deposited
    When "Alice" asks to top up 200 at table "Main" with request "T1"
    Then the top-up is refused because "Alice" has only 100 available

  @EU-1426
  Scenario: A top-up the table refuses releases its hold
    # The table refuses chips while the player has a bet in play; the wallet
    # learns of the refusal and undoes its own half of the transfer.
    Given player "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    When table "Main" refuses top-up "T1" because a wager is in play
    Then the top-up "T1" is refused with reason "WAGER_IN_PLAY"
    And "Alice" has a bankroll of 1000 with 1000 available
    And the wallet of "Alice" balances

  @EU-1427
  Scenario: A refusal for a top-up that is already settled changes nothing
    Given player "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    And table "Main" settled top-up "T1" of 200
    When table "Main" refuses top-up "T1" because a wager is in play
    Then the refusal changes nothing in the wallet
    And "Alice" has a bankroll of 800 with 800 available

  @EU-1428
  Scenario: A settled top-up spends its hold
    Given player "Alice" is registered with 1000 deposited
    And "Alice" asked to top up 200 at table "Main" with request "T1"
    When table "Main" reports top-up "T1" of 200 settled
    Then "Alice" has a bankroll of 800 with 800 available
    And "Alice" has no open hold "T1"
    And "Alice" has sent 200 to tables in total
    And the wallet of "Alice" balances

  @EU-1429
  Scenario: A settlement that matches no hold is recorded and flagged
    # The table's report is a fact: the wallet cannot refuse it, only flag it
    # for someone to look at.
    Given player "Alice" is registered with 1000 deposited
    When table "Main" reports top-up "T9" of 200 settled
    Then the settlement is recorded and flagged because it matches no open hold
    And "Alice" has a bankroll of 800 with 800 available
    And "Alice" has sent 200 to tables in total

  @EU-1430
  Scenario: A cash-out from a table raises the bankroll
    Given player "Alice" is registered with 1000 deposited
    And 500 of "Alice"'s funds were held for buy-in "B1" at table "Main" and captured
    When table "Main" reports that "Alice" cashed out 640
    Then "Alice" has a bankroll of 1140 with 1140 available
    And "Alice" has received 640 from tables in total
    And the wallet of "Alice" balances

  # ==========================================================================
  # Round history and loyalty (reported by the table after each round)
  # ==========================================================================
  # Rule: N/A — loyalty and round history are application concepts

  @EU-1431
  Scenario: A player can join the loyalty programme
    Given player "Alice" is registered
    When "Alice" enrolls in the loyalty programme
    Then "Alice" is a loyalty member with 0 points

  @EU-1432
  Scenario: Loyalty points are awarded to members
    Given player "Alice" is registered and enrolled in the loyalty programme
    When "Alice" is awarded 20 loyalty points for round 1 at table "Main"
    Then "Alice" is a loyalty member with 20 points

  @EU-1433
  Scenario: Loyalty points cannot be awarded to a player who never enrolled
    Given player "Bob" is registered
    When "Bob" is awarded 20 loyalty points for round 1 at table "Main"
    Then the award is refused because "Bob" is not a loyalty member

  @EU-1434
  Scenario: The same round's points are awarded only once
    Given player "Alice" is registered and enrolled in the loyalty programme
    And "Alice" was awarded 20 loyalty points for round 1 at table "Main"
    When "Alice" is awarded 20 loyalty points for round 1 at table "Main"
    Then the request succeeds without any change to the wallet
    And "Alice" is a loyalty member with 20 points

  @EU-1435
  Scenario: A round result is recorded once per round
    Given player "Alice" is registered
    And the result of round 1 at table "Main" was recorded for "Alice" as a net 20 on a wager of 20
    When the result of round 1 at table "Main" is recorded for "Alice" as a net 20 on a wager of 20
    Then the request succeeds without any change to the wallet
    And "Alice" has 1 recorded round result

  @EU-1436
  Scenario: A recorded round result is retracted when its round's follow-up is undone
    # When a round's follow-up fails and the caller asked for compensation,
    # each recorded result is withdrawn; the original record stays in history.
    Given player "Alice" is registered
    And the result of round 1 at table "Main" was recorded for "Alice" as a net 20 on a wager of 20
    When the recording of round 1 at table "Main" for "Alice" is compensated
    Then the result of round 1 at table "Main" is retracted for "Alice"
    And "Alice" has 0 standing round results

  # ==========================================================================
  # History written by older versions
  # ==========================================================================
  # Rule: L1

  @EU-1437
  Scenario: A deposit recorded by an older version still counts
    # Older versions stored deposits in a previous shape; it is converted to
    # the current shape whenever history is read.
    Given player "Alice" is registered
    And "Alice"'s history holds a deposit of 300 in the previous shape
    When "Alice" deposits 200
    Then "Alice" has a bankroll of 500 with 500 available
    And the wallet of "Alice" balances

  # ==========================================================================
  # The wallet explains its own balance (L1)
  # ==========================================================================
  # Rule: L1

  @EU-1438
  Scenario: The wallet balances after a mix of money movements
    Given player "Alice" is registered
    When the following happen to "Alice" in order:
      | step                                   | amount |
      | deposit                                | 1000   |
      | hold for buy-in "B1" at table "Main"   | 400    |
      | capture hold "B1"                      | 400    |
      | request top-up "T1" at table "Main"    | 200    |
      | top-up "T1" refused by the table       | 200    |
      | request top-up "T2" at table "Main"    | 100    |
      | top-up "T2" settled by the table       | 100    |
      | cash-out from table "Main"             | 650    |
      | withdraw                               | 300    |
    Then "Alice" has a bankroll of 850 with 850 available
    And "Alice" has deposited 1000, withdrawn 300, sent 500 to tables and received 650 from tables
    And the wallet of "Alice" balances
