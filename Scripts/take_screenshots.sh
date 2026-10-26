#!/bin/bash
# Runs the screenshot UI tests and writes the PNGs to docs/screenshots/<device>/ —
# one folder per simulator:
#
#   app      BugCoffeeUITests/ScreenshotTests.swift on each of $DEVICES
#            (iphone-17-pro/, ipad-mini-a17-pro/ — iPads in portrait and landscape)
#   watch    BugCoffeeWatchUITests on $WATCH_DEVICE (apple-watch-series-11-46mm/)
#   widgets  BugCoffeeUITests/WidgetScreenshotTests.swift — adds the Stamp Card
#            widgets to the home screen of a throwaway $WIDGET_DEVICE simulator,
#            which is deleted afterwards (images go to that device's folder)
#
#   Scripts/take_screenshots.sh                      # everything
#   SHOTS=watch,widgets Scripts/take_screenshots.sh  # just some of it
#   DEVICES="iPhone 17 Pro Max" Scripts/take_screenshots.sh
#   DEVICES="iPhone 17 Pro,iPad Pro 13-inch (M5)" Scripts/take_screenshots.sh
#   DEVELOPER_DIR=/Applications/Xcode-RC.app/Contents/Developer Scripts/take_screenshots.sh
#
# Uses simulators on the runtimes that match the active Xcode's iOS and watchOS
# SDKs and pins the iOS status bars (9:41 on a fixed date, full battery and
# signal) for the duration of the run. watchOS has no status bar override, so
# the watch shots show the Mac's current time.
set -euo pipefail

cd "$(dirname "$0")/.."

SHOTS="${SHOTS:-app,watch,widgets}"
DEVICES="${DEVICES:-iPhone 17 Pro,iPad mini (A17 Pro)}"
WATCH_DEVICE="${WATCH_DEVICE:-Apple Watch Series 11 (46mm)}"
WIDGET_DEVICE="${WIDGET_DEVICE:-iPhone 17 Pro}"
OUT_DIR="${OUT_DIR:-$PWD/docs/screenshots}"

wants() { [[ ",$SHOTS," == *",$1,"* ]]; }

SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"      # e.g. 26.5
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${SDK_VERSION//./-}"
WATCH_SDK_VERSION="$(xcrun --sdk watchsimulator --show-sdk-version)"
WATCH_RUNTIME="com.apple.CoreSimulator.SimRuntime.watchOS-${WATCH_SDK_VERSION//./-}"
SIMULATORS="$(xcrun simctl list -j devices available)"

# find_simulator <runtime> <name> → UDID, or exits with a hint.
find_simulator() {
  local udid
  udid="$(jq -r --arg runtime "$1" --arg name "$2" \
    '.devices[$runtime] // [] | map(select(.name == $name)) | first | .udid // empty' \
    <<< "$SIMULATORS")"
  if [[ -z "$udid" ]]; then
    echo "No available \"$2\" simulator on $1." >&2
    echo "Create one:  xcrun simctl create \"$2\" \"$2\" $1" >&2
    exit 1
  fi
  echo "$udid"
}

# 9:41 local time; simctl only takes a UTC timestamp with milliseconds.
STATUS_TIME="$(date -ju -r "$(date -j -f "%Y-%m-%d %H:%M:%S" "2026-01-13 09:41:00" +%s)" +%Y-%m-%dT%H:%M:%S.000Z)"

pin_status_bar() {
  xcrun simctl bootstatus "$1" -b >/dev/null
  xcrun simctl status_bar "$1" override \
    --time "$STATUS_TIME" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
}

PINNED=()
SCRATCH=""
cleanup() {
  for UDID in ${PINNED[@]+"${PINNED[@]}"}; do xcrun simctl status_bar "$UDID" clear || true; done
  if [[ -n "$SCRATCH" ]]; then
    xcrun simctl shutdown "$SCRATCH" 2>/dev/null || true
    xcrun simctl delete "$SCRATCH" || true
  fi
}
trap cleanup EXIT

command -v xcodegen >/dev/null && xcodegen generate --quiet

# --- App screens (iPhone + iPad, in parallel) --------------------------------
if wants app; then
  DESTINATIONS=()
  IFS=',' read -ra NAMES <<< "$DEVICES"
  for NAME in "${NAMES[@]}"; do
    UDID="$(find_simulator "$RUNTIME" "$NAME")"
    echo "▶ app: $NAME, iOS $SDK_VERSION ($UDID)"
    pin_status_bar "$UDID"
    PINNED+=("$UDID")
    DESTINATIONS+=(-destination "id=$UDID")
  done

  TEST_RUNNER_SCREENSHOTS_DIR="$OUT_DIR" xcodebuild test \
    -project BugCoffee.xcodeproj \
    -scheme BugCoffee \
    -only-testing:BugCoffeeUITests/ScreenshotTests \
    -enableCodeCoverage NO \
    "${DESTINATIONS[@]}" \
    -quiet
fi

# --- Watch app ---------------------------------------------------------------
if wants watch; then
  UDID="$(find_simulator "$WATCH_RUNTIME" "$WATCH_DEVICE")"
  echo "▶ watch: $WATCH_DEVICE, watchOS $WATCH_SDK_VERSION ($UDID)"
  xcrun simctl bootstatus "$UDID" -b >/dev/null

  # The watch simulator now and then refuses to relaunch the app between tests
  # ("FBSApplicationLibrary returned nil"); a retry of just that test gets past it.
  TEST_RUNNER_SCREENSHOTS_DIR="$OUT_DIR" xcodebuild test \
    -project BugCoffee.xcodeproj \
    -scheme BugCoffeeWatch \
    -destination "id=$UDID" \
    -retry-tests-on-failure -test-iterations 3 \
    -quiet
fi

# --- Home-screen widgets (throwaway simulator) -------------------------------
if wants widgets; then
  # The test changes the stamp count and the home screen, so it gets a fresh
  # simulator of its own rather than one of yours.
  SCRATCH="$(xcrun simctl create "$WIDGET_DEVICE (screenshots, temporary)" "$WIDGET_DEVICE" "$RUNTIME")"
  echo "▶ widgets: temporary $WIDGET_DEVICE, iOS $SDK_VERSION ($SCRATCH)"
  xcrun simctl boot "$SCRATCH"
  pin_status_bar "$SCRATCH"

  TEST_RUNNER_SCREENSHOTS_DIR="$OUT_DIR" \
  TEST_RUNNER_SCREENSHOTS_DEVICE="$WIDGET_DEVICE" \
  TEST_RUNNER_SCREENSHOTS_WIDGETS=1 \
  xcodebuild test \
    -project BugCoffee.xcodeproj \
    -scheme BugCoffee \
    -only-testing:BugCoffeeUITests/WidgetScreenshotTests \
    -enableCodeCoverage NO \
    -destination "id=$SCRATCH" \
    -quiet
fi

echo "✔ Screenshots in $OUT_DIR:"
(cd "$OUT_DIR" && ls -1 */*.png)
