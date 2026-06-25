# Allocated: EU-0900 .. EU-0930
Feature: Betting round iteration logic
  The cluster's hand aggregate must visit every active player after an
  intervening raise, regardless of earlier folds, and must terminate the
  betting round once all active bets are matched or the last aggressor
  has gone all-in. The observable effect of the rule is the
  BettingRoundComplete event: it fires only when every still-active
  seat has matched the current bet (or is all-in). A buggy iteration
  that skips a player would leave their bet_this_round under-funded
  and the round wouldn't complete (or would complete with the wrong
  pot).

  # ==========================================================================
  # Rule references (cited via "# Rule:" comments throughout this file)
  # ==========================================================================
  # Every scenario in this file expresses one or both of:
  #   TDA Rule 50 (2024) — "Players must act in turn verbally and/or by
  #     pushing out chips. Action in turn is binding and commits chips to
  #     the pot that stay in the pot."
  #   TDA Rule 47A (2024) — round termination: "an all-in wager … will not
  #     reopen betting for players who have already acted and are not
  #     facing at least a full bet or raise when the action returns to
  #     them." When the last aggressor is all-in, the round terminates
  #     once remaining active players have called.
  # See features/example/RULES.md for the full rule cross-reference.
  #
  # Reframed 2026-05-20 — scenarios now assert on cluster-observable
  # events (BettingRoundComplete fires, pot totals, per-seat
  # bet_this_round contributions) rather than the in-test fixture's
  # "seats asked to act" iteration log. The iteration order itself is
  # internal to the hand aggregate; what we test here at the cluster
  # tier is the OBSERVABLE EFFECT of the iteration rule — the round
  # completes correctly, every still-active player contributed the
  # matching amount, and the pot totals match the algebra of the
  # scripted action sequence.

  # ==========================================================================
  # Correct Iteration After a Raise — TDA Rule 50
  # ==========================================================================

  # Rule: TDA Rule 50 (2024) — action in turn is binding; the betting round completes only when every active seat has matched the current bet (or is all-in)
  @EU-0900
  @wip
  Scenario: Round completes once every seat has matched the post-raise bet
    # Six-handed; UTG at seat 3 folds, seat 4 folds, seat 5 raises to 48,
    # seat 0 folds, SB at seat 1 calls (43 more), BB at seat 2 calls
    # (38 more). The buggy "skipped Bob" iteration would leave Bob's
    # bet_this_round at 5 (the SB) — round still considered complete
    # because the buggy driver doesn't ask Bob, but Bob's chips don't
    # match the 48 facing him. The observable: BettingRoundComplete
    # fires AND every still-active seat's contribution equals 48.
    Given a 6-handed Texas Hold'em hand
    And blinds posted: SB at seat 1 amount 5, BB at seat 2 amount 10
    When players act in sequence:
      | seat | action | amount |
      | 3    | FOLD   | 0      |
      | 4    | FOLD   | 0      |
      | 5    | RAISE  | 48     |
      | 0    | FOLD   | 0      |
      | 1    | CALL   | 43     |
      | 2    | CALL   | 38     |
    Then a BettingRoundComplete event is emitted for phase PREFLOP
    And seat 5 contributed 48 chips this round
    And seat 1 contributed 48 chips this round
    And seat 2 contributed 48 chips this round
    And the pot total is 144

  @EU-0901
  @wip
  Scenario: SB matches the raise rather than forfeiting their blind
    # Bob (SB at seat 1) has 5 chips committed pre-action. A raise to 48
    # by seat 5 must put Bob's contribution at 48 once he calls — if the
    # iteration skipped him, his contribution would stick at 5 and the
    # round wouldn't complete (or would complete with the pot short).
    Given a 6-handed Texas Hold'em hand
    And blinds posted: SB at seat 1 amount 5, BB at seat 2 amount 10
    When players act in sequence:
      | seat | action | amount |
      | 3    | FOLD   | 0      |
      | 4    | FOLD   | 0      |
      | 5    | RAISE  | 48     |
      | 0    | FOLD   | 0      |
      | 1    | CALL   | 43     |
      | 2    | CALL   | 38     |
    Then seat 1 contributed 48 chips this round
    And a BettingRoundComplete event is emitted for phase PREFLOP

  @EU-0902
  @wip
  Scenario: Raiser is not asked to re-act when everyone only calls
    # If the cluster's iteration loops back to the raiser after the
    # last caller, the raiser would face their own bet (current_bet
    # == their own bet_this_round) and would have nothing to call.
    # Observable: exactly 6 ActionTaken events are emitted, the
    # raiser's seat 5 contributes exactly once.
    Given a 6-handed Texas Hold'em hand
    And blinds posted: SB at seat 1 amount 5, BB at seat 2 amount 10
    When players act in sequence:
      | seat | action | amount |
      | 3    | FOLD   | 0      |
      | 4    | FOLD   | 0      |
      | 5    | RAISE  | 48     |
      | 0    | FOLD   | 0      |
      | 1    | CALL   | 43     |
      | 2    | CALL   | 38     |
    Then a BettingRoundComplete event is emitted for phase PREFLOP
    And exactly 6 ActionTaken events were emitted this round
    And seat 5 acted exactly 1 time this round

  # ==========================================================================
  # All-In Aggressor Termination — TDA Rule 47A
  # ==========================================================================
  # Rule: TDA Rule 47A (2024) — "an all-in wager … will not reopen betting
  # for players who have already acted." When the last raiser's raise is an
  # all-in, they leave the active set. The termination check must treat the
  # aggressor as absent so the round ends once the remaining players have
  # called.

  @EU-0903
  @wip
  Scenario: Round terminates after calls against an all-in aggressor
    # Four-handed; Eve (seat 2, stack 27) raises all-in to 27; Frank,
    # Bob, Dave call. Eve's seat leaves the active set. Observable:
    # round terminates AFTER the three callers; the buggy "keep asking
    # Frank" loop would emit a 5th ActionTaken event before
    # BettingRoundComplete. Plus Eve's post-action stack is 0 and her
    # contribution is 27.
    Given a table with players:
      | name  | seat | stack |
      | Bob   | 0    | 1000  |
      | Dave  | 1    | 1000  |
      | Eve   | 2    | 27    |
      | Frank | 3    | 1000  |
    And blinds posted: SB at seat 0 amount 5, BB at seat 1 amount 10
    When players act in sequence:
      | seat | action | amount |
      | 2    | RAISE  | 27     |
      | 3    | CALL   | 27     |
      | 0    | CALL   | 22     |
      | 1    | CALL   | 17     |
    Then a BettingRoundComplete event is emitted for phase PREFLOP
    And exactly 4 ActionTaken events were emitted this round
    And seat 2 is all-in
    And seat 2 has stack 0
    And seat 2 contributed 27 chips this round
