#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="$(pwd -P)"
WORKSPACE_ENV_FILE="${WORKSPACE_ROOT}/.env"
WORKSPACE_RUNTIME_DIR="${WORKSPACE_ROOT}/runtime"
CONTENT_API_RUNTIME_DIR="${WORKSPACE_RUNTIME_DIR}/content-api"
ACF_JSON_DIR="${WORKSPACE_ROOT}/wp-content/acf-json"
CONTENT_API_FIELD_KEYS_FILE="${CONTENT_API_RUNTIME_DIR}/allowed-field-keys.txt"
CONTENT_API_FIELD_NAMES_FILE="${CONTENT_API_RUNTIME_DIR}/allowed-field-names.txt"
BOOTSTRAP_RUNTIME_DIR="${WORKSPACE_RUNTIME_DIR}/bootstrap"

export SKILL_ROOT
export WORKSPACE_ROOT
export WORKSPACE_ENV_FILE
export WORKSPACE_RUNTIME_DIR
export CONTENT_API_RUNTIME_DIR
export ACF_JSON_DIR
export CONTENT_API_FIELD_KEYS_FILE
export CONTENT_API_FIELD_NAMES_FILE
export BOOTSTRAP_RUNTIME_DIR

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail "Required command not found: ${cmd}"
}

normalize_base_url() {
  local value="$1"
  value="${value%/}"
  printf '%s' "${value}"
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

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_allowed_resource_type() {
  local requested="$1"
  local allowed_csv="$2"
  local normalized
  normalized=",${allowed_csv//[[:space:]]/},"
  [[ "${normalized}" == *",${requested},"* ]]
}

load_api_config() {
  local env_target_base_url="${TARGET_BASE_URL-}"
  local env_wp_api_base_url="${WP_API_BASE_URL-}"
  local env_wp_api_username="${WP_API_USERNAME-}"
  local env_wp_api_user="${WP_API_USER-}"
  local env_target_api_user="${TARGET_API_USER-}"
  local env_wp_api_app_password="${WP_API_APP_PASSWORD-}"
  local env_wp_api_timeout_seconds="${WP_API_TIMEOUT_SECONDS-}"
  local env_default_resource_type="${DEFAULT_RESOURCE_TYPE-}"
  local env_allowed_resource_types="${ALLOWED_RESOURCE_TYPES-}"
  local env_acf_field_allowlist_file="${ACF_FIELD_ALLOWLIST_FILE-}"
  local env_acf_field_name_allowlist_file="${ACF_FIELD_NAME_ALLOWLIST_FILE-}"
  local env_acf_automation_site_id="${ACF_AUTOMATION_SITE_ID-}"
  local env_acf_automation_secret="${ACF_AUTOMATION_SECRET-}"
  local env_acf_automation_content_base_path="${ACF_AUTOMATION_CONTENT_BASE_PATH-}"

  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
  fi

  WP_API_BASE_URL="${env_wp_api_base_url:-${env_target_base_url:-${WP_API_BASE_URL:-${TARGET_BASE_URL:-}}}}"
  WP_API_USERNAME="${env_wp_api_username:-${env_wp_api_user:-${env_target_api_user:-${WP_API_USERNAME:-${WP_API_USER:-${TARGET_API_USER:-}}}}}}"
  WP_API_APP_PASSWORD="${env_wp_api_app_password:-${WP_API_APP_PASSWORD:-}}"
  WP_API_TIMEOUT_SECONDS="${env_wp_api_timeout_seconds:-${WP_API_TIMEOUT_SECONDS:-30}}"
  DEFAULT_RESOURCE_TYPE="${env_default_resource_type:-${DEFAULT_RESOURCE_TYPE:-pages}}"
  ALLOWED_RESOURCE_TYPES="${env_allowed_resource_types:-${ALLOWED_RESOURCE_TYPES:-pages,posts}}"
  ACF_FIELD_ALLOWLIST_FILE="${env_acf_field_allowlist_file:-${ACF_FIELD_ALLOWLIST_FILE:-${CONTENT_API_FIELD_KEYS_FILE}}}"
  ACF_FIELD_NAME_ALLOWLIST_FILE="${env_acf_field_name_allowlist_file:-${ACF_FIELD_NAME_ALLOWLIST_FILE:-${CONTENT_API_FIELD_NAMES_FILE}}}"
  ACF_AUTOMATION_SITE_ID="${env_acf_automation_site_id:-${ACF_AUTOMATION_SITE_ID:-}}"
  ACF_AUTOMATION_SECRET="${env_acf_automation_secret:-${ACF_AUTOMATION_SECRET:-}}"
  ACF_AUTOMATION_CONTENT_BASE_PATH="${env_acf_automation_content_base_path:-${ACF_AUTOMATION_CONTENT_BASE_PATH:-/wp-json/acf-automation/v1/content}}"

  : "${WP_API_BASE_URL:?WP_API_BASE_URL (or TARGET_BASE_URL) must be set in ${WORKSPACE_ENV_FILE} or environment}"
  WP_API_BASE_URL="$(normalize_base_url "${WP_API_BASE_URL}")"
  ACF_AUTOMATION_CONTENT_BASE_PATH="$(normalize_route_path "${ACF_AUTOMATION_CONTENT_BASE_PATH}")"

  if [[ -n "${ACF_AUTOMATION_SITE_ID}" && -n "${ACF_AUTOMATION_SECRET}" ]]; then
    AUTH_MODE="plugin_secret"
  elif [[ -n "${WP_API_USERNAME}" && -n "${WP_API_APP_PASSWORD:-}" ]]; then
    AUTH_MODE="legacy"
  else
    fail "Configure either ACF_AUTOMATION_SITE_ID + ACF_AUTOMATION_SECRET or WP_API_USERNAME + WP_API_APP_PASSWORD in ${WORKSPACE_ENV_FILE}."
  fi

  export AUTH_MODE
  export WP_API_BASE_URL
  export WP_API_USERNAME
  export WP_API_APP_PASSWORD
  export WP_API_TIMEOUT_SECONDS
  export DEFAULT_RESOURCE_TYPE
  export ALLOWED_RESOURCE_TYPES
  export ACF_FIELD_ALLOWLIST_FILE
  export ACF_FIELD_NAME_ALLOWLIST_FILE
  export ACF_AUTOMATION_SITE_ID
  export ACF_AUTOMATION_SECRET
  export ACF_AUTOMATION_CONTENT_BASE_PATH
}

require_api_auth() {
  case "${AUTH_MODE:-}" in
    plugin_secret)
      CURL_AUTH_ARGS=(
        -H "X-ACF-Automation-Site: ${ACF_AUTOMATION_SITE_ID}"
        -H "X-ACF-Automation-Secret: ${ACF_AUTOMATION_SECRET}"
      )
      ;;
    legacy)
      [[ -n "${WP_API_APP_PASSWORD:-}" ]] || fail "WP_API_APP_PASSWORD is required (set in ${WORKSPACE_ENV_FILE} or environment)."
      CURL_AUTH_ARGS=(--user "${WP_API_USERNAME}:${WP_API_APP_PASSWORD}")
      ;;
    *)
      fail "Unknown auth mode: ${AUTH_MODE:-unset}"
      ;;
  esac
}

build_resource_url() {
  local resource_type="$1"
  local resource_id="$2"
  case "${AUTH_MODE:-}" in
    plugin_secret)
      printf '%s%s/%s/%s' "${WP_API_BASE_URL}" "${ACF_AUTOMATION_CONTENT_BASE_PATH}" "${resource_type}" "${resource_id}"
      ;;
    legacy)
      printf '%s/wp-json/wp/v2/%s/%s' "${WP_API_BASE_URL}" "${resource_type}" "${resource_id}"
      ;;
    *)
      fail "Unknown auth mode: ${AUTH_MODE:-unset}"
      ;;
  esac
}
