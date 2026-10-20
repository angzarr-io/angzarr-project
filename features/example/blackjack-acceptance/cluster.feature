# Allocated: EA-0014 .. EA-0049
Feature: Blackjack on a deployed cluster
  The blackjack example deployed as separate services, each one component
  with its own coordinator: the wallet, the table, the buy-in process, the
  table-to-wallet translator and the ledger. These scenarios only make sense over a real
  network: they observe what a caller waiting for an answer actually gets,
  what happens when two callers act on the same thing at once, what survives
  a restart, and what the stored history can be asked afterwards.

  Scenarios that relied on constructs the latest contract removes (waiting
  for every follow-up, writing without reactions, commutative and manually
  reviewed conflicts, compensation, facts, cascade error modes, lasting
  snapshots, what-ifs and speculative reads) wait on rulings in
  docs/design/blackjack-latest-proto-rulings.md.

  Every scenario uses its own players and tables, so scenarios never see each
  other's money. Tables are created with a named shoe seed; the golden shoes
  in ../blackjack/shoe.feature say which cards each seed deals. Assertions
  read what the services report: the event stream, stored history, and the
  ledger's query service. Nothing is checked against the test's own notes.

  A scenario tagged @needs-core-X-NNN depends on the fix for that finding in
  the framework and is excluded from required runs until the fix lands; the
  fix removes the tag.

  How to run: deploy the example, export PLAYER_URL, TABLE_URL and LEDGER_URL,
  then run the example repository's acceptance runner.

  Background:
    Given the blackjack cluster is reachable

  # ==========================================================================
  # Waiting for an answer
  # ==========================================================================
  # Rule: N/A — framework command-mode behaviour over the deployed cluster

  @command-mode @projector @cluster @needs-core-X-014
  @EA-0017
  Scenario: A deposit that waits for the read models is in the ledger when it returns
    Given player "Alice" is registered
    When "Alice" deposits 500 and waits for the read models to catch up
    Then at the moment the answer arrives the ledger shows "Alice" with a bankroll of 500

  @projector @consistency @cluster
  @EA-0018
  Scenario: A deposit that does not wait reaches the ledger shortly after
    Given player "Alice" is registered
    When "Alice" deposits 500 without waiting for anything downstream
    Then within 3 seconds the ledger shows "Alice" with a bankroll of 500

  # ==========================================================================
  # Two callers at once
  # ==========================================================================
  # Rule: N/A — framework concurrency (conflict resolution) behaviour over the deployed cluster

  @concurrency @conflict-aggregate-handles @cluster
  @EA-0022
  Scenario: A second bet for the same seat is refused by the table itself
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And two bets of 20 at seat 0 were prepared from the table as it is now
    When both bets are sent, letting the table judge them against its full history
    Then exactly one bet of 20 is placed at seat 0
    And the other is refused because seat 0 has already bet this round

  @concurrency @conflict-aggregate-handles @cluster
  @EA-0023
  Scenario: Bets for different seats prepared at the same moment both land
    Given "Alice" sits at seat 0 and "Bob" at seat 1 of table "Main", each with a stack of 500
    And a bet of 20 at seat 0 and a bet of 30 at seat 1 were prepared from the table as it is now
    When both bets are sent, letting the table judge them against its full history
    Then seat 0 has a wager of 20 and seat 1 has a wager of 30

  # Rule: AHR-10
  @concurrency @conflict-strict @cluster
  @EA-0024
  Scenario: Two hits for one hand at the same moment deal exactly one card
    # Seed 1 deals "Alice" 7♦ 4♦ against a dealer showing 9♣.
    Given "Alice" sits at seat 0 of table "Main" opened with shoe seed 1
    And "Alice" has bet 20 and the round has been dealt
    And two hits for seat 0 were prepared from the table as it is now
    When both hits are sent, refusing either if the table has changed
    Then exactly one of the hits deals a card to seat 0, the 8♦
    And the other is refused as out of date, and may be retried

  # ==========================================================================
  # Buy-ins across two services
  # ==========================================================================
  # Rule: N/A — cross-domain process coordination over the deployed cluster

  @pm @command-mode @cluster @needs-core-X-031
  @EA-0026
  Scenario: Each step of a buy-in is decided before the next one starts
    Given player "Alice" is registered and has deposited 1000
    And table "Main" is open
    When "Alice" asks for seat 0 of "Main" for 500
    Then within 10 seconds the buy-in's history across both services reads, in order:
      | service | what happened            |
      | table   | seat 0 held              |
      | player  | 500 held for the buy-in  |
      | table   | "Alice" seated with 500  |
      | player  | 500 spent on the buy-in  |

  # ==========================================================================
  # Snapshots and looking back
  # ==========================================================================
  # Rule: N/A — framework storage and query behaviour over the deployed cluster

  @snapshot @cluster
  @EA-0037
  Scenario: A long-running table is served from its latest snapshot
    Given table "Main" saves a routine snapshot every 20 events
    And "Alice" has played 10 rounds at table "Main"
    When table "Main"'s stored history is read
    Then it starts from a snapshot taken after the 20th event or later
    And the table rebuilt from that snapshot shows the same stack for "Alice" as the table replayed from the start

  @temporal @cluster
  @EA-0043
  Scenario: The wallet can be read as it was at an earlier point in its history
    Given player "Alice" is registered and has deposited 1000
    And "Alice" has bought in at table "Main" for 500
    When "Alice"'s wallet is read as of just before the buy-in
    Then that wallet has a bankroll of 1000 with nothing held

  @temporal @cluster
  @EA-0044
  Scenario: The wallet can be read as it was at an earlier moment in time
    Given player "Alice" is registered and has deposited 1000
    And a moment was noted
    And "Alice" has since withdrawn 300
    When "Alice"'s wallet is read as of the noted moment
    Then that wallet has a bankroll of 1000

  @stream @cluster @needs-core-X-034
  @EA-0045
  Scenario: A live view follows one buy-in across both services
    Given player "Alice" is registered and has deposited 1000
    And table "Main" is open
    And a live view is watching the conversation of "Alice"'s next request
    When "Alice" asks for seat 0 of "Main" for 500
    Then within 10 seconds the live view has shown the seat held, the money held, the seat confirmed and the money spent
    And the live view has shown nothing from any other conversation

  # ==========================================================================
  # Money adds up across the whole system
  # ==========================================================================
  # Rule: L3

  @ledger @cluster @needs-core-X-031
  @EA-0046
  Scenario: A buy-in's history gathered from both services pairs up
    Given player "Alice" is registered and has deposited 1000
    And table "Main" is open
    When "Alice" asks for seat 0 of "Main" for 500
    Then within 10 seconds the stored history of that conversation holds exactly one seat confirmation and one spent hold for 500 under the same buy-in

  # ==========================================================================
  # Restarts
  # ==========================================================================
  # Rule: N/A — durability across service restarts on the deployed cluster

  @durability @cluster
  @EA-0048
  Scenario: Wallet and table survive their services restarting
    Given "Alice" is seated at seat 0 of table "Main" opened with shoe seed 7, with a stack of 500 and 500 left in her wallet
    And "Alice" has played one round at table "Main", betting 20 and standing on her turn
    When the wallet service and the table service restart
    Then within 15 seconds "Alice" has a bankroll of 500 and a stack of 520 at table "Main"
    And the next round at table "Main" is dealt from where the shoe left off

  @pm @durability @cluster @needs-core-X-031
  @EA-0049
  Scenario: A buy-in interrupted by a restart holds and spends the money once
    Given player "Alice" is registered and has deposited 1000
    And table "Main" is open
    When "Alice" asks for seat 0 of "Main" for 500 while the buy-in process restarts mid-flow
    Then within 20 seconds "Alice" is seated at seat 0 of "Main" with a stack of 500
    And "Alice" has a bankroll of 500 with 500 available
    And the wallet holds and spends the money for that buy-in exactly once
