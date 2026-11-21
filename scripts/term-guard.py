#!/usr/bin/env python3
"""Term guard: one word for the personal band in every German text the app shows or sends ("üblicher Bereich").

Scans the Swift sources of the app and PulseCore for retired terms inside string literals and fails if one is
found. Retired: "Coach-Schwelle" (the Coach's wider band is described as "deutlich über/unter deinem üblichen
Bereich"), "persönlicher/persönlichen Bereich", "Normalband", "Normbereich". Comments may still mention them.

Usage: scripts/term-guard.py [--app PulseOne]
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RETIRED = re.compile(r"Coach-Schwelle|persönliche[rn]? Bereich|Normalband|Normbereich")
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="PulseOne")
    args = parser.parse_args()
    roots = [os.path.join(ROOT, "apps", args.app, "Sources"),
             os.path.join(ROOT, "apps", args.app, "Packages", "PulseCore", "Sources")]
    problems = []
    for root in roots:
        for folder, _, files in os.walk(root):
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as handle:
                    in_block = False  # inside a """ multi-line string
                    for number, line in enumerate(handle, 1):
                        stripped = line.strip()
                        quotes = line.count('"""')
                        texts = [line] if in_block else STRING.findall(line.split("//")[0] if not quotes else line)
                        if quotes % 2 == 1:
                            in_block = not in_block
                        if stripped.startswith("//"):
                            continue
                        for text in texts:
                            match = RETIRED.search(text)
                            if match:
                                problems.append(f"{os.path.relpath(path, ROOT)}:{number}: \"{match.group(0)}\"")
                                break
    if problems:
        print("term-guard: retired terms in texts (use \"üblicher Bereich\"):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("term-guard: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
