#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: push-content.sh --id <resource-id> --payload <json-file> [--resource-type <type>] [--allowlist <path>] [--response-out <path>] [--dry-run]

Push ACF content update through WP REST API with allowlist validation.
Payload must be a JSON object containing only:
{
  "acf": { ... }
}
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
PAYLOAD_PATH=""
ALLOWLIST_PATH=""
RESPONSE_OUT=""
DRY_RUN=0

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
    --payload)
      [[ $# -ge 2 ]] || fail "Missing value for --payload"
      PAYLOAD_PATH="$2"
      shift 2
      ;;
    --allowlist)
      [[ $# -ge 2 ]] || fail "Missing value for --allowlist"
      ALLOWLIST_PATH="$2"
      shift 2
      ;;
    --response-out)
      [[ $# -ge 2 ]] || fail "Missing value for --response-out"
      RESPONSE_OUT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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
[[ -n "${PAYLOAD_PATH}" ]] || fail "--payload is required"
[[ -f "${PAYLOAD_PATH}" ]] || fail "Payload file not found: ${PAYLOAD_PATH}"

require_command jq
require_command curl

load_api_config

if [[ -z "${RESOURCE_TYPE}" ]]; then
  RESOURCE_TYPE="${DEFAULT_RESOURCE_TYPE}"
fi
is_allowed_resource_type "${RESOURCE_TYPE}" "${ALLOWED_RESOURCE_TYPES}" || fail "--resource-type '${RESOURCE_TYPE}' is not allowlisted (${ALLOWED_RESOURCE_TYPES})"

# Validate against field names (what REST API uses), not field keys.
# --allowlist flag overrides; otherwise use the generated names file.
if [[ -z "${ALLOWLIST_PATH}" ]]; then
  ALLOWLIST_PATH="${CONTENT_API_FIELD_NAMES_FILE}"
fi
[[ -f "${ALLOWLIST_PATH}" ]] || fail "Allowlist file not found: ${ALLOWLIST_PATH}. Run scripts/build-allowlist.sh first."
[[ -s "${ALLOWLIST_PATH}" ]] || fail "Allowlist file is empty: ${ALLOWLIST_PATH}"

jq -e 'type=="object" and (keys - ["acf"] | length == 0) and .acf and (.acf | type=="object")' "${PAYLOAD_PATH}" >/dev/null \
  || fail "Payload must be a JSON object with only an 'acf' object."

tmp_payload_keys="$(mktemp)"
tmp_allowlist="$(mktemp)"
tmp_invalid="$(mktemp)"

jq -r '.acf | keys[]?' "${PAYLOAD_PATH}" | sort -u > "${tmp_payload_keys}"
sort -u "${ALLOWLIST_PATH}" > "${tmp_allowlist}"

if [[ ! -s "${tmp_payload_keys}" ]]; then
  rm -f "${tmp_payload_keys}" "${tmp_allowlist}" "${tmp_invalid}"
  fail "Payload has no ACF keys to update."
fi

comm -23 "${tmp_payload_keys}" "${tmp_allowlist}" > "${tmp_invalid}" || true
if [[ -s "${tmp_invalid}" ]]; then
  echo "Payload contains keys outside allowlist:" >&2
  sed 's/^/  - /' "${tmp_invalid}" >&2
  rm -f "${tmp_payload_keys}" "${tmp_allowlist}" "${tmp_invalid}"
  exit 1
fi

url="$(build_resource_url "${RESOURCE_TYPE}" "${RESOURCE_ID}")"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Dry-run validation passed."
  echo "Would POST to: ${url}"
  echo "ACF fields:"
  sed 's/^/  - /' "${tmp_payload_keys}"
  rm -f "${tmp_payload_keys}" "${tmp_allowlist}" "${tmp_invalid}"
  exit 0
fi

require_api_auth

if [[ -z "${RESPONSE_OUT}" ]]; then
  RESPONSE_OUT="${CONTENT_API_RUNTIME_DIR}/push-${RESOURCE_TYPE}-${RESOURCE_ID}-response.json"
fi
mkdir -p "$(dirname -- "${RESPONSE_OUT}")"

tmp_response="$(mktemp)"

echo "Posting update to ${url}"
curl -sS --fail --show-error \
  --connect-timeout "${WP_API_TIMEOUT_SECONDS}" \
  --max-time "${WP_API_TIMEOUT_SECONDS}" \
  "${CURL_AUTH_ARGS[@]}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST \
  --data-binary "@${PAYLOAD_PATH}" \
  "${url}" > "${tmp_response}"

jq -e '.acf | type=="object"' "${tmp_response}" >/dev/null || fail "Response does not contain an ACF object."

missing_any=0
while IFS= read -r key; do
  [[ -n "${key}" ]] || continue
  if ! jq -e --arg k "${key}" '.acf | has($k)' "${tmp_response}" >/dev/null; then
    echo "Missing updated key in response: ${key}" >&2
    missing_any=1
  fi
done < "${tmp_payload_keys}"

if [[ "${missing_any}" -ne 0 ]]; then
  rm -f "${tmp_payload_keys}" "${tmp_allowlist}" "${tmp_invalid}" "${tmp_response}"
  fail "Update response failed verification."
fi

mv "${tmp_response}" "${RESPONSE_OUT}"
rm -f "${tmp_payload_keys}" "${tmp_allowlist}" "${tmp_invalid}"

echo "Update applied successfully."
echo "Response written to: ${RESPONSE_OUT}"
