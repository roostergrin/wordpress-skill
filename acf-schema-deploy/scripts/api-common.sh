#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="$(pwd -P)"
WORKSPACE_ENV_FILE="${WORKSPACE_ROOT}/.env"
WORKSPACE_RUNTIME_DIR="${WORKSPACE_ROOT}/runtime"
SCHEMA_DEPLOY_RUNTIME_DIR="${WORKSPACE_RUNTIME_DIR}/schema-deploy"
ACF_JSON_DIR="${WORKSPACE_ROOT}/wp-content/acf-json"
BOOTSTRAP_RUNTIME_DIR="${WORKSPACE_RUNTIME_DIR}/bootstrap"

export SKILL_ROOT
export WORKSPACE_ROOT
export WORKSPACE_ENV_FILE
export WORKSPACE_RUNTIME_DIR
export SCHEMA_DEPLOY_RUNTIME_DIR
export ACF_JSON_DIR
export BOOTSTRAP_RUNTIME_DIR

API_CURL_AUTH_ARGS=()
PUSH_SIGNATURE_HEADERS=()

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail "Required command not found: ${cmd}"
}

require_json_object() {
  local file="$1"
  local label="$2"
  if ! jq -e 'type == "object"' "${file}" >/dev/null 2>&1; then
    fail "${label} is not a valid JSON object: ${file}"
  fi
}

json_pretty_write() {
  local src="$1"
  local dest="$2"
  jq '.' "${src}" > "${dest}"
}

normalize_route_path() {
  local value="$1"
  [[ -n "${value}" ]] || fail "Route path cannot be empty."
  if [[ "${value}" != /* ]]; then
    value="/${value}"
  fi
  value="${value%/}"
  printf '%s' "${value}"
}

load_target_config() {
  local env_target_base_url="${TARGET_BASE_URL-}"
  local env_wp_api_base_url="${WP_API_BASE_URL-}"
  local env_target_curl_timeout="${TARGET_CURL_TIMEOUT-}"
  local env_target_api_user="${TARGET_API_USER-}"
  local env_wp_api_user="${WP_API_USER-}"
  local env_wp_api_username="${WP_API_USERNAME-}"
  local env_target_api_app_password="${TARGET_API_APP_PASSWORD-}"
  local env_wp_api_app_password="${WP_API_APP_PASSWORD-}"
  local env_target_api_hmac_secret="${TARGET_API_HMAC_SECRET-}"
  local env_acf_schema_api_hmac_secret="${ACF_SCHEMA_API_HMAC_SECRET-}"
  local env_acf_automation_site_id="${ACF_AUTOMATION_SITE_ID-}"
  local env_acf_automation_secret="${ACF_AUTOMATION_SECRET-}"
  local env_acf_automation_schema_pull_path="${ACF_AUTOMATION_SCHEMA_PULL_PATH-}"
  local env_acf_automation_schema_push_path="${ACF_AUTOMATION_SCHEMA_PUSH_PATH-}"
  local env_target_api_pull_path="${TARGET_API_PULL_PATH-}"
  local env_target_api_push_path="${TARGET_API_PUSH_PATH-}"
  local env_target_api_push_route="${TARGET_API_PUSH_ROUTE-}"

  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
  fi

  TARGET_BASE_URL="${env_target_base_url:-${env_wp_api_base_url:-${TARGET_BASE_URL:-${WP_API_BASE_URL:-}}}}"
  : "${TARGET_BASE_URL:?TARGET_BASE_URL (or WP_API_BASE_URL) must be set in ${WORKSPACE_ENV_FILE} or environment}"

  TARGET_BASE_URL="${TARGET_BASE_URL%/}"
  TARGET_CURL_TIMEOUT="${env_target_curl_timeout:-${TARGET_CURL_TIMEOUT:-30}}"
  TARGET_API_USER="${env_target_api_user:-${env_wp_api_user:-${env_wp_api_username:-${TARGET_API_USER:-${WP_API_USER:-${WP_API_USERNAME:-}}}}}}"
  TARGET_API_APP_PASSWORD="${env_target_api_app_password:-${env_wp_api_app_password:-${TARGET_API_APP_PASSWORD:-${WP_API_APP_PASSWORD:-}}}}"
  TARGET_API_HMAC_SECRET="${env_target_api_hmac_secret:-${env_acf_schema_api_hmac_secret:-${TARGET_API_HMAC_SECRET:-${ACF_SCHEMA_API_HMAC_SECRET:-}}}}"
  ACF_AUTOMATION_SITE_ID="${env_acf_automation_site_id:-${ACF_AUTOMATION_SITE_ID:-}}"
  ACF_AUTOMATION_SECRET="${env_acf_automation_secret:-${ACF_AUTOMATION_SECRET:-}}"
  ACF_AUTOMATION_SCHEMA_PULL_PATH="${env_acf_automation_schema_pull_path:-${ACF_AUTOMATION_SCHEMA_PULL_PATH:-/wp-json/acf-schema/v1/pull}}"
  ACF_AUTOMATION_SCHEMA_PUSH_PATH="${env_acf_automation_schema_push_path:-${ACF_AUTOMATION_SCHEMA_PUSH_PATH:-/wp-json/acf-schema/v1/push}}"
  TARGET_API_PULL_PATH="${env_target_api_pull_path:-${TARGET_API_PULL_PATH:-/wp-json/acf-schema/v1/pull}}"
  TARGET_API_PUSH_PATH="${env_target_api_push_path:-${TARGET_API_PUSH_PATH:-/wp-json/acf-schema/v1/push}}"
  TARGET_API_PUSH_ROUTE="${env_target_api_push_route:-${TARGET_API_PUSH_ROUTE:-/acf-schema/v1/push}}"

  if [[ -n "${ACF_AUTOMATION_SITE_ID}" && -n "${ACF_AUTOMATION_SECRET}" ]]; then
    AUTH_MODE="plugin_secret"
    TARGET_API_PULL_PATH="$(normalize_route_path "${ACF_AUTOMATION_SCHEMA_PULL_PATH}")"
    TARGET_API_PUSH_PATH="$(normalize_route_path "${ACF_AUTOMATION_SCHEMA_PUSH_PATH}")"
    TARGET_API_PUSH_ROUTE="${TARGET_API_PUSH_PATH#/wp-json}"
    API_CURL_AUTH_ARGS=(
      -H "X-ACF-Automation-Site: ${ACF_AUTOMATION_SITE_ID}"
      -H "X-ACF-Automation-Secret: ${ACF_AUTOMATION_SECRET}"
    )
  else
    AUTH_MODE="legacy"
    : "${TARGET_API_USER:?TARGET_API_USER (or WP_API_USER/WP_API_USERNAME) must be set in ${WORKSPACE_ENV_FILE} or environment}"
    : "${TARGET_API_APP_PASSWORD:?TARGET_API_APP_PASSWORD (or WP_API_APP_PASSWORD) must be set in ${WORKSPACE_ENV_FILE} or environment}"
    TARGET_API_PULL_PATH="$(normalize_route_path "${TARGET_API_PULL_PATH}")"
    TARGET_API_PUSH_PATH="$(normalize_route_path "${TARGET_API_PUSH_PATH}")"
    TARGET_API_PUSH_ROUTE="$(normalize_route_path "${TARGET_API_PUSH_ROUTE}")"
    API_CURL_AUTH_ARGS=(--user "${TARGET_API_USER}:${TARGET_API_APP_PASSWORD}")
  fi

  PULL_URL="${TARGET_BASE_URL}${TARGET_API_PULL_PATH}"
  PUSH_URL="${TARGET_BASE_URL}${TARGET_API_PUSH_PATH}"

  export AUTH_MODE
  export TARGET_BASE_URL
  export TARGET_CURL_TIMEOUT
  export TARGET_API_HMAC_SECRET
  export TARGET_API_PULL_PATH
  export TARGET_API_PUSH_PATH
  export TARGET_API_PUSH_ROUTE
  export ACF_AUTOMATION_SITE_ID
  export ACF_AUTOMATION_SECRET
  export ACF_AUTOMATION_SCHEMA_PULL_PATH
  export ACF_AUTOMATION_SCHEMA_PUSH_PATH
}

render_api_error() {
  local status="$1"
  local body_file="$2"

  if jq -e '.' "${body_file}" >/dev/null 2>&1; then
    local code
    local message
    code="$(jq -r '.code // empty' "${body_file}")"
    message="$(jq -r '.message // empty' "${body_file}")"

    if [[ -n "${code}" || -n "${message}" ]]; then
      echo "HTTP ${status} from API." >&2
      [[ -n "${code}" ]] && echo "  code: ${code}" >&2
      [[ -n "${message}" ]] && echo "  message: ${message}" >&2
    else
      echo "HTTP ${status} from API with JSON error response." >&2
    fi

    if jq -e '.data.errors | type == "array"' "${body_file}" >/dev/null 2>&1; then
      echo "  details:" >&2
      jq -r '.data.errors[] | "    - " + .' "${body_file}" >&2
    fi

    return
  fi

  echo "HTTP ${status} from API (non-JSON response)." >&2
  sed 's/^/  /' "${body_file}" >&2
}

api_post_json() {
  local url="$1"
  local payload_file="$2"
  local response_file="$3"
  shift 3

  local http_code
  http_code="$(curl -sS --show-error \
    --connect-timeout "${TARGET_CURL_TIMEOUT}" \
    --max-time "${TARGET_CURL_TIMEOUT}" \
    "${API_CURL_AUTH_ARGS[@]}" \
    -H "Content-Type: application/json" \
    "$@" \
    -X POST \
    --data-binary "@${payload_file}" \
    -o "${response_file}" \
    -w "%{http_code}" \
    "${url}")"

  [[ "${http_code}" =~ ^[0-9]{3}$ ]] || fail "Unexpected HTTP status from API call: ${http_code}"

  if (( http_code >= 400 )); then
    render_api_error "${http_code}" "${response_file}"
    return 1
  fi

  require_json_object "${response_file}" "API response"
}

build_push_signature_headers() {
  local payload_file="$1"
  PUSH_SIGNATURE_HEADERS=()
  [[ -n "${TARGET_API_HMAC_SECRET}" ]] || return 0

  local timestamp
  local nonce
  local body_hash
  local canonical
  local signature

  timestamp="$(date +%s)"
  nonce="$(openssl rand -hex 16)"
  body_hash="$(openssl dgst -sha256 "${payload_file}" | awk '{print $NF}')"
  canonical="$(printf 'POST\n%s\n%s\n%s\n%s' "${TARGET_API_PUSH_ROUTE}" "${timestamp}" "${nonce}" "${body_hash}")"
  signature="$(printf '%s' "${canonical}" | openssl dgst -sha256 -hmac "${TARGET_API_HMAC_SECRET}" | awk '{print $NF}')"

  PUSH_SIGNATURE_HEADERS=(
    -H "X-ACF-Schema-Timestamp: ${timestamp}"
    -H "X-ACF-Schema-Nonce: ${nonce}"
    -H "X-ACF-Schema-Signature: ${signature}"
  )
}
