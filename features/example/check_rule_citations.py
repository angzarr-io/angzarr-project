#!/usr/bin/env python3
"""Rule-citation coverage checker.

Every Scenario in features/example/{poker,acceptance} must be governed by a
`# Rule:` comment that carries forward until the next `# Rule:` (or Feature).
`# Rule: N/A — <reason>` is an explicit exemption (app/integration concept, not a
codified hand rule). framework/ is out of scope. Exits non-zero if any scenario
is ungoverned.  Usage: python3 check_rule_citations.py [features/example]
"""
import sys, re, glob, os
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
SCN = re.compile(r'^\s*(Scenario|Scenario Outline):\s*(.*)')
RULE = re.compile(r'^\s*#\s*Rule:\s*(.+)', re.I)
FEAT = re.compile(r'^\s*Feature:')
cited = exempt = uncited = 0
gaps = {}
for sub in ("poker", "acceptance"):
    for f in sorted(glob.glob(os.path.join(ROOT, sub, "*.feature"))):
        cur = None; missing = []
        for i, line in enumerate(open(f), 1):
            if FEAT.match(line): cur = None
            elif RULE.match(line): cur = RULE.match(line).group(1).strip()
            elif SCN.match(line):
                if cur is None:
                    uncited += 1; missing.append((i, SCN.match(line).group(2).strip()[:60]))
                elif cur.upper().startswith("N/A"): exempt += 1
                else: cited += 1
        if missing: gaps[os.path.relpath(f, ROOT)] = missing
total = cited + exempt + uncited
print(f"Rule-citation coverage: {cited} cited + {exempt} exempt = {cited+exempt}/{total} governed; {uncited} UNCITED")
for f, m in sorted(gaps.items()):
    print(f"  {f}: {len(m)} uncited")
    for ln, name in m[:5]: print(f"      L{ln}: {name}")
sys.exit(1 if uncited else 0)
