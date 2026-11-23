#!/usr/bin/env python3
"""Usage: perf-summary.py <result.xcresult>  – prints the XCTest metrics of the bundle as a Markdown table.

Report only: without a stored baseline XCTest records values and never fails on them. Simulator numbers find
regressions; they do not prove 60 fps on the iPhone.
"""
import json, statistics, subprocess, sys

path = sys.argv[1]
try:
    raw = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", path],
                         check=True, capture_output=True, text=True).stdout
    data = json.loads(raw)
except Exception as error:  # older xcresulttool, no metrics, no bundle
    print(f"Keine Messwerte lesbar ({error.__class__.__name__}).")
    sys.exit(0)

rows = []
for test in data if isinstance(data, list) else data.get("tests", []):
    name = test.get("testIdentifier", "?")
    for run in test.get("testRuns", [test]):
        for metric in run.get("metrics", []):
            values = [m for m in metric.get("measurements", []) if isinstance(m, (int, float))]
            if not values:
                continue
            rows.append((name.split("/")[-1], metric.get("displayName", metric.get("identifier", "?")),
                         statistics.mean(values), max(values), metric.get("unitOfMeasurement", "")))
if not rows:
    print("Keine Messwerte im Ergebnis (Verlauf noch nicht integriert?).")
    sys.exit(0)
print("| Test | Messgröße | Mittel | Max | Einheit |\n|---|---|---|---|---|")
for test, metric, mean, top, unit in rows:
    print(f"| {test} | {metric} | {mean:.2f} | {top:.2f} | {unit} |")
