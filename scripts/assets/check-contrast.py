#!/usr/bin/env python3
"""Checks WCAG contrast of the DesignKit color tokens (Auftrag 02, Abnahme "Kontrast AA").

Reads every `Color(hex: 0x......)` token from DesignKit/DKColor.swift (named `static let` tokens plus the
per-kind / per-phase colors inside MetricStyle and SleepPhaseStyle) and checks:
- text tokens  >= 4.5:1 on every surface (normal text, AA)
- accent/kind/phase colors >= 3:1 on every surface (graphics and large text, AA)
- onAccent on the accent fill >= 4.5:1

Usage: python3 scripts/assets/check-contrast.py   (exit 1 on any failure)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "apps", "PulseOne", "Sources", "DesignKit", "DKColor.swift")

SURFACES = ["obsidian", "surface", "surfaceRaised", "surfaceSelected"]
TEXT = ["iceWhite", "textSecondary", "textTertiary"]
GRAPHICS = ["bioCyan", "neuralViolet", "pulseCoral"]


def luminance(hex_value):
    channels = [((hex_value >> shift) & 0xFF) / 255 for shift in (16, 8, 0)]
    linear = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def main():
    text = open(SOURCE, encoding="utf-8").read()
    named = {m.group(1): int(m.group(2), 16)
             for m in re.finditer(r"static let (\w+)\s*=\s*Color\(hex: 0x([0-9A-Fa-f]{6})\)", text)}
    # Colors used inline for kinds and phases (everything after the MetricStyle declaration).
    styles = text[text.index("struct MetricStyle"):]
    inline = sorted({int(h, 16) for h in re.findall(r"Color\(hex: 0x([0-9A-Fa-f]{6})\)", styles)})

    failures, lines = [], []
    for surface in SURFACES:
        bg = named[surface]
        for name in TEXT:
            r = ratio(named[name], bg)
            lines.append(f"text     {name:15} on {surface:15} {r:5.2f}")
            if r < 4.5:
                failures.append(f"{name} on {surface}: {r:.2f} < 4.5")
        for name in GRAPHICS:
            r = ratio(named[name], bg)
            lines.append(f"graphic  {name:15} on {surface:15} {r:5.2f}")
            if r < 3:
                failures.append(f"{name} on {surface}: {r:.2f} < 3")
        for value in inline:
            r = ratio(value, bg)
            lines.append(f"kind     #{value:06X}        on {surface:15} {r:5.2f}")
            if r < 3:
                failures.append(f"#{value:06X} on {surface}: {r:.2f} < 3")
    r = ratio(named["obsidian"], named["bioCyan"])
    lines.append(f"text     onAccent        on bioCyan         {r:5.2f}")
    if r < 4.5:
        failures.append(f"onAccent on bioCyan: {r:.2f} < 4.5")

    print("\n".join(lines))
    if failures:
        print("check-contrast: FAILED\n  - " + "\n  - ".join(failures))
        return 1
    print(f"check-contrast: OK ({len(lines)} pairs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
