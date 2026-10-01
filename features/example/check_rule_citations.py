#!/usr/bin/env python3
"""Rule-citation coverage checker.

Every Scenario in features/example/{blackjack,blackjack-acceptance} must be
governed by a `# Rule:` comment that carries forward until the next `# Rule:`
(or Feature). `# Rule: N/A — <reason>` is an explicit exemption (an
application or framework concept, not a house rule). The framework tier
(blackjack-framework) is out of scope.

Citations name the house rules and ledger invariants of blackjack/RULES.md
(`AHR-1` .. `AHR-13`, `L1` .. `L4`). The checker verifies that every
citation names a catalogued rule and that every catalogued rule is cited by
at least one scenario.

Exits non-zero if any scenario is ungoverned, a citation is unknown or a rule
is uncited.
Usage: python3 check_rule_citations.py [features/example]
"""
import glob
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
SCN = re.compile(r'^\s*(Scenario|Scenario Outline):\s*(.*)')
RULE = re.compile(r'^\s*#\s*Rule:\s*(.+)', re.I)
FEAT = re.compile(r'^\s*Feature:')
SUBS = ("blackjack", "blackjack-acceptance")
BLACKJACK_RULES = {f"AHR-{n}" for n in range(1, 14)} | {f"L{n}" for n in range(1, 5)}
BLACKJACK_ID = re.compile(r'\b(AHR-\d+|L\d+)\b')

cited = exempt = uncited = 0
gaps = {}
unknown = []
blackjack_cited = set()
for sub in SUBS:
    for f in sorted(glob.glob(os.path.join(ROOT, sub, "*.feature"))):
        cur = None
        missing = []
        for i, line in enumerate(open(f, encoding="utf-8"), 1):
            if FEAT.match(line):
                cur = None
            elif RULE.match(line):
                cur = RULE.match(line).group(1).strip()
            elif SCN.match(line):
                if cur is None:
                    uncited += 1
                    missing.append((i, SCN.match(line).group(2).strip()[:60]))
                elif cur.upper().startswith("N/A"):
                    exempt += 1
                else:
                    cited += 1
                    ids = BLACKJACK_ID.findall(cur)
                    bad = [r for r in ids if r not in BLACKJACK_RULES]
                    if not ids or bad:
                        unknown.append(f"{os.path.relpath(f, ROOT)}:{i}: cites {cur!r}, not a rule in blackjack/RULES.md")
                    blackjack_cited.update(r for r in ids if r in BLACKJACK_RULES)
        if missing:
            gaps[os.path.relpath(f, ROOT)] = missing

total = cited + exempt + uncited
print(f"Rule-citation coverage: {cited} cited + {exempt} exempt = {cited+exempt}/{total} governed; {uncited} UNCITED")
for f, m in sorted(gaps.items()):
    print(f"  {f}: {len(m)} uncited")
    for ln, name in m[:5]:
        print(f"      L{ln}: {name}")
for u in unknown:
    print(f"  {u}")
uncited_rules = sorted(BLACKJACK_RULES - blackjack_cited, key=lambda r: (r[0], int(re.sub(r'\D', '', r))))
if uncited_rules:
    print(f"  blackjack rules cited by no scenario: {', '.join(uncited_rules)}")
sys.exit(1 if uncited or unknown or uncited_rules else 0)
