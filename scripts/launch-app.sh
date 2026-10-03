#!/usr/bin/env bash
set -euo pipefail
TASK_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_APP_PATH="${TASK_PROJECT_ROOT}/build/TemperatureMonitor.app"
if [[ ! -d "$TASK_APP_PATH" ]]; then
  printf '%s\n' 'Build the local App first: bash scripts/build-app.sh' >&2
  exit 1
fi
# Standard LaunchServices startup/reopen. No Release-only UI flags or fixture arguments.
open "$TASK_APP_PATH"
