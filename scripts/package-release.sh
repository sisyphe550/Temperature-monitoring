#!/usr/bin/env bash
# Package, sign, notarize, and staple TemperatureMonitor for formal distribution.
# Requires: DEVELOPER_ID_APPLICATION, APPLE_TEAM_ID, Keychain profile temperature-monitor-notary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TemperatureMonitor"
APP="${ROOT}/build/${APP_NAME}.app"
WORKER="${APP}/Contents/MacOS/SensorWorker"
APP_BINARY="${APP}/Contents/MacOS/${APP_NAME}"
SUBMIT_ZIP="${ROOT}/build/${APP_NAME}.zip"
NOTARIZED_ZIP="${ROOT}/build/${APP_NAME}-notarized.zip"
NOTARY_PROFILE="temperature-monitor-notary"
RELEASE_VERSION="${RELEASE_VERSION:-0.1.0}"
EVIDENCE_DIR="${ROOT}/docs/validation/releases/${RELEASE_VERSION}"
MANIFEST="${ROOT}/build/release-manifest.json"

log() {
  printf '[package-release] %s\n' "$*"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

write_blocking_report() {
  local reason="$1"
  mkdir -p "${EVIDENCE_DIR}"
  cat > "${EVIDENCE_DIR}/report.md" <<EOF
# Release ${RELEASE_VERSION} — blocked

**Status:** pending external credentials  
**Recorded at:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")  
**Source tree:** $(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)

## Blocker

${reason}

## Required inputs (not stored in repository)

- \`DEVELOPER_ID_APPLICATION\` — Developer ID Application identity in Keychain
- \`APPLE_TEAM_ID\` — Apple Team ID
- Keychain profile \`${NOTARY_PROFILE}\` for \`xcrun notarytool\`

Local ad-hoc App from \`scripts/build-app.sh\` remains the W01–W09 delivery artifact until credentials are supplied.
EOF
  log "wrote blocking report ${EVIDENCE_DIR}/report.md"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

check_credentials() {
  local missing=()
  if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    missing+=("DEVELOPER_ID_APPLICATION")
  fi
  if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
    missing+=("APPLE_TEAM_ID")
  fi
  if ((${#missing[@]} > 0)); then
    write_blocking_report "Missing environment variables: ${missing[*]}"
    echo "error: release credentials not configured (${missing[*]})" >&2
    echo "error: formal notarized release is an external dependency; local App delivery is unchanged" >&2
    exit 2
  fi
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "${DEVELOPER_ID_APPLICATION}" | grep -q .; then
    write_blocking_report "Developer ID identity not found in Keychain: ${DEVELOPER_ID_APPLICATION}"
    echo "error: codesigning identity not available in Keychain" >&2
    exit 2
  fi
  if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" --pagesize 1 >/dev/null 2>&1; then
    write_blocking_report "Notarytool Keychain profile unavailable: ${NOTARY_PROFILE}"
    echo "error: notarytool profile ${NOTARY_PROFILE} is not configured" >&2
    exit 2
  fi
}

run_preflight() {
  log "running handoff validation"
  python3 "${ROOT}/scripts/validate-handoff.py" >/dev/null
}

sign_release_binaries() {
  log "signing SensorWorker (Developer ID, hardened runtime)"
  codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${WORKER}"
  log "signing ${APP_NAME}.app"
  codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${APP}"
  codesign --verify --deep --strict --verbose=2 "${APP}"
}

submit_and_staple() {
  log "creating submission zip"
  rm -f "${SUBMIT_ZIP}"
  ditto -c -k --keepParent "${APP}" "${SUBMIT_ZIP}"

  log "submitting to Apple notary service"
  xcrun notarytool submit "${SUBMIT_ZIP}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

  log "stapling ticket"
  xcrun stapler staple "${APP}"
  xcrun stapler validate "${APP}"

  log "assessing Gatekeeper policy"
  spctl --assess --type execute --verbose=2 "${APP}"

  log "creating notarized distribution zip"
  rm -f "${NOTARIZED_ZIP}"
  ditto -c -k --keepParent "${APP}" "${NOTARIZED_ZIP}"
}

write_release_manifest() {
  mkdir -p "${EVIDENCE_DIR}"
  RELEASE_VERSION="${RELEASE_VERSION}" \
  APPLE_TEAM_ID="${APPLE_TEAM_ID}" \
  DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION}" \
  NOTARY_PROFILE="${NOTARY_PROFILE}" \
  ROOT="${ROOT}" \
  MANIFEST="${MANIFEST}" \
  EVIDENCE_MANIFEST="${EVIDENCE_DIR}/manifest.json" \
  python3 <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ["ROOT"])
sys.path.insert(0, str(root / "scripts"))
from product_qualification import collect_platform, sha256_file  # noqa: E402

app = root / "build/TemperatureMonitor.app"
worker = app / "Contents/MacOS/SensorWorker"
zip_path = root / "build/TemperatureMonitor-notarized.zip"
notices = app / "Contents/Resources/ThirdPartyNotices.md"
platform = collect_platform(app, root / "docs/contracts/first-profile-v1.json", "release")
payload = {
    "schema_version": 1,
    "artifact_kind": "product-release-manifest",
    "recorded_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "release_version": os.environ["RELEASE_VERSION"],
    "source_tree_sha": __import__("subprocess")
    .check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True)
    .strip(),
    "apple_team_id": os.environ["APPLE_TEAM_ID"],
    "codesign_identity": os.environ["DEVELOPER_ID_APPLICATION"],
    "app_sha256": sha256_file(app / "Contents/MacOS/TemperatureMonitor"),
    "worker_sha256": sha256_file(worker),
    "zip_sha256": sha256_file(zip_path),
    "third_party_contract_sha256": sha256_file(root / "docs/contracts/third-party-v1.json"),
    "third_party_notices_sha256": sha256_file(notices) if notices.is_file() else None,
    "build_toolchain": platform["build_toolchain"],
    "deployment_target": platform["deployment_target"],
    "runtime_profile": platform["runtime_profile"],
    "qualified_combinations": platform.get("qualified_combinations", []),
    "notary_keychain_profile": os.environ["NOTARY_PROFILE"],
    "distribution_zip": "build/TemperatureMonitor-notarized.zip",
}
text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
Path(os.environ["MANIFEST"]).write_text(text, encoding="utf-8")
Path(os.environ["EVIDENCE_MANIFEST"]).write_text(text, encoding="utf-8")
PY
}

write_success_report() {
  mkdir -p "${EVIDENCE_DIR}"
  cat > "${EVIDENCE_DIR}/report.md" <<EOF
# Release ${RELEASE_VERSION} — notarized

**Status:** notarized zip produced locally  
**Recorded at:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")  
**Source tree:** $(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)

Artifacts:

- \`build/TemperatureMonitor-notarized.zip\`
- \`build/release-manifest.json\`
- \`${EVIDENCE_DIR}/manifest.json\`

Public upload and release announcement remain maintainer actions outside this repository.
EOF
}

main() {
  require_command codesign
  require_command ditto
  require_command xcrun
  require_command spctl
  require_command python3
  require_command security

  run_preflight
  check_credentials

  log "building current source App"
  bash "${ROOT}/scripts/build-app.sh"

  log "running upstream boundary scan"
  python3 "${ROOT}/scripts/check-upstream-boundary.py"

  if [[ ! -x "${WORKER}" || ! -d "${APP}" ]]; then
    echo "error: expected app bundle at ${APP}" >&2
    exit 1
  fi

  sign_release_binaries
  submit_and_staple
  write_release_manifest
  write_success_report

  log "release complete: ${NOTARIZED_ZIP}"
  log "app sha256: $(sha256_file "${APP}")"
  log "zip sha256: $(sha256_file "${NOTARIZED_ZIP}")"
}

main "$@"
