#!/usr/bin/env bash
# Prints GitHub step outputs: main/small/large simulator UDIDs and names.
# main = newest "iPhone NN Pro", large = newest "Pro Max", small = newest non-Pro/non-Plus/non-Max model (e.g. iPhone 16e or base model).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
phones = []
for runtime, devs in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m: continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devs:
        n = re.match(r"iPhone (\d+)(.*)", d["name"])
        if n: phones.append((ver, int(n.group(1)), n.group(2).strip(), d))
if not phones: sys.exit("no iPhone simulators")
newest_rt = max(p[0] for p in phones)
phones = [p for p in phones if p[0] == newest_rt]
def pick(pred):
    c = [p for p in phones if pred(p[2])]
    return max(c, key=lambda p: p[1])[3] if c else None
main  = pick(lambda s: s == "Pro") or phones[0][3]
large = pick(lambda s: s == "Pro Max") or main
small = pick(lambda s: s == "e") or pick(lambda s: s == "") or main
for key, d in (("main", main), ("small", small), ("large", large)):
    udid, name = d["udid"], d["name"].replace(" ", "-")
    print(key + "=" + udid)
    print(key + "_name=" + name)
print("runtime=%d.%d" % newest_rt, file=sys.stderr)
'
