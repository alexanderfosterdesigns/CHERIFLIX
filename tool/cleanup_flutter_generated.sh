#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SAFE_DIRS=(
  "build"
  ".dart_tool"
  "android/.gradle"
  "android/build"
  "android/app/build"
  "ios/Pods"
  "ios/.symlinks"
  "ios/Flutter/ephemeral"
  "macos/Pods"
  "macos/.symlinks"
  "macos/Flutter/ephemeral"
  "linux/flutter/ephemeral"
  "windows/flutter/ephemeral"
  "web/.dart_tool"
  "coverage"
)

for rel in "${SAFE_DIRS[@]}"; do
  abs="$ROOT/$rel"
  if [[ -d "$abs" ]]; then
    echo "Deleting: $abs"
    rm -rf -- "$abs"
  else
    echo "Skip (not found): $abs"
  fi
done

echo "Cleanup complete."
