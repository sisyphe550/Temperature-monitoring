#!/usr/bin/env bash
# Gate tests for scripts/package-release.sh (TC-RELEASE packaging script).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/package-release.sh"
TEST_VERSION="gate-fixture"
REPORT="${ROOT}/docs/validation/releases/${TEST_VERSION}/report.md"

fail() {
  echo "test-package-release: $*" >&2
  exit 1
}

test_script_exists() {
  [[ -x "${SCRIPT}" ]] || fail "missing executable ${SCRIPT}"
}

test_required_pipeline_present() {
  local body
  body="$(<"${SCRIPT}")"
  for token in \
    "validate-handoff.py" \
    "build-app.sh" \
    "check-upstream-boundary.py" \
    "codesign --force --options runtime --timestamp" \
    "notarytool submit" \
    "stapler staple" \
    "spctl --assess" \
    "TemperatureMonitor-notarized.zip"
  do
    [[ "${body}" == *"${token}"* ]] || fail "script missing expected step: ${token}"
  done
  if [[ "${body}" == *"--deep"* && "${body}" == *"codesign --force"* ]]; then
    :
  fi
  if [[ "${body}" == *"codesign --deep"* ]]; then
    fail "must not use codesign --deep as signing strategy"
  fi
}

test_missing_credentials_fail_closed() {
  rm -rf "${ROOT}/docs/validation/releases/${TEST_VERSION}"
  set +e
  env -i PATH="${PATH}" HOME="${HOME}" RELEASE_VERSION="${TEST_VERSION}" bash "${SCRIPT}" \
    > /tmp/test-package-release.out 2> /tmp/test-package-release.err
  local status=$?
  set -e
  [[ "${status}" -eq 2 ]] || fail "expected exit 2 without credentials, got ${status}"
  grep -q "external dependency" /tmp/test-package-release.err || fail "missing external dependency message"
  [[ -f "${REPORT}" ]] || fail "blocking report not written"
  grep -q "pending external credentials" "${REPORT}" || fail "blocking report missing pending status"
}

test_no_secret_logging_patterns() {
  local body
  body="$(<"${SCRIPT}")"
  for forbidden in "p12" "password=" "API_KEY" "private-key"; do
    [[ "${body}" != *"${forbidden}"* ]] || fail "script contains forbidden logging pattern: ${forbidden}"
  done
}

main() {
  test_script_exists
  test_required_pipeline_present
  test_missing_credentials_fail_closed
  test_no_secret_logging_patterns
  rm -rf "${ROOT}/docs/validation/releases/${TEST_VERSION}"
  echo "package release script: 4 checks passed"
}

main "$@"
