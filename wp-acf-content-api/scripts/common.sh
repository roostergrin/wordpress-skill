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

export SKILL_ROOT
export WORKSPACE_ROOT
export WORKSPACE_ENV_FILE
export WORKSPACE_RUNTIME_DIR
export CONTENT_API_RUNTIME_DIR
export ACF_JSON_DIR
export CONTENT_API_FIELD_KEYS_FILE
export CONTENT_API_FIELD_NAMES_FILE

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
  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
  fi

  WP_API_BASE_URL="${WP_API_BASE_URL:-${TARGET_BASE_URL:-}}"
  WP_API_USERNAME="${WP_API_USERNAME:-${WP_API_USER:-${TARGET_API_USER:-}}}"
  : "${WP_API_BASE_URL:?WP_API_BASE_URL (or TARGET_BASE_URL) must be set in ${WORKSPACE_ENV_FILE} or environment}"
  : "${WP_API_USERNAME:?WP_API_USERNAME (or WP_API_USER) must be set in ${WORKSPACE_ENV_FILE} or environment}"

  WP_API_TIMEOUT_SECONDS="${WP_API_TIMEOUT_SECONDS:-30}"
  DEFAULT_RESOURCE_TYPE="${DEFAULT_RESOURCE_TYPE:-pages}"
  ALLOWED_RESOURCE_TYPES="${ALLOWED_RESOURCE_TYPES:-pages,posts}"
  ACF_FIELD_ALLOWLIST_FILE="${ACF_FIELD_ALLOWLIST_FILE:-${CONTENT_API_FIELD_KEYS_FILE}}"
  ACF_FIELD_NAME_ALLOWLIST_FILE="${ACF_FIELD_NAME_ALLOWLIST_FILE:-${CONTENT_API_FIELD_NAMES_FILE}}"

  WP_API_BASE_URL="$(normalize_base_url "${WP_API_BASE_URL}")"
}

require_api_auth() {
  [[ -n "${WP_API_APP_PASSWORD:-}" ]] || fail "WP_API_APP_PASSWORD is required (set in ${WORKSPACE_ENV_FILE} or environment)."
  CURL_AUTH_ARGS=(--user "${WP_API_USERNAME}:${WP_API_APP_PASSWORD}")
}

build_resource_url() {
  local resource_type="$1"
  local resource_id="$2"
  printf '%s/wp-json/wp/v2/%s/%s' "${WP_API_BASE_URL}" "${resource_type}" "${resource_id}"
}
