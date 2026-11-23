#!/usr/bin/env bash
# Usage: run-durchstich.sh <simulator-udid> <app> <out-dir>
# Runs the M1 walkthrough (DurchstichTests) once while the simulator screen is recorded.
# Leaves in <out-dir>: durchstich.mp4, durchstich__NN.png per step, durchstich-report.md.
# Exit code = the test's exit code (a skip before integration counts as success).
set -uo pipefail
sim="$1"; app="$2"; out="$3"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out" build
rm -rf build/durchstich.xcresult

xcrun simctl bootstatus "$sim" -b >/dev/null 2>&1 || true
# h264 plays everywhere (QuickTime, browser, GitHub preview); hevc is the simctl default.
xcrun simctl io "$sim" recordVideo --codec=h264 --force "$out/durchstich.mp4" &
recorder=$!
sleep 3   # recorder needs a moment before the first frame

xcodebuild test-without-building -project "apps/$app/$app.xcodeproj" -scheme "$app" \
  -destination "platform=iOS Simulator,id=$sim" -derivedDataPath build/dd \
  -resultBundlePath build/durchstich.xcresult \
  -only-testing:PulseOneUITests/DurchstichTests
status=$?

sleep 2
# SIGINT lets simctl finish the file (moov atom); SIGKILL would leave an unplayable video.
kill -INT "$recorder" 2>/dev/null || true
wait "$recorder" 2>/dev/null || true

"$here/../export-screenshots.sh" build/durchstich.xcresult "$out" || true
size=$(stat -f%z "$out/durchstich.mp4" 2>/dev/null || echo 0)
echo "video: $out/durchstich.mp4 ($size bytes), test exit $status"
exit $status
