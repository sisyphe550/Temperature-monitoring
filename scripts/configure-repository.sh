#!/usr/bin/env bash
# Idempotent GitHub repository merge and ruleset configuration for W00.
# Do not pass --require-blocking-issues until that check has succeeded on a
# trusted default-branch workflow run against a real open PR head.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-sisyphe550/Temperature-monitoring}"
REQUIRE_BLOCKING=0

usage() {
  echo "Usage: $0 [--require-blocking-issues]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-blocking-issues)
      REQUIRE_BLOCKING=1
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

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

gh api -X PATCH "repos/${REPO}" \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=false \
  -F allow_update_branch=true >/dev/null

ensure_label() {
  local name="$1"
  local color="$2"
  local description="$3"
  if gh api "repos/${REPO}/labels/${name}" >/dev/null 2>&1; then
    gh api -X PATCH "repos/${REPO}/labels/${name}" \
      -f new_name="${name}" \
      -f color="${color}" \
      -f description="${description}" >/dev/null
  else
    gh api -X POST "repos/${REPO}/labels" \
      -f name="${name}" \
      -f color="${color}" \
      -f description="${description}" >/dev/null
  fi
}

ensure_label "bug" "d73a4a" "可复现缺陷"
ensure_label "blocking" "b60205" "阻塞当前里程碑或合并"
ensure_label "hardware" "0e8a16" "实机相关"

STATUS_CHECKS='[{"context":"handoff-docs"},{"context":"probe-tests"}]'
if [[ "${REQUIRE_BLOCKING}" -eq 1 ]]; then
  STATUS_CHECKS='[{"context":"handoff-docs"},{"context":"probe-tests"},{"context":"blocking-issues"}]'
fi

RULESET_PAYLOAD="$(python3 - "${STATUS_CHECKS}" <<'PY'
import json
import sys

checks = json.loads(sys.argv[1])
payload = {
    "name": "main-protection",
    "target": "branch",
    "enforcement": "active",
    "bypass_actors": [],
    "conditions": {
        "ref_name": {
            "include": ["refs/heads/main"],
            "exclude": [],
        }
    },
    "rules": [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {
            "type": "pull_request",
            "parameters": {
                "required_approving_review_count": 0,
                "dismiss_stale_reviews_on_push": False,
                "require_code_owner_review": False,
                "require_last_push_approval": False,
                "required_review_thread_resolution": True,
                "allowed_merge_methods": ["merge"],
            },
        },
        {
            "type": "required_status_checks",
            "parameters": {
                "strict_required_status_checks_policy": True,
                "do_not_enforce_on_create": False,
                "required_status_checks": checks,
            },
        },
    ],
}
json.dump(payload, sys.stdout)
PY
)"

EXISTING_ID="$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="main-protection") | .id' || true)"
if [[ -n "${EXISTING_ID}" ]]; then
  printf '%s' "${RULESET_PAYLOAD}" | gh api -X PUT "repos/${REPO}/rulesets/${EXISTING_ID}" --input - >/dev/null
else
  printf '%s' "${RULESET_PAYLOAD}" | gh api -X POST "repos/${REPO}/rulesets" --input - >/dev/null
fi

gh api "repos/${REPO}" --jq '{allow_merge_commit,allow_squash_merge,allow_rebase_merge,delete_branch_on_merge}'
gh api "repos/${REPO}/rulesets"
echo "blocking_required=${REQUIRE_BLOCKING}"
