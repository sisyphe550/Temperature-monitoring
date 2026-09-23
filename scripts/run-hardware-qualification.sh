#!/usr/bin/env bash
# Collect W09 product hardware qualification evidence from the production App bundle.
# The legacy sensor-probe prototype must never substitute for App/worker execution.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=""
PROFILE=""
SUITE=""
OUTPUT=""
DURATION=""
CHECKPOINT_INTERVAL=""
USE_PROBE=0

usage() {
  echo "Usage: $0 --app PATH --profile PATH --suite NAME --output DIR [--duration-seconds N] [--checkpoint-interval-seconds N] [--dry-run]" >&2
  echo "Suites: dry-run, sources, schedules, lifecycle, endurance, full" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --suite)
      SUITE="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --dry-run)
      SUITE="dry-run"
      shift
      ;;
    --duration-seconds)
      DURATION="$2"
      shift 2
      ;;
    --checkpoint-interval-seconds)
      CHECKPOINT_INTERVAL="$2"
      shift 2
      ;;
    --use-probe)
      USE_PROBE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${APP}" || -z "${PROFILE}" || -z "${SUITE}" || -z "${OUTPUT}" ]]; then
  usage
  exit 1
fi

if [[ "${USE_PROBE}" -eq 1 ]]; then
  echo "error: sensor-probe backend is forbidden for product qualification" >&2
  exit 1
fi

if [[ "${SUITE}" != "dry-run" && -x "${ROOT}/prototypes/sensor-probe/.build/release/sensor-probe" ]]; then
  echo "error: full qualification must run the production App, not sensor-probe" >&2
  exit 1
fi

ARGS=(collect --app "${APP}" --profile "${PROFILE}" --suite "${SUITE}" --output "${OUTPUT}")
if [[ -n "${DURATION}" ]]; then
  ARGS+=(--duration-seconds "${DURATION}")
fi
if [[ -n "${CHECKPOINT_INTERVAL}" ]]; then
  ARGS+=(--checkpoint-interval-seconds "${CHECKPOINT_INTERVAL}")
fi
if [[ "${USE_PROBE}" -eq 1 ]]; then
  ARGS+=(--use-probe)
fi

python3 "${ROOT}/scripts/product_qualification.py" "${ARGS[@]}"
