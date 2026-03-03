#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pull-content.sh --id <resource-id> [--resource-type <type>] [--out <raw-json-path>] [--acf-out <acf-json-path>]

Fetch one WP REST resource and write:
1) Raw response JSON
2) Extracted .acf object JSON
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

RESOURCE_ID=""
RESOURCE_TYPE=""
OUT_PATH=""
ACF_OUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      [[ $# -ge 2 ]] || fail "Missing value for --id"
      RESOURCE_ID="$2"
      shift 2
      ;;
    --resource-type)
      [[ $# -ge 2 ]] || fail "Missing value for --resource-type"
      RESOURCE_TYPE="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || fail "Missing value for --out"
      OUT_PATH="$2"
      shift 2
      ;;
    --acf-out)
      [[ $# -ge 2 ]] || fail "Missing value for --acf-out"
      ACF_OUT_PATH="$2"
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

[[ -n "${RESOURCE_ID}" ]] || fail "--id is required"
is_positive_integer "${RESOURCE_ID}" || fail "--id must be a positive integer"

require_command curl
require_command jq

load_api_config
require_api_auth

if [[ -z "${RESOURCE_TYPE}" ]]; then
  RESOURCE_TYPE="${DEFAULT_RESOURCE_TYPE}"
fi
is_allowed_resource_type "${RESOURCE_TYPE}" "${ALLOWED_RESOURCE_TYPES}" || fail "--resource-type '${RESOURCE_TYPE}' is not allowlisted (${ALLOWED_RESOURCE_TYPES})"

if [[ -z "${OUT_PATH}" ]]; then
  OUT_PATH="${CONTENT_API_RUNTIME_DIR}/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-raw.json"
fi
if [[ -z "${ACF_OUT_PATH}" ]]; then
  ACF_OUT_PATH="${CONTENT_API_RUNTIME_DIR}/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-acf.json"
fi

mkdir -p "$(dirname -- "${OUT_PATH}")" "$(dirname -- "${ACF_OUT_PATH}")"

base_url="$(build_resource_url "${RESOURCE_TYPE}" "${RESOURCE_ID}")"
tmp_response="$(mktemp)"

if [[ "${AUTH_MODE}" == "plugin_secret" ]]; then
  url="${base_url}"
  echo "Fetching ${url}"
  curl -sS --fail --show-error \
    --connect-timeout "${WP_API_TIMEOUT_SECONDS}" \
    --max-time "${WP_API_TIMEOUT_SECONDS}" \
    "${CURL_AUTH_ARGS[@]}" \
    -H "Accept: application/json" \
    "${url}" > "${tmp_response}"
else
  # Try context=edit first (returns raw/unrendered values, needs edit_post cap).
  # Fall back to view context if the user/app-password lacks edit permissions.
  url="${base_url}?context=edit"
  echo "Fetching ${url}"
  if ! curl -sS --fail --show-error \
    --connect-timeout "${WP_API_TIMEOUT_SECONDS}" \
    --max-time "${WP_API_TIMEOUT_SECONDS}" \
    "${CURL_AUTH_ARGS[@]}" \
    -H "Accept: application/json" \
    "${url}" > "${tmp_response}" 2>/dev/null; then

    echo "context=edit returned 401 — falling back to view context."
    url="${base_url}"
    echo "Fetching ${url}"
    curl -sS --fail --show-error \
      --connect-timeout "${WP_API_TIMEOUT_SECONDS}" \
      --max-time "${WP_API_TIMEOUT_SECONDS}" \
      "${CURL_AUTH_ARGS[@]}" \
      -H "Accept: application/json" \
      "${url}" > "${tmp_response}"
  fi
fi

jq -e 'type=="object"' "${tmp_response}" >/dev/null || fail "Response is not a JSON object."
jq -e '.acf | type=="object"' "${tmp_response}" >/dev/null || fail "Response does not include an ACF object. Ensure ACF REST integration is enabled for this resource."

cp "${tmp_response}" "${OUT_PATH}"
jq '.acf' "${tmp_response}" > "${ACF_OUT_PATH}"
rm -f "${tmp_response}"

echo "Raw response written to: ${OUT_PATH}"
echo "ACF content written to: ${ACF_OUT_PATH}"
