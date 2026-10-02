#!/bin/bash
# Runs the Swift Testing unit tests (BugWalletTests + BugWalletMessagesTests)
# with code coverage, prints per-target coverage, and fails when a target drops
# below MIN_COVERAGE percent.
#
#   Scripts/run_unit_tests.sh                        # iPhone 17, 95% floor
#   DEVICE="iPhone 17 Pro Max" Scripts/run_unit_tests.sh
#   MIN_COVERAGE=90 Scripts/run_unit_tests.sh
#   DEVELOPER_DIR=/Applications/Xcode-RC.app/Contents/Developer Scripts/run_unit_tests.sh
#
# Uses a simulator on the runtime that matches the active Xcode's iOS SDK. The
# tests never touch that simulator's real login, stamps, favorites or diary:
# the stores are pointed at scratch defaults suites for the run.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17}"
MIN_COVERAGE="${MIN_COVERAGE:-95}"
RESULT="${RESULT:-$(mktemp -d)/BugWalletTests.xcresult}"

SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"      # e.g. 26.5
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${SDK_VERSION//./-}"
UDID="$(xcrun simctl list -j devices available | jq -r --arg runtime "$RUNTIME" --arg name "$DEVICE" \
  '.devices[$runtime] // [] | map(select(.name == $name)) | first | .udid // empty')"
if [[ -z "$UDID" ]]; then
  echo "No available \"$DEVICE\" simulator on iOS $SDK_VERSION." >&2
  echo "Create one:  xcrun simctl create \"$DEVICE\" \"$DEVICE\" $RUNTIME" >&2
  exit 1
fi
echo "▶ $DEVICE, iOS $SDK_VERSION ($UDID)"

command -v xcodegen >/dev/null && xcodegen generate --quiet

xcodebuild test \
  -project BugWallet.xcodeproj \
  -scheme BugWallet \
  -only-testing:BugWalletTests \
  -only-testing:BugWalletMessagesTests \
  -destination "id=$UDID" \
  -resultBundlePath "$RESULT" \
  -quiet

xcrun xccov view --report --only-targets "$RESULT"

# The app and the order-logic bundle must each stay above the floor.
BELOW="$(xcrun xccov view --report --only-targets --json "$RESULT" |
  jq -r --argjson min "$MIN_COVERAGE" '.[] | select(.lineCoverage * 100 < $min) | .name')"
if [[ -n "$BELOW" ]]; then
  echo "✘ Coverage below ${MIN_COVERAGE}%: $BELOW" >&2
  exit 1
fi
echo "✔ Coverage ≥ ${MIN_COVERAGE}% (result bundle: $RESULT)"
