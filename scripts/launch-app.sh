#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/build/TemperatureMonitor.app"

if [[ ! -d "${APP}" ]]; then
  echo "error: missing ${APP}; run bash scripts/build-app.sh first" >&2
  exit 1
fi

xattr -cr "${APP}" 2>/dev/null || true

if pgrep -f "${APP}/Contents/MacOS/TemperatureMonitor" >/dev/null 2>&1; then
  echo "TemperatureMonitor is already running; opening dashboard..."
  open "${APP}" --args --open-dashboard
else
  echo "starting TemperatureMonitor with dashboard..."
  open "${APP}" --args --open-dashboard
fi

cat <<EOF

If macOS shows an unidentified-developer dialog:
  System Settings → Privacy & Security → Open Anyway
  or right-click the app → Open once.

Menu bar: look for the thermometer icon near the clock.
EOF
