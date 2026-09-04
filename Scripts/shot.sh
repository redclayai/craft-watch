#!/bin/bash
# Screenshot the booted phone and watch simulators side by side.
#
# Exists because the Claude Code live simulator panel crashes on this machine
# (claude-ios-sim aborts in CoreImage/Metal via FBSimulatorControl), so simctl is the
# reliable way to see what the apps actually render.
#
#   Scripts/shot.sh [output-dir]
set -euo pipefail

out="${1:-/tmp/craftwatch-shots}"
mkdir -p "$out"
stamp=$(date +%H%M%S)

booted() { xcrun simctl list devices | grep "(Booted)" | sed -E 's/^ *(.*) \(([0-9A-F-]{36})\) \(Booted\).*/\2|\1/'; }

while IFS='|' read -r udid name; do
    [ -n "$udid" ] || continue
    slug=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
    path="$out/$slug-$stamp.png"
    xcrun simctl io "$udid" screenshot "$path" >/dev/null 2>&1 && echo "$path"
done < <(booted)
