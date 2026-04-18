# Step phrasing conventions

Advisory rules for authoring Gherkin scenarios across all three tiers.
Not CI-enforced — code review is the feedback loop.

Each rule below gives the **rule**, the **rationale**, a **good** example,
and a **bad** example. When a reviewer cites a rule, they cite the number.

---

## 1. Entities are quoted proper nouns

Name aggregates, sagas, domains, tables, players as quoted strings.

**Rationale:** easy to grep; consistent parameterization; avoids collisions
between step words and identifiers.

- Good: `player "Alice"`, `table "Main"`, `saga "OrderFulfillment"`
- Bad: `player Alice`, `the Main table`, `saga OrderFulfillment`

## 2. Types are unquoted, in the code's native casing

Commands/events use PascalCase; domains use lowercase quoted strings.

- Good: `domain "order"`, command `CreateOrder`, event `OrderCreated`
- Bad: `domain Order`, command `"CreateOrder"`, event `order_created`

## 3. Given/When/Then semantics

- **Given** — prior state, past tense facts
- **When** — the action under test, active voice
- **Then** — assertion of outcome, declarative

- Good: `Given a registered player "Alice"` / `When Alice folds` / `Then the response contains one FundsReleased event`
- Bad: `Given I fold` / `When the response contains…` / `Then Alice is folding`

## 4. Temporal markers are acceptance-only

`within N seconds` belongs in `example/acceptance/` only. Unit tiers are
synchronous by contract — a temporal assertion there is a category error.

- Good (acceptance): `Then within 3 seconds hand domain has CardsDealt event`
- Bad (unit): `Then within 100ms the handler emits OrderCreated`

## 5. Command invocation phrasing differs by tier

- Acceptance: `When I send a CreateOrder command` (user-perspective; the
  CommandClient is the subject)
- Unit: `When CreateOrder(order_id="o-1") is dispatched` (router-perspective;
  passive voice emphasizes the framework)

Keep the style consistent within one feature file.

## 6. Assertion verbs carry meaning

- `emits` — handler returned this output
- `has` — observable state reflects this
- `triggers` — cross-domain chain occurred (acceptance)

- Good: `Then the saga emits a DealCards command`, `Then Alice has stack 495`
- Bad: `Then Alice emits stack 495`, `Then the saga has a DealCards`

## 7. Tables use `|` with a key column first

- Good:
  ```
  | name  | seat | stack |
  | Alice | 0    | 500   |
  ```
- Bad: key-less rows, unquoted strings, inconsistent column order across
  scenarios.

## 8. Step regex uses named groups

Positional groups break when patterns grow.

- Good: `r'player "(?P<name>[^"]+)" has stack (?P<stack>\d+)'`
- Bad: `r'player "([^"]+)" has stack (\d+)'`

## 9. Step file mirrors feature file name

`player.feature` ↔ `player_steps.py` (or `player_steps.go`, etc.). Shared
steps go in `common_steps.*`.

## 10. `@wip` tag opts a scenario out of CI

Used during authoring. CI always runs with `--tags="~@wip"`. Don't land @wip
scenarios in main without a tracking issue.

## 11. Scenario titles are present-tense behavior claims

- Good: `Saga produces a command for the target domain`
- Bad: `Producing a command for the target domain` / `Test saga output`

## 12. Domain vocabulary is tier-bound

- `features/client/` — only `Order`, `Payment`, `Inventory`, `Shipping`. No poker.
- `features/example/` — only poker types.

Mixing poisons the shared vocabulary for consumer repos.

## 13. Background is for truly shared setup

Prefer per-scenario `Given` when the setup is not universal across every
scenario in the file. Overloaded `Background` blocks become invisible state
that makes scenarios harder to read in isolation.

## 14. No doc strings; use tables

Multi-line `"""..."""` payloads obscure structure. Tables make assertions
inspectable at a glance.

## 15. Assertions are structural, not positional

Don't assert `the first element has...` when the collection is unordered.
Name the element by key.

## 16. Scenario ID tag is mandatory

Every `Scenario:` has a `@<tier>-NNNN` tag immediately above it. Format is
fixed: uppercase tier code, dash, four digits with leading zeros.

- Good: `@C-0042`
- Bad: `@C-42`, `@c-0042`, `@C_0042`

## 17. Tier domain purity

Client tier feature files import zero poker concepts. Example tier feature
files import zero generic `Order`/`Payment` concepts. A scenario that
genuinely spans both belongs in a different test — probably pytest/unit
integration — not cucumber.
