# Allocated: EA-0014 .. EA-0049
Feature: Blackjack on a deployed cluster
  The blackjack example deployed as separate services: the wallet and the
  table (each with its own coordinator), the buy-in process, the four
  translators and the ledger. These scenarios only make sense over a real
  network: they observe what a caller waiting for an answer actually gets,
  what happens when two callers act on the same thing at once, what survives
  a restart, and what the stored history can be asked afterwards.

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
  # Smoke
  # ==========================================================================
  # Rule: N/A — cross-service integration over the deployed cluster

  @smoke @cluster @needs-core-X-031
  @EA-0014
  Scenario: Two players buy in, play a round and cash out across services
    # Seed 2: with bets of 20 and 30 and both players standing, both win.
    Given players "Alice" and "Bob" are registered and have each deposited 1000
    And table "Main" is open with 3 seats, 1 deck, bets from 10 to 100, buy-ins from 100 to 1000 and shoe seed 2
    When the session is played:
      | step                                                     |
      | "Alice" buys in at seat 0 of "Main" for 500              |
      | "Bob" buys in at seat 1 of "Main" for 500                |
      | "Alice" bets 20 and "Bob" bets 30                        |
      | the round is dealt and every player stands on their turn |
      | "Alice" and "Bob" leave "Main"                           |
    Then within 10 seconds round 1 at "Main" is reported settled with "Alice" winning 20 and "Bob" winning 30
    And within 10 seconds "Alice" has a bankroll of 1020 and "Bob" has a bankroll of 1030

  # ==========================================================================
  # Waiting for an answer
  # ==========================================================================
  # Rule: N/A — framework sync-mode behaviour over the deployed cluster

  @sync-mode @cluster @needs-core-X-031 @needs-core-X-014
  @EA-0015
  Scenario: A player who asks for a seat and waits is seated when the answer arrives
    Given player "Alice" is registered and has deposited 1000
    And table "Main" is open
    When "Alice" asks for seat 0 of "Main" for 500 and waits for every follow-up to finish
    Then the answer reports "Alice" seated at seat 0 of "Main" with a stack of 500
    And at that moment the wallet of "Alice" has already spent 500 on the buy-in

  @sync-mode @cluster @needs-core-X-014
  @EA-0016
  Scenario: A player who leaves and waits has been credited when the answer arrives
    Given player "Alice" is seated at table "Main" with a stack of 500 and 500 left in her wallet
    When "Alice" leaves "Main" and waits for every follow-up to finish
    Then at the moment the answer arrives "Alice" has a bankroll of 1000

  @sync-mode @projector @cluster @needs-core-X-014
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
  # Rule: N/A — framework concurrency (merge strategy) behaviour over the deployed cluster

  @concurrency @merge-commutative @cluster @needs-core-X-016
  @EA-0019
  Scenario: A deposit prepared before a rename still lands
    # The rename and the deposit change different parts of the wallet, so
    # the deposit does not need to be redone.
    Given player "Alice" is registered and has deposited 1000
    And a deposit of 200 for "Alice" was prepared from her wallet as it is now
    And "Alice" has since changed her display name to "Ace"
    When the prepared deposit is sent, allowing it to merge with unrelated changes
    Then the deposit is accepted
    And "Alice" has a bankroll of 1200 and is registered as "Ace"

  @concurrency @merge-commutative @cluster
  @EA-0020
  Scenario: A deposit prepared before another deposit must be redone
    # Both deposits change the bankroll, so the second one is out of date and
    # is refused in a way that invites a retry.
    Given player "Alice" is registered and has deposited 1000
    And a deposit of 200 for "Alice" was prepared from her wallet as it is now
    And "Alice" has since deposited 300
    When the prepared deposit is sent, allowing it to merge with unrelated changes
    Then the deposit is refused as out of date, and may be retried
    And "Alice" has a bankroll of 1300

  @concurrency @merge-manual @dlq @cluster @needs-core-X-110
  @EA-0021
  Scenario: A withdrawal prepared before another change goes to a person for review
    # Withdrawals are never merged or retried automatically.
    Given player "Alice" is registered and has deposited 1000
    And a withdrawal of 400 for "Alice" was prepared from her wallet as it is now
    And "Alice" has since deposited 100
    When the prepared withdrawal is sent for manual review on conflict
    Then the withdrawal is refused as needing review, and must not be retried automatically
    And the withdrawal is waiting in the dead-letter queue for review
    And "Alice" has a bankroll of 1100

  @concurrency @merge-aggregate-handles @cluster
  @EA-0022
  Scenario: A second bet for the same seat is refused by the table itself
    Given "Alice" sits at seat 0 of table "Main" with a stack of 500
    And two bets of 20 at seat 0 were prepared from the table as it is now
    When both bets are sent, letting the table judge them against its full history
    Then exactly one bet of 20 is placed at seat 0
    And the other is refused because seat 0 has already bet this round

  @concurrency @merge-aggregate-handles @cluster
  @EA-0023
  Scenario: Bets for different seats prepared at the same moment both land
    Given "Alice" sits at seat 0 and "Bob" at seat 1 of table "Main", each with a stack of 500
    And a bet of 20 at seat 0 and a bet of 30 at seat 1 were prepared from the table as it is now
    When both bets are sent, letting the table judge them against its full history
    Then seat 0 has a wager of 20 and seat 1 has a wager of 30

  # Rule: AHR-10
  @concurrency @merge-strict @cluster
  @EA-0024
  Scenario: Two hits for one hand at the same moment deal exactly one card
    # Seed 1 deals "Alice" 7♦ 4♦ against a dealer showing 9♣.
    Given "Alice" sits at seat 0 of table "Main" opened with shoe seed 1
    And "Alice" has bet 20 and the round has been dealt
    And two hits for seat 0 were prepared from the table as it is now
    When both hits are sent, refusing either if the table has changed
    Then exactly one of the hits deals a card to seat 0, the 8♦
    And the other is refused as out of date, and may be retried

  # Rule: N/A — framework sync-mode behaviour over the deployed cluster

  @sync-mode @isolated @cluster
  @EA-0025
  Scenario: A migrated player is stored without anything else reacting
    Given player "Carol" has not registered
    When "Carol" is imported from the old system without triggering any follow-up
    Then "Carol" is registered as "Carol" with a bankroll of 0
    And after 5 seconds the ledger still reports that it has not seen "Carol"

  # ==========================================================================
  # Buy-ins across two services
  # ==========================================================================
  # Rule: N/A — cross-domain process coordination over the deployed cluster

  @pm @sync-mode @cluster @needs-core-X-031
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

  @pm @compensation @cluster @needs-core-X-031 @needs-core-X-023
  @EA-0027
  Scenario: A buy-in the wallet cannot fund frees the seat
    Given player "Carol" is registered and has deposited 300
    And table "Main" is open
    When "Carol" asks for seat 0 of "Main" for 500
    Then within 10 seconds seat 0 at table "Main" is free again
    And "Carol" has a bankroll of 300 with 300 available
    And the buy-in is reported failed because the funds are not available

  @pm @compensation @cluster @needs-core-X-031 @needs-core-X-023
  @EA-0028
  Scenario: Asking for two seats at once seats the player once and releases the rest
    Given player "Alice" is registered and has deposited 1000
    And table "Main" is open
    When "Alice" asks for seat 0 and seat 1 of "Main" for 400 each, without waiting for either
    Then within 10 seconds "Alice" is seated in exactly one of seats 0 and 1 with a stack of 400
    And the other seat is free
    And "Alice" has a bankroll of 600 with 600 available
    And one buy-in is reported failed because "Alice" is already seated

  # ==========================================================================
  # Top-ups and cash-outs
  # ==========================================================================
  # Rule: AHR-13

  @saga @compensation @cluster @needs-core-X-023
  @EA-0029
  Scenario: A top-up asked for during a round is refused and its hold released
    Given "Alice" is seated at seat 0 of table "Main" opened with shoe seed 2, with a stack of 500 and 500 left in her wallet
    And "Alice" has bet 20 and the round has been dealt
    When "Alice" asks to top up 100 at "Main"
    Then within 10 seconds the top-up is reported refused because a wager is in play
    And "Alice" has a bankroll of 500 with 500 available
    And "Alice" has a stack of 480 at table "Main"

  @saga @fact @cluster
  @EA-0030
  Scenario: A top-up between rounds moves the chips once
    Given "Alice" is seated at seat 0 of table "Main" with a stack of 500 and 500 left in her wallet
    When "Alice" asks to top up 100 at "Main"
    Then within 10 seconds "Alice" has a stack of 600 at table "Main"
    And "Alice" has a bankroll of 400 with 400 available
    And the top-up was settled in the wallet exactly once

  @saga @fact @durability @cluster
  @EA-0031
  Scenario: A cash-out is credited exactly once even if the translator restarts
    Given "Alice" is seated at seat 0 of table "Main" with a stack of 500 and 500 left in her wallet
    When "Alice" leaves "Main" while the settlement translator restarts mid-delivery
    Then within 15 seconds "Alice" has a bankroll of 1000
    And the cash-out was credited to the wallet exactly once

  # ==========================================================================
  # One settled round, several follow-ups: what a waiting caller gets back
  # ==========================================================================
  # Rule: N/A — framework cascade error handling over the deployed cluster
  #
  # Seed 7 with bets of 20 (Alice, seat 0) and 30 (Bob, seat 1): both stand
  # and both lose. "Alice" never joined the loyalty programme, so her points
  # are refused; "Bob" is a member. Round results are recorded before
  # loyalty points are awarded, seat by seat. Bob's stand ends the round and
  # waits for every follow-up.

  @cascade @cluster @needs-core-X-012
  @EA-0032
  Scenario: Stopping at the first failed follow-up
    Given the loyalty round at table "Main" is ready for "Bob"'s final stand
    When "Bob" stands and waits for every follow-up, stopping at the first failure
    Then the answer is a failure because "Alice" is not a loyalty member
    And round 1 at "Main" is settled
    And "Bob" was not awarded loyalty points for round 1

  @cascade @cluster @needs-core-X-012
  @EA-0033
  Scenario: Carrying on past a failed follow-up and reporting it
    Given the loyalty round at table "Main" is ready for "Bob"'s final stand
    When "Bob" stands and waits for every follow-up, carrying on past failures
    Then the answer is a success
    And the answer reports exactly one failed follow-up: the loyalty award for "Alice", refused because she is not a loyalty member
    And "Bob" was awarded 30 loyalty points for round 1
    And round 1 results are recorded for "Alice" and "Bob"

  @cascade @compensation @cluster @needs-core-X-012 @needs-core-X-023
  @EA-0034
  Scenario: Undoing the follow-ups that already happened when one fails
    Given the loyalty round at table "Main" is ready for "Bob"'s final stand
    When "Bob" stands and waits for every follow-up, undoing them if one fails
    Then the answer is a failure because "Alice" is not a loyalty member
    And within 10 seconds round 1 results for "Alice" and "Bob" are recorded and then retracted
    And "Bob" was not awarded loyalty points for round 1
    And round 1 at "Main" is still settled

  @cascade @dlq @cluster @needs-core-X-012 @needs-core-X-110
  @EA-0035
  Scenario: Setting a failed follow-up aside for review and carrying on
    Given the loyalty round at table "Main" is ready for "Bob"'s final stand
    When "Bob" stands and waits for every follow-up, setting failures aside for review
    Then the answer is a success
    And the answer reports no failed follow-ups
    And the loyalty award for "Alice" is waiting in the dead-letter queue for review
    And "Bob" was awarded 30 loyalty points for round 1

  @cascade @cluster
  @EA-0036
  Scenario: A caller who does not wait is unaffected by a failed follow-up
    Given the loyalty round at table "Main" is ready for "Bob"'s final stand
    When "Bob" stands without waiting for anything downstream
    Then the answer is a success
    And within 10 seconds round 1 results are recorded for "Alice" and "Bob"
    And "Bob" was awarded 30 loyalty points for round 1
    And "Alice" was not awarded loyalty points for round 1

  # ==========================================================================
  # Snapshots, what-ifs and looking back
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

  @snapshot @cluster @needs-core-X-092
  @EA-0038
  Scenario: Every shoe's starting snapshot is kept while routine ones are replaced
    Given table "Main" saves a routine snapshot every 20 events
    And "Alice" has played at table "Main" until the shoe has been replaced twice
    When table "Main"'s stored snapshots are listed
    Then there is a lasting snapshot for each of shoes 1, 2 and 3
    And exactly one routine snapshot remains, the newest

  @edition @cluster @needs-core-X-021 @needs-core-X-089
  @EA-0039
  Scenario: Replaying a round differently in a what-if leaves the real table untouched
    # Seed 1 deals "Alice" 7♦ 4♦ against 9♣ 8♥: standing loses; hitting draws
    # 8♦ for 19, which wins.
    Given "Alice" sits at seat 0 of table "Main" opened with shoe seed 1
    And "Alice" bet 20, the round was dealt and she stood and lost
    When a what-if of table "Main" branches just before her stand and she hits and then stands
    Then in the what-if "Alice" wins round 1 and has a stack of 520
    And at the real table "Main" "Alice" lost round 1 and has a stack of 480
    And the real table's history is unchanged

  @speculative @cluster
  @EA-0040
  Scenario: A speculative withdrawal shows its outcome without happening
    Given player "Alice" is registered and has deposited 1000
    When "Alice" tries a withdrawal of 400 speculatively
    Then the speculative answer shows a withdrawal of 400 leaving a bankroll of 600
    And "Alice" still has a bankroll of 1000
    And the ledger still shows "Alice" with a bankroll of 1000

  @speculative @cluster
  @EA-0041
  Scenario: A speculative overdraft shows the refusal without anything happening
    Given player "Alice" is registered and has deposited 100
    When "Alice" tries a withdrawal of 400 speculatively
    Then the speculative answer is a refusal because only 100 is available
    And "Alice"'s history is unchanged

  @upcaster @cluster
  @EA-0042
  Scenario: A deposit stored by an older version is read in today's shape
    # The harness stores the old-shape event directly as a fact.
    Given player "Alice" is registered
    And "Alice"'s stored history holds a deposit of 300 in the previous shape
    When "Alice" deposits 200
    Then "Alice" has a bankroll of 500
    And reading "Alice"'s history shows both deposits in today's shape

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

  # Rule: L4

  @ledger @cluster @needs-core-X-031
  @EA-0047
  Scenario: All the money adds up after a scripted session
    Given players "Alice" and "Bob" are registered and have each deposited 1000
    And table "Main" is open with shoe seed 2
    When the session is played:
      | step                                                     |
      | "Alice" buys in at seat 0 of "Main" for 500              |
      | "Bob" buys in at seat 1 of "Main" for 500                |
      | "Alice" tops up 100 at "Main"                            |
      | "Alice" bets 20 and "Bob" bets 30                        |
      | the round is dealt and every player stands on their turn |
      | "Bob" leaves "Main"                                      |
      | "Bob" withdraws 200                                      |
    Then within 15 seconds the ledger reports nothing in flight
    And the ledger reports the money as balanced
    And a recount from the stored histories of every wallet and table gives the same totals as the ledger

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
