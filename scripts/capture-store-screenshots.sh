#!/usr/bin/env bash
# Capture README / marketing screenshots via UI test. Not run in normal CI.
# Requires: Xcode, an iOS Simulator matching SCREENSHOT_DESTINATION.
# Output: docs/store-screenshots/README/*.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# If xcodebuild reports an ambiguous device, pin OS or pass id=..., e.g.:
#   SCREENSHOT_DESTINATION='platform=iOS Simulator,id=6816CEEA-3C2D-4558-A528-0FB6F2F35E78' ./scripts/capture-store-screenshots.sh
# List: xcrun simctl list devices available
: "${SCREENSHOT_DESTINATION:=platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.5}"

# Uses the Store Screenshots scheme so this test is not skipped (it is skipped in the Archive Angel scheme).
xcodebuild test \
  -project ArchiveAngel.xcodeproj \
  -scheme "Store Screenshots" \
  -destination "$SCREENSHOT_DESTINATION" \
  -only-testing:'photo backupUITests/StoreScreenshotUITests/testCaptureStoreScreenshots'

echo "Wrote PNGs under docs/store-screenshots/README/ (commit them for README and App Store 6.7\" uploads when captured on a 6.7\" simulator)."
