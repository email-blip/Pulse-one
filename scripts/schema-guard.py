#!/usr/bin/env python3
"""Schema guard for the SwiftData store (no Xcode needed, runs in seconds).

Reads every `@Model` class under apps/<App>/Sources and compares its stored properties with the committed
snapshot docs/schema-snapshot.json. A change that SwiftData cannot migrate on its own fails the check:

- a model or stored property was removed or renamed,
- a stored property changed its type or lost its optional marker,
- a new stored property in an existing model is neither optional nor has a default value,
- `@Attribute(.unique)` was added to an existing property.

New models, new optional properties and new properties with a default are lightweight migrations and pass.
After an intended change run with --update and commit the snapshot together with the model change.
A change that fails here needs a real migration stage (VersionedSchema with frozen model copies) first.

Usage: scripts/schema-guard.py [--app PulseOne] [--update]
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAPSHOT = os.path.join(ROOT, "docs", "schema-snapshot.json")

CLASS_RE = re.compile(r"^@Model\s*\n(?:\s*@[^\n]*\n)*\s*(?:public\s+|internal\s+)?final\s+class\s+(\w+)", re.M)
PROP_RE = re.compile(
    r"^    (?P<attrs>(?:@\w+(?:\([^)]*\))?\s+)*)"
    r"(?:(?:public|internal|private(?:\(set\))?|fileprivate)\s+)*"
    r"var\s+(?P<name>\w+)\s*:\s*(?P<type>[^={\n]+?)\s*(?P<rest>=[^\n]*|\{[^\n]*)?$"
)


def class_bodies(text):
    """Yields (name, body) for each @Model class: the lines up to the matching closing brace."""
    for match in CLASS_RE.finditer(text):
        start = text.index("{", match.end())
        depth = 0
        for index in range(start, len(text)):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    yield match.group(1), text[start + 1:index]
                    break


def stored_properties(body):
    """Stored properties at class level (4-space indent); computed properties and static members are skipped."""
    props = {}
    for line in body.split("\n"):
        if "static " in line or "@Transient" in line or "@ObservationIgnored" in line:
            continue
        match = PROP_RE.match(line)
        if not match:
            continue
        rest = (match.group("rest") or "").strip()
        if rest.startswith("{"):
            continue  # computed property
        type_name = re.sub(r"\s+", "", match.group("type"))
        optional = type_name.endswith("?") or type_name.endswith("!")
        props[match.group("name")] = {
            "type": type_name.rstrip("?!"),
            "optional": optional,
            "default": rest.startswith("="),
            "unique": ".unique" in (match.group("attrs") or ""),
        }
    return props


def scan(app):
    models = {}
    source_root = os.path.join(ROOT, "apps", app, "Sources")
    for folder, _, files in os.walk(source_root):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(folder, name)
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            if "@Model" not in text:
                continue
            for class_name, body in class_bodies(text):
                models[class_name] = {
                    "file": os.path.relpath(path, ROOT),
                    "properties": stored_properties(body),
                }
    return dict(sorted(models.items()))


def compare(old, new):
    problems = []
    for model, before in old.items():
        if model not in new:
            problems.append(f"{model}: model removed or renamed (existing rows would be lost)")
            continue
        after = new[model]["properties"]
        for prop, was in before["properties"].items():
            now = after.get(prop)
            if now is None:
                problems.append(f"{model}.{prop}: stored property removed or renamed")
                continue
            if now["type"] != was["type"]:
                problems.append(f"{model}.{prop}: type changed {was['type']} -> {now['type']}")
            if was["optional"] and not now["optional"]:
                problems.append(f"{model}.{prop}: was optional, now required")
            if now["unique"] and not was["unique"]:
                problems.append(f"{model}.{prop}: @Attribute(.unique) added to existing property")
        for prop, now in after.items():
            if prop not in before["properties"] and not (now["optional"] or now["default"]):
                problems.append(f"{model}.{prop}: new property needs to be optional or have a default value")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="PulseOne")
    parser.add_argument("--update", action="store_true", help="write the current schema as the new snapshot")
    args = parser.parse_args()

    current = scan(args.app)
    if not current:
        print("schema-guard: no @Model classes found", file=sys.stderr)
        return 1
    if args.update or not os.path.exists(SNAPSHOT):
        with open(SNAPSHOT, "w", encoding="utf-8") as handle:
            json.dump(current, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print(f"schema-guard: snapshot written ({len(current)} models)")
        return 0

    with open(SNAPSHOT, encoding="utf-8") as handle:
        snapshot = json.load(handle)
    problems = compare(snapshot, current)
    if problems:
        print("schema-guard: changes SwiftData cannot migrate on its own:")
        for problem in problems:
            print(f"  - {problem}")
        print("Make new properties optional or give them a default; for renames/removals add a migration stage.")
        return 1
    added = sorted(set(current) - set(snapshot))
    changed = [m for m in snapshot if m in current and current[m]["properties"] != snapshot[m]["properties"]]
    if added or changed:
        print("schema-guard: OK, lightweight changes only. Run with --update and commit the snapshot:")
        for model in added:
            print(f"  + new model {model}")
        for model in changed:
            print(f"  ~ {model}")
        return 1
    print(f"schema-guard: OK ({len(current)} models unchanged)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
