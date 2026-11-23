#!/usr/bin/env python3
"""ROOK text guard (NEUBAU-PLAN §9, Auftrag 04): routine sentences that PULSE ONE never shows, speaks or asks
Claude to write. Scans every string literal in the Swift sources of the app and PulseCore (prompts, UI texts,
sample answers) and fails when one contains a forbidden fragment. Comments are not checked.

Forbidden (lowercase, keep in sync with RookTextGuard.forbidden in PulseCore):
"kein arzt", "keine ärztin", "nicht lesen", "basislinie fehlt", "lernt noch", "fehlen mir",
"sag ehrlich, was fehlt", "noch nicht abgeglichen", "ich lerne dein normal", "kein medizinprodukt".

Exceptions:
- PATTERN_FILES hold the fragments as patterns to filter Claude's answers.
- KNOWN lists texts in other teams' files that existed before the guard; they are reported as warnings with
  the owning team until that team replaces the screen. A new finding anywhere fails the run.

Usage: scripts/rook-text-guard.py [--app PulseOne]
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORBIDDEN = [
    "kein arzt", "keine ärztin", "nicht lesen", "basislinie fehlt", "lernt noch", "fehlen mir",
    "sag ehrlich, was fehlt", "noch nicht abgeglichen", "ich lerne dein normal", "kein medizinprodukt",
]
PATTERN_FILES = {"SafetyRules.swift", "RookTextGuard.swift"}
# file name -> owning team; remove the entry once the text is gone.
KNOWN = {
    "DailyScores.swift": "01 (Scores: \"lernt noch\")",
    "ScoreDetailScreen.swift": "03 (alte Score-Ansicht)",
}
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def scan(path):
    """Yields (line number, fragment) for every forbidden fragment inside a string literal."""
    with open(path, encoding="utf-8") as handle:
        in_block = False  # inside a """ multi-line string
        for number, line in enumerate(handle, 1):
            stripped = line.strip()
            quotes = line.count('"""')
            if in_block:
                texts = [line]
            elif stripped.startswith("//"):
                texts = []
            else:
                texts = [line] if quotes else STRING.findall(line.split(" //")[0])
            if quotes % 2 == 1:
                in_block = not in_block
            for text in texts:
                lower = text.lower()
                for fragment in FORBIDDEN:
                    if fragment in lower:
                        yield number, fragment
                        break


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="PulseOne")
    args = parser.parse_args()
    roots = [os.path.join(ROOT, "apps", args.app, "Sources"),
             os.path.join(ROOT, "apps", args.app, "Packages", "PulseCore", "Sources")]
    problems, warnings = [], []
    for root in roots:
        for folder, _, files in os.walk(root):
            for name in sorted(files):
                if not name.endswith(".swift") or name in PATTERN_FILES:
                    continue
                path = os.path.join(folder, name)
                for number, fragment in scan(path):
                    entry = f"{os.path.relpath(path, ROOT)}:{number}: \"{fragment}\""
                    if name in KNOWN:
                        warnings.append(f"{entry} (Team {KNOWN[name]})")
                    else:
                        problems.append(entry)
    for warning in warnings:
        print(f"rook-text-guard: warning: {warning}")
    if problems:
        print("rook-text-guard: routine sentences ROOK never says (plan §9):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("rook-text-guard: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
