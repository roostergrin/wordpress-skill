#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap-repo.sh (--claim-token <token> | --claim-url <url>) [--verify-id <resource-id>]

Claim a site-specific automation secret and write the managed keys into ./.env.
Run this from the target repo root.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./api-common.sh
source "${SCRIPT_DIR}/api-common.sh"
CONTENT_API_SCRIPT="${SKILL_ROOT}/../wp-acf-content-api/scripts/pull-content.sh"

CLAIM_TOKEN=""
CLAIM_URL=""
VERIFY_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claim-token)
      [[ $# -ge 2 ]] || fail "Missing value for --claim-token"
      CLAIM_TOKEN="$2"
      shift 2
      ;;
    --claim-url)
      [[ $# -ge 2 ]] || fail "Missing value for --claim-url"
      CLAIM_URL="$2"
      shift 2
      ;;
    --verify-id)
      [[ $# -ge 2 ]] || fail "Missing value for --verify-id"
      VERIFY_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${CLAIM_TOKEN}" || -n "${CLAIM_URL}" ]] || fail "Provide --claim-token or --claim-url."
[[ -z "${CLAIM_TOKEN}" || -z "${CLAIM_URL}" ]] || fail "Use only one of --claim-token or --claim-url."

require_command jq
require_command curl

BASE_URL=""
if [[ -n "${CLAIM_URL}" ]]; then
  claim_url_no_fragment="${CLAIM_URL%%#*}"
  BASE_URL="$(printf '%s' "${claim_url_no_fragment}" | sed -E 's#(https?://[^/]+).*#\1#')"
  CLAIM_TOKEN="$(printf '%s' "${claim_url_no_fragment}" | sed -nE 's#.*[?&]claim_token=([^&]+).*#\1#p')"
  [[ -n "${CLAIM_TOKEN}" ]] || fail "Could not extract claim_token from --claim-url."
  CLAIM_TOKEN="${CLAIM_TOKEN//%20/ }"
fi

if [[ -z "${BASE_URL}" ]]; then
  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
  fi
  BASE_URL="${TARGET_BASE_URL:-${WP_API_BASE_URL:-}}"
fi

[[ -n "${BASE_URL}" ]] || fail "TARGET_BASE_URL must already exist in ${WORKSPACE_ENV_FILE} when using --claim-token."
BASE_URL="${BASE_URL%/}"

mkdir -p "${BOOTSTRAP_RUNTIME_DIR}"
STATUS_OUT="${BOOTSTRAP_RUNTIME_DIR}/bootstrap-status.json"
CLAIM_OUT="${BOOTSTRAP_RUNTIME_DIR}/bootstrap-claim-response.json"

CLAIM_ENDPOINT="${BASE_URL}/wp-json/acf-automation/v1/bootstrap/claim"
tmp_response="$(mktemp)"
tmp_payload="$(mktemp)"
trap 'rm -f "${tmp_response}" "${tmp_payload}"' EXIT

jq -n --arg claim_token "${CLAIM_TOKEN}" '{claim_token: $claim_token}' > "${tmp_payload}"

http_code="$(curl -sS --show-error \
  --connect-timeout 30 \
  --max-time 30 \
  -H "Content-Type: application/json" \
  -X POST \
  --data-binary "@${tmp_payload}" \
  -o "${tmp_response}" \
  -w "%{http_code}" \
  "${CLAIM_ENDPOINT}")"

[[ "${http_code}" =~ ^[0-9]{3}$ ]] || fail "Unexpected HTTP status from claim endpoint: ${http_code}"
if (( http_code >= 400 )); then
  if jq -e '.' "${tmp_response}" >/dev/null 2>&1; then
    jq '.' "${tmp_response}" >&2
  else
    cat "${tmp_response}" >&2
  fi
  fail "Claim endpoint returned HTTP ${http_code}"
fi

jq -e '.site_id and .automation_secret and .target_base_url and .schema_pull_path and .schema_push_path and .content_base_path' "${tmp_response}" >/dev/null \
  || fail "Claim response missing required fields."

jq '.' "${tmp_response}" > "${CLAIM_OUT}"

managed_keys=(
  TARGET_BASE_URL
  ACF_AUTOMATION_SITE_ID
  ACF_AUTOMATION_SECRET
  ACF_AUTOMATION_SCHEMA_PULL_PATH
  ACF_AUTOMATION_SCHEMA_PUSH_PATH
  ACF_AUTOMATION_CONTENT_BASE_PATH
)
TARGET_BASE_URL_VALUE="$(jq -r '.target_base_url' "${CLAIM_OUT}" | sed 's#/$##')"
ACF_AUTOMATION_SITE_ID_VALUE="$(jq -r '.site_id' "${CLAIM_OUT}")"
ACF_AUTOMATION_SECRET_VALUE="$(jq -r '.automation_secret' "${CLAIM_OUT}")"
ACF_AUTOMATION_SCHEMA_PULL_PATH_VALUE="$(jq -r '.schema_pull_path' "${CLAIM_OUT}")"
ACF_AUTOMATION_SCHEMA_PUSH_PATH_VALUE="$(jq -r '.schema_push_path' "${CLAIM_OUT}")"
ACF_AUTOMATION_CONTENT_BASE_PATH_VALUE="$(jq -r '.content_base_path' "${CLAIM_OUT}")"

if jq -e '.allowed_resource_types | type=="array"' "${CLAIM_OUT}" >/dev/null 2>&1; then
  managed_keys+=(ALLOWED_RESOURCE_TYPES)
  ALLOWED_RESOURCE_TYPES_VALUE="$(jq -r '.allowed_resource_types | join(",")' "${CLAIM_OUT}")"
fi

env_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  printf '"%s"' "${value}"
}

managed_value() {
  case "$1" in
    TARGET_BASE_URL) printf '%s' "${TARGET_BASE_URL_VALUE}" ;;
    ACF_AUTOMATION_SITE_ID) printf '%s' "${ACF_AUTOMATION_SITE_ID_VALUE}" ;;
    ACF_AUTOMATION_SECRET) printf '%s' "${ACF_AUTOMATION_SECRET_VALUE}" ;;
    ACF_AUTOMATION_SCHEMA_PULL_PATH) printf '%s' "${ACF_AUTOMATION_SCHEMA_PULL_PATH_VALUE}" ;;
    ACF_AUTOMATION_SCHEMA_PUSH_PATH) printf '%s' "${ACF_AUTOMATION_SCHEMA_PUSH_PATH_VALUE}" ;;
    ACF_AUTOMATION_CONTENT_BASE_PATH) printf '%s' "${ACF_AUTOMATION_CONTENT_BASE_PATH_VALUE}" ;;
    ALLOWED_RESOURCE_TYPES) printf '%s' "${ALLOWED_RESOURCE_TYPES_VALUE:-}" ;;
    *) fail "Unknown managed key: $1" ;;
  esac
}

key_seen() {
  local key="$1"
  shift
  local seen_key
  for seen_key in "$@"; do
    if [[ "${seen_key}" == "${key}" ]]; then
      return 0
    fi
  done
  return 1
}

tmp_env="$(mktemp)"
if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
  cp "${WORKSPACE_ENV_FILE}" "${WORKSPACE_ENV_FILE}.bak"
  seen_keys=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^([A-Z0-9_]+)= ]]; then
      key="${BASH_REMATCH[1]}"
      replaced=0
      for managed_key in "${managed_keys[@]}"; do
        if [[ "${key}" == "${managed_key}" ]]; then
          printf '%s=%s\n' "${managed_key}" "$(env_escape "$(managed_value "${managed_key}")")" >> "${tmp_env}"
          seen_keys+=("${managed_key}")
          replaced=1
          break
        fi
      done
      if [[ "${replaced}" -eq 1 ]]; then
        continue
      fi
    fi
    printf '%s\n' "${line}" >> "${tmp_env}"
  done < "${WORKSPACE_ENV_FILE}"

  for managed_key in "${managed_keys[@]}"; do
    if ! key_seen "${managed_key}" "${seen_keys[@]}"; then
      printf '%s=%s\n' "${managed_key}" "$(env_escape "$(managed_value "${managed_key}")")" >> "${tmp_env}"
    fi
  done
else
  for managed_key in "${managed_keys[@]}"; do
    printf '%s=%s\n' "${managed_key}" "$(env_escape "$(managed_value "${managed_key}")")" >> "${tmp_env}"
  done
fi

mv "${tmp_env}" "${WORKSPACE_ENV_FILE}"
chmod 600 "${WORKSPACE_ENV_FILE}"

echo "Wrote managed automation keys to ${WORKSPACE_ENV_FILE}"
echo "Claim response written to: ${CLAIM_OUT}"

echo "Verifying schema pull..."
bash "${SCRIPT_DIR}/pull.sh" --dry-run > "${STATUS_OUT}"
echo "Schema dry-run verification written to: ${STATUS_OUT}"

if [[ -n "${VERIFY_ID}" ]]; then
  echo "Verifying content pull for resource ${VERIFY_ID}..."
  bash "${CONTENT_API_SCRIPT}" --resource-type pages --id "${VERIFY_ID}" >/dev/null
  echo "Content verification succeeded for resource ${VERIFY_ID}"
fi
