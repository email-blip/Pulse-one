#!/usr/bin/env bash
# Usage: export-screenshots.sh <result.xcresult> <out-dir>
# Extracts PNG attachments (XCTAttachment name = file name) from an xcresult bundle.
set -euo pipefail
res="$1"; out="$2"
[ -d "$res" ] || { echo "no result bundle $res – skipping"; exit 0; }
tmp=$(mktemp -d); mkdir -p "$out"
xcrun xcresulttool export attachments --path "$res" --output-path "$tmp"
python3 - "$tmp" "$out" <<'PY'
import json, os, re, shutil, sys
tmp, out = sys.argv[1], sys.argv[2]
manifest = os.path.join(tmp, "manifest.json")
count = 0
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for a in test.get("attachments", []):
            src = os.path.join(tmp, a["exportedFileName"])
            if not src.lower().endswith(".png"): continue
            name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            name = re.sub(r"_\d+_[0-9A-F-]{36}", "", name)   # strip index/UUID suffix if present
            name = re.sub(r"[^A-Za-z0-9_.-]", "-", name)
            if not name.endswith(".png"): name += ".png"
            shutil.copy(src, os.path.join(out, name)); count += 1
else:
    for f in os.listdir(tmp):
        if f.lower().endswith(".png"): shutil.copy(os.path.join(tmp, f), out); count += 1
print(f"exported {count} screenshots to {out}")
PY
