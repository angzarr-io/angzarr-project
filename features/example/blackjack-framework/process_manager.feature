# Allocated: EU-1550 .. EU-1564
Feature: Buying in
  A buy-in needs two things from two places: a seat at the table and money
  from the wallet. Neither side can decide alone, so a buy-in process holds
  the seat, then the money, then confirms the seat, then spends the money,
  and undoes whichever half went through if the other half is refused. It
  remembers where each buy-in is, so every step happens once even when
  messages arrive twice.

  Why this matters:
  - a player is seated only when their money is secured, and their money is
    spent only once they are seated
  - a refused buy-in leaves nothing behind: no seat held, no money held
  - two buy-ins in flight at the same time never mix up their steps
  - the process only coordinates; the table and the wallet make every
    decision

  Each buy-in is tracked under the conversation it started in, and moves
  through: waiting for funds, waiting for the seat, waiting for the money to
  be spent, then completed or failed. Every step it asks for is decided
  before it moves on.

  # ==========================================================================
  # The happy path
  # ==========================================================================

  @EU-1550
  Scenario: A held seat starts a buy-in and asks the wallet to hold the money
    Given no buy-in has started in this conversation
    When seat 0 at table "Main" is held for "Alice" by buy-in "B1" of 500
    Then buy-in "B1" is waiting for funds
    And the wallet of "Alice" is asked to hold 500 for buy-in "B1" at table "Main"
    And the request is decided before the buy-in moves on

  @EU-1551
  Scenario: Held money leads to confirming the seat
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for funds
    When the wallet of "Alice" holds 500 for buy-in "B1"
    Then buy-in "B1" is waiting for the seat
    And table "Main" is asked to confirm buy-in "B1"

  @EU-1552
  Scenario: A confirmed seat leads to spending the money
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for the seat
    When "Alice" is seated at seat 0 of table "Main" through buy-in "B1" with a stack of 500
    Then buy-in "B1" is waiting for the money to be spent
    And the wallet of "Alice" is asked to spend the hold for buy-in "B1"

  @EU-1553
  Scenario: Spent money completes the buy-in
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for the money to be spent
    When the wallet of "Alice" spends 500 for buy-in "B1"
    Then buy-in "B1" is completed
    And nothing more is asked of the table or the wallet

  # ==========================================================================
  # Refusals undo the other half
  # ==========================================================================

  @EU-1554
  Scenario: Money the wallet refuses to hold frees the seat and fails the buy-in
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for funds
    When the wallet of "Alice" refuses to hold 500 for buy-in "B1" because the funds are not available
    Then buy-in "B1" has failed because the funds are not available
    And table "Main" is asked to release the seat held by buy-in "B1"
    And nothing is asked of the wallet

  @EU-1555
  Scenario: A seat the table refuses to confirm releases the money and the seat
    Given buy-in "B2" for "Alice" at seat 1 of table "Main" is waiting for the seat
    When table "Main" refuses to confirm buy-in "B2" because "Alice" is already seated
    Then buy-in "B2" has failed because "Alice" is already seated
    And the wallet of "Alice" is asked to release the hold for buy-in "B2"
    And table "Main" is asked to release the seat held by buy-in "B2"

  @EU-1556
  Scenario: A refusal that arrives after the buy-in completed changes nothing
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is completed
    When the wallet of "Alice" refuses to hold 500 for buy-in "B1" because the funds are not available
    Then buy-in "B1" is still completed
    And nothing is asked of the table or the wallet

  # ==========================================================================
  # Robustness
  # ==========================================================================

  @EU-1557
  Scenario: News about a different buy-in is ignored
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for funds
    When the wallet of "Alice" holds 500 for buy-in "B7"
    Then buy-in "B1" is still waiting for funds
    And nothing is asked of the table or the wallet

  @EU-1558
  Scenario: The same news delivered twice moves the buy-in once
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for the seat
    And table "Main" was asked to confirm buy-in "B1"
    When the wallet of "Alice" holds 500 for buy-in "B1"
    Then buy-in "B1" is still waiting for the seat
    And table "Main" is not asked to confirm buy-in "B1" again

  @EU-1559
  Scenario: Two buy-ins in different conversations do not interfere
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for funds in one conversation
    And buy-in "B2" for "Bob" at seat 1 of table "Main" is waiting for funds in another conversation
    When the wallet of "Bob" holds 500 for buy-in "B2"
    Then buy-in "B2" is waiting for the seat
    And buy-in "B1" is still waiting for funds

  @EU-1560
  Scenario: The buy-in remembers its progress from its own history
    Given the buy-in history for this conversation is:
      | step                                                   |
      | buy-in "B1" started for "Alice" at seat 0 of "Main" for 500 |
      | funds held for buy-in "B1"                             |
      | seat confirmed for buy-in "B1" with a stack of 500     |
    When the buy-in is rebuilt from its history
    Then buy-in "B1" is waiting for the money to be spent
    And it belongs to "Alice", seat 0 of table "Main", for 500

  @EU-1561
  Scenario: The buy-in's requests carry the conversation they belong to
    # The buy-in never names the conversation itself; the framework carries
    # it from the news that triggered the request, which is how the answer
    # finds its way back to this buy-in.
    Given buy-in "B1" for "Alice" at seat 0 of table "Main" is waiting for funds in conversation "C1"
    When the wallet of "Alice" holds 500 for buy-in "B1"
    Then the request to confirm buy-in "B1" belongs to conversation "C1"
