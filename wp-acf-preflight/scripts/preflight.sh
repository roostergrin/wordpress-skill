#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: preflight.sh [--id <resource-id>] [--resource-type <type>] [--write-field <field-name>] [--live] [--allow-dirty]

Verify that the current repo is ready for WordPress ACF automation.

Safe mode checks:
  - local command dependencies
  - repo-local auth loading
  - schema pull
  - schema push dry-run
  - field allowlist generation
  - content pull
  - content push dry-run

Live mode additionally checks:
  - schema push apply (with the just-pulled local schema)
  - content write + verification + rollback

Options:
  --id            Existing WordPress resource ID to verify (or set PREFLIGHT_RESOURCE_ID in .env)
  --resource-type Resource type to verify (default: pages)
  --write-field   Override the field used for live content write/rollback
  --live          Enable live schema apply and live content write/rollback
  --allow-dirty   Allow running even if ./wp-content/acf-json has uncommitted changes
  -h, --help      Show help
EOF
}

fail_fast() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="$(pwd -P)"
WORKSPACE_ENV_FILE="${WORKSPACE_ROOT}/.env"
PREFLIGHT_RUNTIME_DIR="${WORKSPACE_ROOT}/runtime/preflight"

SCHEMA_PULL_SCRIPT="${SKILL_ROOT}/../acf-schema-deploy/scripts/pull.sh"
SCHEMA_PUSH_SCRIPT="${SKILL_ROOT}/../acf-schema-deploy/scripts/push.sh"
ALLOWLIST_SCRIPT="${SKILL_ROOT}/../wp-acf-content-api/scripts/build-allowlist.sh"
CONTENT_PULL_SCRIPT="${SKILL_ROOT}/../wp-acf-content-api/scripts/pull-content.sh"
CONTENT_PUSH_SCRIPT="${SKILL_ROOT}/../wp-acf-content-api/scripts/push-content.sh"

RESOURCE_ID=""
RESOURCE_TYPE="pages"
WRITE_FIELD=""
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

ensure_clean_schema_dir() {
  [[ "${ALLOW_DIRTY}" -eq 1 ]] && return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "${WORKSPACE_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local status_output
  status_output="$(git -C "${WORKSPACE_ROOT}" status --porcelain -- wp-content/acf-json 2>/dev/null || true)"
  if [[ -n "${status_output}" ]]; then
    fail_fast "Uncommitted changes detected under ./wp-content/acf-json. Commit/stash them first or rerun with --allow-dirty."
  fi
}

select_write_field() {
  [[ -n "${WRITE_FIELD}" ]] && return 0

  local acf_file="${WORKSPACE_ROOT}/runtime/content-api/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-acf.json"
  [[ -f "${acf_file}" ]] || fail_fast "Expected pulled ACF snapshot at ${acf_file}"

  local candidates candidate value_type
  candidates="$(jq -r '
    .fields[]? 
    | select(.name? and (.type == "text" or .type == "textarea" or .type == "wysiwyg" or .type == "email" or .type == "url"))
    | .name
  ' "${WORKSPACE_ROOT}"/wp-content/acf-json/group_*.json 2>/dev/null | sort -u)"

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    value_type="$(jq -r --arg k "${candidate}" 'if has($k) then .[$k] | type else "missing" end' "${acf_file}")"
    if [[ "${value_type}" == "string" || "${value_type}" == "null" ]]; then
      WRITE_FIELD="${candidate}"
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
  ' "${WORKSPACE_ROOT}"/wp-content/acf-json/group_*.json 2>/dev/null | sort -u)"

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    value_type="$(field_path_type "${candidate}" "${acf_file}")"
    if [[ "${value_type}" == "string" || "${value_type}" == "null" ]]; then
      WRITE_FIELD="${candidate}"
      return 0
    fi
  done <<< "${candidates}"

  fail_fast "Unable to auto-select a safe text field for live verification. Re-run with --write-field <field-name>."
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
echo "Mode: $([[ "${LIVE}" -eq 1 ]] && printf 'live' || printf 'safe')"

require_command bash
require_command curl
require_command jq
pass "local command dependencies available"

[[ -f "${WORKSPACE_ENV_FILE}" ]] || fail_fast "Missing ${WORKSPACE_ENV_FILE}. Paste the plugin-generated .env block first."
pass "repo-local .env present"

resolve_resource_id
ensure_clean_schema_dir
pass "repo-local schema directory is safe to pull into"

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

select_write_field
pass "selected verification write field '${WRITE_FIELD}'"

live_payload_file="${PREFLIGHT_RUNTIME_DIR}/content-live-payload.json"
rollback_payload_file="${PREFLIGHT_RUNTIME_DIR}/content-rollback-payload.json"
acf_snapshot_file="${WORKSPACE_ROOT}/runtime/content-api/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-acf.json"
test_value="wp-acf-preflight $(date +%s)"

write_live_payload "${WRITE_FIELD}" "${acf_snapshot_file}" "${test_value}" "${live_payload_file}"
write_rollback_payload "${WRITE_FIELD}" "${acf_snapshot_file}" "${rollback_payload_file}"
pass "prepared verification payloads"

if ! run_logged_check "content push dry-run" "${content_push_dry_run_log}" \
  bash "${CONTENT_PUSH_SCRIPT}" --resource-type "${RESOURCE_TYPE}" --id "${RESOURCE_ID}" --payload "${live_payload_file}" --dry-run; then
  print_summary
  exit 1
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
        if verify_rollback_value "${WRITE_FIELD}" "${WORKSPACE_ROOT}/runtime/content-api/pull-${RESOURCE_TYPE}-${RESOURCE_ID}-acf.json" "${rollback_payload_file}"; then
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
