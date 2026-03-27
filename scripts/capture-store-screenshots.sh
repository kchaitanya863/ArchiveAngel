#!/usr/bin/env bash
# Capture README / marketing screenshots via UI tests. Not run in normal CI.
# Requires: Xcode, Simulators matching the destinations below.
# Output: docs/store-screenshots/iphone/*.png and docs/store-screenshots/ipad/*.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Defaults: latest flagship sizes for App Store (override with *_SCREENSHOT_DESTINATION).
# If xcodebuild reports an ambiguous device, pin OS or use id=... (see xcrun simctl list devices available).
: "${IPHONE_SCREENSHOT_DESTINATION:=platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest}"
: "${IPAD_SCREENSHOT_DESTINATION:=platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest}"

run_one() {
  local dest="$1"
  local test_id="$2"
  xcodebuild test \
    -project ArchiveAngel.xcodeproj \
    -scheme "Store Screenshots" \
    -destination "$dest" \
    -only-testing:"$test_id"
}

# Store Screenshots scheme: screenshot tests are not in Archive Angel’s SkippedTests for this scheme.
run_one "$IPHONE_SCREENSHOT_DESTINATION" 'photo backupUITests/StoreScreenshotUITests/testCaptureStoreScreenshots_iPhone'
run_one "$IPAD_SCREENSHOT_DESTINATION" 'photo backupUITests/StoreScreenshotUITests/testCaptureStoreScreenshots_iPad'

echo "Wrote PNGs under docs/store-screenshots/iphone/ and docs/store-screenshots/ipad/ (commit for README and App Store)."
