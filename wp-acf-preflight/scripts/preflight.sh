#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: preflight.sh [--id <resource-id>] [--resource-type <type>] [--write-field <field-name>] [--globaldata-id <resource-id>] [--globaldata-write-field <field-name>] [--live] [--allow-dirty]

Verify that the target workspace is ready for WordPress ACF automation.

Safe mode checks:
  - local command dependencies
  - resolved env loading
  - schema pull
  - schema push dry-run
  - field allowlist generation
  - content pull
  - content push dry-run
  - optional globaldata pull + dry-run push

Live mode additionally checks:
  - schema push apply (with the just-pulled local schema)
  - content write + verification + rollback

Options:
  --id            Existing WordPress resource ID to verify (or set PREFLIGHT_RESOURCE_ID in the resolved env file)
  --resource-type Resource type to verify (default: pages)
  --write-field   Override the field used for live content write/rollback
  --globaldata-id Existing globaldata resource ID to verify (or set PREFLIGHT_GLOBALDATA_ID in the resolved env file)
  --globaldata-write-field Override the field used for globaldata dry-run verification
  --live          Enable live schema apply and live content write/rollback
  --allow-dirty   Allow running even if the resolved ACF_JSON_DIR has uncommitted changes
  -h, --help      Show help
EOF
}

fail_fast() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${SKILL_ROOT}/.." && pwd -P)"
CURRENT_DIR="$(pwd -P)"

resolve_path() {
  local base_dir="$1"
  local configured_path="$2"

  if [[ "${configured_path}" == /* ]]; then
    printf '%s' "${configured_path}"
  else
    printf '%s/%s' "${base_dir}" "${configured_path}"
  fi
}

WORKSPACE_ROOT="$(resolve_path "${CURRENT_DIR}" "${ACF_WORKSPACE_ROOT:-${CURRENT_DIR}}")"
if [[ -d "${WORKSPACE_ROOT}" ]]; then
  WORKSPACE_ROOT="$(cd -- "${WORKSPACE_ROOT}" && pwd -P)"
fi

WORKSPACE_ENV_FILE="$(resolve_path "${WORKSPACE_ROOT}" "${ACF_ENV_FILE:-.env}")"
WORKSPACE_RUNTIME_DIR="$(resolve_path "${WORKSPACE_ROOT}" "${ACF_RUNTIME_DIR:-tmp/wp-acf}")"
PREFLIGHT_RUNTIME_DIR="$(resolve_path "${WORKSPACE_ROOT}" "${ACF_PREFLIGHT_RUNTIME_DIR:-${WORKSPACE_RUNTIME_DIR}/preflight}")"
CONTENT_API_RUNTIME_DIR="$(resolve_path "${WORKSPACE_ROOT}" "${ACF_CONTENT_API_RUNTIME_DIR:-${WORKSPACE_RUNTIME_DIR}/content-api}")"
ACF_JSON_DIR="$(resolve_path "${WORKSPACE_ROOT}" "${ACF_JSON_DIR:-wp-content/acf-json}")"

export ACF_WORKSPACE_ROOT="${WORKSPACE_ROOT}"
export ACF_ENV_FILE="${WORKSPACE_ENV_FILE}"
export ACF_RUNTIME_DIR="${WORKSPACE_RUNTIME_DIR}"
export ACF_PREFLIGHT_RUNTIME_DIR="${PREFLIGHT_RUNTIME_DIR}"
export ACF_CONTENT_API_RUNTIME_DIR="${CONTENT_API_RUNTIME_DIR}"
export ACF_JSON_DIR="${ACF_JSON_DIR}"

SCHEMA_PULL_SCRIPT="${REPO_ROOT}/acf-schema-deploy/scripts/pull.sh"
SCHEMA_PUSH_SCRIPT="${REPO_ROOT}/acf-schema-deploy/scripts/push.sh"
ALLOWLIST_SCRIPT="${REPO_ROOT}/wp-acf-content-api/scripts/build-allowlist.sh"
CONTENT_PULL_SCRIPT="${REPO_ROOT}/wp-acf-content-api/scripts/pull-content.sh"
CONTENT_PUSH_SCRIPT="${REPO_ROOT}/wp-acf-content-api/scripts/push-content.sh"

RESOURCE_ID=""
RESOURCE_TYPE="pages"
WRITE_FIELD=""
GLOBALDATA_RESOURCE_ID=""
GLOBALDATA_RESOURCE_TYPE="globaldata"
GLOBALDATA_WRITE_FIELD=""
LIVE=0
ALLOW_DIRTY=0

PASS=0
FAIL=0
SKIP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      [[ $# -ge 2 ]] || fail_fast "Missing value for --id"
      RESOURCE_ID="$2"
      shift 2
      ;;
    --resource-type)
      [[ $# -ge 2 ]] || fail_fast "Missing value for --resource-type"
      RESOURCE_TYPE="$2"
      shift 2
      ;;
    --write-field)
      [[ $# -ge 2 ]] || fail_fast "Missing value for --write-field"
      WRITE_FIELD="$2"
      shift 2
      ;;
    --globaldata-id)
      [[ $# -ge 2 ]] || fail_fast "Missing value for --globaldata-id"
      GLOBALDATA_RESOURCE_ID="$2"
      shift 2
      ;;
    --globaldata-write-field)
      [[ $# -ge 2 ]] || fail_fast "Missing value for --globaldata-write-field"
      GLOBALDATA_WRITE_FIELD="$2"
      shift 2
      ;;
    --live)
      LIVE=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail_fast "Unknown argument: $1"
      ;;
  esac
done

mkdir -p "${PREFLIGHT_RUNTIME_DIR}"

pass() {
  PASS=$((PASS + 1))
  echo "PASS: $1"
}

fail_check() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1" >&2
}

skip() {
  SKIP=$((SKIP + 1))
  echo "SKIP: $1"
}

print_summary() {
  echo ""
  echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
  echo "Logs: ${PREFLIGHT_RUNTIME_DIR}"
}

run_logged_check() {
  local label="$1"
  local logfile="$2"
  shift 2

  if "$@" >"${logfile}" 2>&1; then
    pass "${label}"
    return 0
  fi

  fail_check "${label} (see ${logfile})"
  return 1
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail_fast "Required command not found: ${cmd}"
}

resolve_resource_id() {
  if [[ -n "${RESOURCE_ID}" ]]; then
    return 0
  fi

  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
    RESOURCE_ID="${PREFLIGHT_RESOURCE_ID:-}"
  fi

  [[ -n "${RESOURCE_ID}" ]] || fail_fast "Provide --id <resource-id> or set PREFLIGHT_RESOURCE_ID in ${WORKSPACE_ENV_FILE}."
}

resolve_globaldata_target() {
  if [[ -n "${GLOBALDATA_RESOURCE_ID}" ]]; then
    return 0
  fi

  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
    GLOBALDATA_RESOURCE_ID="${PREFLIGHT_GLOBALDATA_ID:-}"
    GLOBALDATA_RESOURCE_TYPE="${PREFLIGHT_GLOBALDATA_RESOURCE_TYPE:-${GLOBALDATA_RESOURCE_TYPE}}"
    GLOBALDATA_WRITE_FIELD="${PREFLIGHT_GLOBALDATA_WRITE_FIELD:-${GLOBALDATA_WRITE_FIELD}}"
  fi
}

ensure_clean_schema_dir() {
  [[ "${ALLOW_DIRTY}" -eq 1 ]] && return 0
  command -v git >/dev/null 2>&1 || return 0
  [[ -d "${ACF_JSON_DIR}" ]] || return 0
  git -C "${ACF_JSON_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local status_output
  status_output="$(git -C "${ACF_JSON_DIR}" status --porcelain -- . 2>/dev/null || true)"
  if [[ -n "${status_output}" ]]; then
    fail_fast "Uncommitted changes detected under ${ACF_JSON_DIR}. Commit/stash them first or rerun with --allow-dirty, or change ACF_JSON_DIR."
  fi
}

select_write_field() {
  local resource_type="$1"
  local resource_id="$2"
  local requested_write_field="${3:-}"

  if [[ -n "${requested_write_field}" ]]; then
    printf '%s' "${requested_write_field}"
    return 0
  fi

  local acf_file="${CONTENT_API_RUNTIME_DIR}/pull-${resource_type}-${resource_id}-acf.json"
  [[ -f "${acf_file}" ]] || fail_fast "Expected pulled ACF snapshot at ${acf_file}"

  local candidates candidate value_type
  local schema_files=()
  while IFS= read -r schema_file; do
    [[ -n "${schema_file}" ]] && schema_files+=("${schema_file}")
  done < <(find "${ACF_JSON_DIR}" -maxdepth 1 -type f -name 'group_*.json' | sort)
  [[ "${#schema_files[@]}" -gt 0 ]] || fail_fast "No schema files found under ${ACF_JSON_DIR}. Set ACF_JSON_DIR to a trusted schema directory."

  candidates="$(jq -r '
    .fields[]? 
    | select(.name? and (.type == "text" or .type == "textarea" or .type == "wysiwyg" or .type == "email" or .type == "url"))
    | .name
  ' "${schema_files[@]}" 2>/dev/null | sort -u)"

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    value_type="$(jq -r --arg k "${candidate}" 'if has($k) then .[$k] | type else "missing" end' "${acf_file}")"
    if [[ "${value_type}" == "string" || "${value_type}" == "null" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done <<< "${candidates}"

  candidates="$(jq -r '
    .fields[]?
    | select(.type == "group" and .name?)
    | .name as $group_name
    | .sub_fields[]?
    | select(.name? and (.type == "text" or .type == "textarea" or .type == "wysiwyg" or .type == "email" or .type == "url"))
    | "\($group_name).\(.name)"
  ' "${schema_files[@]}" 2>/dev/null | sort -u)"

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    value_type="$(field_path_type "${candidate}" "${acf_file}")"
    if [[ "${value_type}" == "string" || "${value_type}" == "null" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done <<< "${candidates}"

  fail_fast "Unable to auto-select a safe text field for verification on ${resource_type}/${resource_id}. Re-run with --write-field or --globaldata-write-field."
}

field_path_type() {
  local field_path="$1"
  local acf_file="$2"
  if [[ "${field_path}" == *.* ]]; then
    local group_name="${field_path%%.*}"
    local child_name="${field_path#*.}"
    jq -r --arg g "${group_name}" --arg c "${child_name}" '
      if (.[$g] | type) == "object" and (.[$g] | has($c)) then
        .[$g][$c] | type
      else
        "missing"
      end
    ' "${acf_file}"
    return 0
  fi

  jq -r --arg k "${field_path}" 'if has($k) then .[$k] | type else "missing" end' "${acf_file}"
}

field_path_value() {
  local field_path="$1"
  local acf_file="$2"
  if [[ "${field_path}" == *.* ]]; then
    local group_name="${field_path%%.*}"
    local child_name="${field_path#*.}"
    jq -r --arg g "${group_name}" --arg c "${child_name}" '.[$g][$c] // empty' "${acf_file}"
    return 0
  fi

  jq -r --arg k "${field_path}" '.[$k] // empty' "${acf_file}"
}

write_string_payload() {
  local field_path="$1"
  local acf_file="$2"
  local value="$3"
  local out_file="$4"

  if [[ "${field_path}" == *.* ]]; then
    local group_name="${field_path%%.*}"
    local child_name="${field_path#*.}"
    jq -n --arg g "${group_name}" --arg c "${child_name}" --arg v "${value}" --slurpfile acf "${acf_file}" '
      {acf:{($g): (($acf[0][$g] // {}) + {($c): $v})}}
    ' > "${out_file}"
    return 0
  fi

  jq -n --arg k "${field_path}" --arg v "${value}" '{acf:{($k):$v}}' > "${out_file}"
}

write_null_payload() {
  local field_path="$1"
  local acf_file="$2"
  local out_file="$3"

  if [[ "${field_path}" == *.* ]]; then
    local group_name="${field_path%%.*}"
    local child_name="${field_path#*.}"
    jq -n --arg g "${group_name}" --arg c "${child_name}" --slurpfile acf "${acf_file}" '
      {acf:{($g): (($acf[0][$g] // {}) + {($c): null})}}
    ' > "${out_file}"
    return 0
  fi

  jq -n --arg k "${field_path}" '{acf:{($k):null}}' > "${out_file}"
}

write_live_payload() {
  local field_path="$1"
  local acf_file="$2"
  local value="$3"
  local out_file="$4"
  write_string_payload "${field_path}" "${acf_file}" "${value}" "${out_file}"
}

write_rollback_payload() {
  local field_path="$1"
  local acf_file="$2"
  local out_file="$3"
  local value_type
  value_type="$(field_path_type "${field_path}" "${acf_file}")"

  case "${value_type}" in
    string)
      write_string_payload "${field_path}" "${acf_file}" "$(field_path_value "${field_path}" "${acf_file}")" "${out_file}"
      ;;
    null)
      write_null_payload "${field_path}" "${acf_file}" "${out_file}"
      ;;
    *)
      fail_fast "Rollback for field '${field_path}' is only supported for string/null values. Re-run with --write-field <field-name>."
      ;;
  esac
}

verify_live_value() {
  local field_path="$1"
  local expected_value="$2"
  local acf_file="$3"
  local actual_value
  actual_value="$(field_path_value "${field_path}" "${acf_file}")"
  [[ "${actual_value}" == "${expected_value}" ]]
}

verify_rollback_value() {
  local field_path="$1"
  local acf_file="$2"
  local rollback_file="$3"
  local current_type rollback_value current_value
  current_type="$(field_path_type "${field_path}" "${acf_file}")"

  if [[ "${field_path}" == *.* ]]; then
    local group_name="${field_path%%.*}"
    local child_name="${field_path#*.}"
    rollback_value="$(jq -r --arg g "${group_name}" --arg c "${child_name}" 'if .acf[$g][$c] == null then "__NULL__" else .acf[$g][$c] end' "${rollback_file}")"
  else
    rollback_value="$(jq -r --arg k "${field_path}" 'if .acf[$k] == null then "__NULL__" else .acf[$k] end' "${rollback_file}")"
  fi

  if [[ "${rollback_value}" == "__NULL__" ]]; then
    [[ "${current_type}" == "null" ]]
    return 0
  fi

  current_value="$(field_path_value "${field_path}" "${acf_file}")"
  [[ "${current_value}" == "${rollback_value}" ]]
}

echo "=== WP ACF Preflight ==="
echo "Workspace: ${WORKSPACE_ROOT}"
echo "Schema dir: ${ACF_JSON_DIR}"
echo "Runtime dir: ${PREFLIGHT_RUNTIME_DIR}"
echo "Mode: $([[ "${LIVE}" -eq 1 ]] && printf 'live' || printf 'safe')"

require_command bash
require_command curl
require_command jq
pass "local command dependencies available"

[[ -f "${WORKSPACE_ENV_FILE}" ]] || fail_fast "Missing ${WORKSPACE_ENV_FILE}. Paste the plugin-generated .env block first."
pass "resolved env file present"

[[ -f "${SCHEMA_PULL_SCRIPT}" ]] || fail_fast "Schema pull script not found: ${SCHEMA_PULL_SCRIPT}"
[[ -f "${SCHEMA_PUSH_SCRIPT}" ]] || fail_fast "Schema push script not found: ${SCHEMA_PUSH_SCRIPT}"
[[ -f "${ALLOWLIST_SCRIPT}" ]] || fail_fast "Allowlist script not found: ${ALLOWLIST_SCRIPT}"
[[ -f "${CONTENT_PULL_SCRIPT}" ]] || fail_fast "Content pull script not found: ${CONTENT_PULL_SCRIPT}"
[[ -f "${CONTENT_PUSH_SCRIPT}" ]] || fail_fast "Content push script not found: ${CONTENT_PUSH_SCRIPT}"

resolve_resource_id
resolve_globaldata_target
ensure_clean_schema_dir
pass "trusted schema directory is safe to pull into"

echo "Primary resource: ${RESOURCE_TYPE}/${RESOURCE_ID}"
if [[ -n "${GLOBALDATA_RESOURCE_ID}" ]]; then
  echo "Globaldata resource: ${GLOBALDATA_RESOURCE_TYPE}/${GLOBALDATA_RESOURCE_ID}"
fi

schema_pull_log="${PREFLIGHT_RUNTIME_DIR}/schema-pull.log"
schema_push_dry_run_log="${PREFLIGHT_RUNTIME_DIR}/schema-push-dry-run.log"
schema_push_apply_log="${PREFLIGHT_RUNTIME_DIR}/schema-push-apply.log"
allowlist_log="${PREFLIGHT_RUNTIME_DIR}/content-allowlist.log"
content_pull_log="${PREFLIGHT_RUNTIME_DIR}/content-pull.log"
content_push_dry_run_log="${PREFLIGHT_RUNTIME_DIR}/content-push-dry-run.log"
content_push_live_log="${PREFLIGHT_RUNTIME_DIR}/content-push-live.log"
content_pull_verify_log="${PREFLIGHT_RUNTIME_DIR}/content-pull-verify.log"
content_push_rollback_log="${PREFLIGHT_RUNTIME_DIR}/content-push-rollback.log"
content_pull_restore_log="${PREFLIGHT_RUNTIME_DIR}/content-pull-restore.log"
globaldata_pull_log="${PREFLIGHT_RUNTIME_DIR}/globaldata-pull.log"
globaldata_push_dry_run_log="${PREFLIGHT_RUNTIME_DIR}/globaldata-push-dry-run.log"
globaldata_live_payload_file="${PREFLIGHT_RUNTIME_DIR}/globaldata-live-payload.json"
globaldata_rollback_payload_file="${PREFLIGHT_RUNTIME_DIR}/globaldata-rollback-payload.json"

if ! run_logged_check "schema pull" "${schema_pull_log}" \
  bash "${SCHEMA_PULL_SCRIPT}"; then
  print_summary
  exit 1
fi

if ! run_logged_check "schema push dry-run" "${schema_push_dry_run_log}" \
  bash "${SCHEMA_PUSH_SCRIPT}" --dry-run; then
  print_summary
  exit 1
fi

if [[ "${LIVE}" -eq 1 ]]; then
  if ! run_logged_check "schema push apply" "${schema_push_apply_log}" \
    bash "${SCHEMA_PUSH_SCRIPT}"; then
    print_summary
    exit 1
  fi
else
  skip "schema push apply (re-run with --live)"
fi

if ! run_logged_check "content allowlist generation" "${allowlist_log}" \
  bash "${ALLOWLIST_SCRIPT}"; then
  print_summary
  exit 1
fi

if ! run_logged_check "content pull" "${content_pull_log}" \
  bash "${CONTENT_PULL_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}"; then
  print_summary
  exit 1
fi

WRITE_FIELD="$(select_write_field "${RESOURCE_TYPE}" "${RESOURCE_ID}" "${WRITE_FIELD}")"
pass "selected verification write field '${WRITE_FIELD}'"

live_payload_file="${PREFLIGHT_RUNTIME_DIR}/content-live-payload.json"
rollback_payload_file="${PREFLIGHT_RUNTIME_DIR}/content-rollback-payload.json"
acf_snapshot_file="${CONTENT_API_RUNTIME_DIR}/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-acf.json"
test_value="wp-acf-preflight $(date +%s)"

write_live_payload "${WRITE_FIELD}" "${acf_snapshot_file}" "${test_value}" "${live_payload_file}"
write_rollback_payload "${WRITE_FIELD}" "${acf_snapshot_file}" "${rollback_payload_file}"
pass "prepared verification payloads"

if ! run_logged_check "content push dry-run" "${content_push_dry_run_log}" \
  bash "${CONTENT_PUSH_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}" --payload "${live_payload_file}" --dry-run; then
  print_summary
  exit 1
fi

if [[ -n "${GLOBALDATA_RESOURCE_ID}" ]]; then
  if [[ "${GLOBALDATA_RESOURCE_TYPE}" == "${RESOURCE_TYPE}" && "${GLOBALDATA_RESOURCE_ID}" == "${RESOURCE_ID}" ]]; then
    skip "globaldata verification (already covered by primary resource)"
  else
    if ! run_logged_check "globaldata content pull" "${globaldata_pull_log}" \
      bash "${CONTENT_PULL_SCRIPT}" --resource-type "${GLOBALDATA_RESOURCE_TYPE}" --id "${GLOBALDATA_RESOURCE_ID}"; then
      print_summary
      exit 1
    fi

    GLOBALDATA_WRITE_FIELD="$(select_write_field "${GLOBALDATA_RESOURCE_TYPE}" "${GLOBALDATA_RESOURCE_ID}" "${GLOBALDATA_WRITE_FIELD}")"
    pass "selected globaldata verification write field '${GLOBALDATA_WRITE_FIELD}'"

    globaldata_acf_snapshot_file="${CONTENT_API_RUNTIME_DIR}/pull-${GLOBALDATA_RESOURCE_TYPE}-${GLOBALDATA_RESOURCE_ID}-acf.json"
    globaldata_test_value="wp-acf-preflight-globaldata $(date +%s)"
    write_live_payload "${GLOBALDATA_WRITE_FIELD}" "${globaldata_acf_snapshot_file}" "${globaldata_test_value}" "${globaldata_live_payload_file}"
    write_rollback_payload "${GLOBALDATA_WRITE_FIELD}" "${globaldata_acf_snapshot_file}" "${globaldata_rollback_payload_file}"
    pass "prepared globaldata verification payloads"

    if ! run_logged_check "globaldata content push dry-run" "${globaldata_push_dry_run_log}" \
      bash "${CONTENT_PUSH_SCRIPT}" --resource-type "${GLOBALDATA_RESOURCE_TYPE}" --id "${GLOBALDATA_RESOURCE_ID}" --payload "${globaldata_live_payload_file}" --dry-run; then
      print_summary
      exit 1
    fi
  fi
else
  skip "globaldata verification (set PREFLIGHT_GLOBALDATA_ID or pass --globaldata-id)"
fi

if [[ "${LIVE}" -eq 1 ]]; then
  if run_logged_check "content push apply" "${content_push_live_log}" \
    bash "${CONTENT_PUSH_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}" --payload "${live_payload_file}"; then
    if run_logged_check "content pull after live write" "${content_pull_verify_log}" \
      bash "${CONTENT_PULL_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}"; then
      if verify_live_value "${WRITE_FIELD}" "${test_value}" "${acf_snapshot_file}"; then
        pass "content live write verified"
      else
        fail_check "content live write verification mismatch"
      fi
    fi

    if run_logged_check "content rollback apply" "${content_push_rollback_log}" \
      bash "${CONTENT_PUSH_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}" --payload "${rollback_payload_file}"; then
      if run_logged_check "content pull after rollback" "${content_pull_restore_log}" \
        bash "${CONTENT_PULL_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}"; then
        if verify_rollback_value "${WRITE_FIELD}" "${CONTENT_API_RUNTIME_DIR}/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-acf.json" "${rollback_payload_file}"; then
          pass "content rollback verified"
        else
          fail_check "content rollback verification mismatch"
        fi
      fi
    fi
  fi
else
  skip "content push apply + rollback (re-run with --live)"
fi

print_summary

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
