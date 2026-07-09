#!/usr/bin/env bash
# Reclaim disk space from Xcode without breaking device builds.
#
# This app is scan-first (VisionKit DataScanner isn't supported in the Simulator),
# so you develop on a physical iPhone. Simulator runtimes and build caches are the
# biggest space hogs and are safe to trim.
#
# SAFE section runs automatically (caches only — Xcode regenerates them).
# BIG-WIN section only PRINTS what's large + how to remove it (you decide),
# because those deletes (runtimes, device support, archives) are one-way.
#
# Usage:  bash tools/xcode-cleanup.sh          # report + clear caches
#         bash tools/xcode-cleanup.sh --dry     # report only, delete nothing
set -euo pipefail
DRY=${1:-}

human () { du -sh "$1" 2>/dev/null | cut -f1; }
exists () { [ -e "$1" ]; }

echo "=== Current Xcode/dev disk usage ==="
for p in \
  "$HOME/Library/Developer/Xcode/DerivedData" \
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport" \
  "$HOME/Library/Developer/Xcode/Archives" \
  "$HOME/Library/Developer/Xcode/iOS Device Logs" \
  "$HOME/Library/Developer/CoreSimulator/Caches" \
  "$HOME/Library/Developer/CoreSimulator/Devices" \
  "$HOME/Library/Caches/org.swift.swiftpm" \
  "$HOME/Library/Caches/com.apple.dt.Xcode" ; do
  exists "$p" && printf "  %6s  %s\n" "$(human "$p")" "$p"
done
echo

if [ "$DRY" = "--dry" ]; then echo "(dry run — nothing deleted)"; else
  echo "=== SAFE: clearing regenerable caches ==="
  # Build cache — first build after this is slower, then normal.
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
  echo "  cleared DerivedData"
  # Swift Package Manager cache (re-downloads on next resolve).
  rm -rf "$HOME/Library/Caches/org.swift.swiftpm/"* 2>/dev/null || true
  echo "  cleared SwiftPM cache"
  # Simulator caches + any broken/unavailable simulators.
  rm -rf "$HOME/Library/Developer/CoreSimulator/Caches/"* 2>/dev/null || true
  xcrun simctl delete unavailable 2>/dev/null || true
  echo "  cleared CoreSimulator caches + unavailable simulators"
  # Old device logs (not your app's data).
  rm -rf "$HOME/Library/Developer/Xcode/iOS Device Logs/"* 2>/dev/null || true
  echo "  cleared iOS Device Logs"
fi

echo
echo "=== BIG WINS (review, then remove what you don't need) ==="
echo "-- Simulator runtimes (each iOS image ~7-10 GB) --"
xcrun simctl runtime list 2>/dev/null || true
echo "   Keep AT MOST ONE (for SwiftUI Previews). Remove others in:"
echo "     Xcode → Settings → Platforms → select a runtime → (-)"
echo "     or:  xcrun simctl runtime delete <identifier-from-above>"
echo "   Building on your iPhone does NOT need any runtime."
echo
echo "-- Simulator devices (per-sim data) --"
echo "   Remove all simulator devices (keeps runtimes):  xcrun simctl delete all"
echo
echo "-- iOS DeviceSupport (one folder per iOS version you've connected) --"
echo "   Safe to delete old versions; Xcode recreates the one for your current device:"
echo "     open \"$HOME/Library/Developer/Xcode/iOS DeviceSupport\"   # delete old-version folders"
echo
echo "-- Archives (old builds you've shipped/tested) --"
echo "     open \"$HOME/Library/Developer/Xcode/Archives\"           # delete ones you don't need"
echo
echo "Done. Do NOT delete: Xcode.app itself, Command Line Tools, or the iOS SDK — those build the app."
