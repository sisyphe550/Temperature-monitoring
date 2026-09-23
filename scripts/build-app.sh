#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${ROOT}/build/DerivedData"
APP_NAME="TemperatureMonitor"
OUTPUT_APP="${ROOT}/build/${APP_NAME}.app"
WORKER_PRODUCT="SensorWorker"
PACKAGE_PATH="${ROOT}/Packages/TemperatureCore"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found; full Xcode is required" >&2
  exit 1
fi

if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  echo "error: full Xcode.app must be selected via xcode-select" >&2
  exit 1
fi

WORKER_BUILD_FLAGS=(-Xswiftc -target -Xswiftc arm64-apple-macos15.7.3)

echo "building ${WORKER_PRODUCT} (release)..."
swift build --package-path "${PACKAGE_PATH}" --product "${WORKER_PRODUCT}" -c release "${WORKER_BUILD_FLAGS[@]}"

WORKER_BIN="$(swift build --package-path "${PACKAGE_PATH}" --product "${WORKER_PRODUCT}" -c release "${WORKER_BUILD_FLAGS[@]}" --show-bin-path)/${WORKER_PRODUCT}"
if [[ ! -x "${WORKER_BIN}" ]]; then
  echo "error: missing worker binary at ${WORKER_BIN}" >&2
  exit 1
fi

echo "building ${APP_NAME} (release)..."
xcodebuild \
  -project "${ROOT}/TemperatureMonitor.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "error: missing app bundle at ${BUILT_APP}" >&2
  exit 1
fi

for resource in defaults-v1.json first-profile-v1.json third-party-v1.json ThirdPartyNotices.md; do
  if [[ ! -f "${BUILT_APP}/Contents/Resources/${resource}" ]]; then
    echo "error: missing bundled resource ${resource}" >&2
    exit 1
  fi
done

rm -rf "${OUTPUT_APP}"
ditto "${BUILT_APP}" "${OUTPUT_APP}"

MACOS_DIR="${OUTPUT_APP}/Contents/MacOS"
mkdir -p "${MACOS_DIR}"
install -m 755 "${WORKER_BIN}" "${MACOS_DIR}/SensorWorker"

echo "ad-hoc signing worker and app..."
codesign --force --sign - "${MACOS_DIR}/SensorWorker"
codesign --force --sign - "${OUTPUT_APP}"
xattr -cr "${OUTPUT_APP}" 2>/dev/null || true

echo "built ${OUTPUT_APP}"
cat <<EOF

Launch (recommended):
  bash scripts/launch-app.sh

First launch opens the main dashboard window automatically.
The menu bar also shows a thermometer icon with the current reading.
EOF
