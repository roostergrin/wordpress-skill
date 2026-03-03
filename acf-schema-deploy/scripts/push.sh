#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: push.sh [--dry-run] [--allow-field-key-changes] [--delete-missing] [--expected-hash <hash>]

Push local ./wp-content/acf-json/group_*.json from the current repo to the WordPress plugin API.
Validation is enforced server-side by the plugin.
If TARGET_API_HMAC_SECRET or ACF_SCHEMA_API_HMAC_SECRET is set, signed headers are added automatically.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./api-common.sh
source "${SCRIPT_DIR}/api-common.sh"

DRY_RUN=0
ALLOW_FIELD_KEY_CHANGES=0
DELETE_MISSING=0
EXPECTED_HASH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --allow-field-key-changes)
      ALLOW_FIELD_KEY_CHANGES=1
      shift
      ;;
    --delete-missing)
      DELETE_MISSING=1
      shift
      ;;
    --expected-hash)
      [[ $# -ge 2 ]] || fail "Missing value for --expected-hash"
      EXPECTED_HASH="$2"
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

local_acf_dir="${ACF_JSON_DIR}"
[[ -d "${local_acf_dir}" ]] || fail "Expected ACF schema at ${local_acf_dir}. Run this from the target repo root."

require_command curl
require_command jq

echo "Loading workspace environment..."
load_target_config
if [[ -n "${TARGET_API_HMAC_SECRET:-}" ]]; then
  require_command openssl
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

group_files=()
while IFS= read -r file; do
  [[ -n "${file}" ]] && group_files+=("${file}")
done < <(find "${local_acf_dir}" -maxdepth 1 -type f -name 'group_*.json' | sort)
[[ "${#group_files[@]}" -gt 0 ]] || fail "No group_*.json files found in ${local_acf_dir}"

for file in "${group_files[@]}"; do
  jq -e 'type == "object" and (.key | strings | startswith("group_"))' "${file}" >/dev/null \
    || fail "Invalid field group JSON file: ${file}"
done

field_groups_file="${tmp_dir}/field-groups.json"
jq -s '.' "${group_files[@]}" > "${field_groups_file}"

# Pull current server state for hash resolution and diff baseline
pull_payload="${tmp_dir}/pull-request.json"
pull_response="${tmp_dir}/pull-response.raw.json"
jq -n '{include_groups: true}' > "${pull_payload}"
api_post_json "${PULL_URL}" "${pull_payload}" "${pull_response}"

if [[ -z "${EXPECTED_HASH}" ]]; then
  EXPECTED_HASH="$(jq -r '.schema_hash // empty' "${pull_response}")"
  [[ -n "${EXPECTED_HASH}" ]] || fail "Unable to resolve expected_hash from pull endpoint."
fi

# Snapshot server-side schema as "before" state for diff
diff_before_dir="${tmp_dir}/diff-before"
diff_after_dir="${tmp_dir}/diff-after"
mkdir -p "${diff_before_dir}" "${diff_after_dir}"
while IFS= read -r gk; do
  [[ -n "${gk}" ]] || continue
  jq -S --arg gk "${gk}" '.field_groups[] | select(.key == $gk)' "${pull_response}" \
    > "${diff_before_dir}/${gk}.json"
done < <(jq -r '.field_groups[]? | .key // empty' "${pull_response}" | sort)

payload_file="${tmp_dir}/push-request.json"
response_raw="${tmp_dir}/push-response.raw.json"
runtime_dir="${SCHEMA_DEPLOY_RUNTIME_DIR}"
response_pretty="${runtime_dir}/schema-push-response.json"
mkdir -p "${runtime_dir}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  dry_run_json=true
else
  dry_run_json=false
fi

if [[ "${ALLOW_FIELD_KEY_CHANGES}" -eq 1 ]]; then
  allow_keys_json=true
else
  allow_keys_json=false
fi

if [[ "${DELETE_MISSING}" -eq 1 ]]; then
  delete_missing_json=true
else
  delete_missing_json=false
fi

jq -n \
  --arg expected_hash "${EXPECTED_HASH}" \
  --argjson dry_run "${dry_run_json}" \
  --argjson allow_field_key_changes "${allow_keys_json}" \
  --argjson delete_missing_groups "${delete_missing_json}" \
  --slurpfile groups "${field_groups_file}" \
  '{
    expected_hash: $expected_hash,
    dry_run: $dry_run,
    allow_field_key_changes: $allow_field_key_changes,
    delete_missing_groups: $delete_missing_groups,
    field_groups: $groups[0]
  }' > "${payload_file}"

build_push_signature_headers "${payload_file}"
echo "Calling push endpoint: ${PUSH_URL}"
if [[ -n "${TARGET_API_HMAC_SECRET:-}" ]]; then
  api_post_json "${PUSH_URL}" "${payload_file}" "${response_raw}" "${PUSH_SIGNATURE_HEADERS[@]}"
else
  api_post_json "${PUSH_URL}" "${payload_file}" "${response_raw}"
fi
json_pretty_write "${response_raw}" "${response_pretty}"

jq -e '.plan and .current_hash and .incoming_hash' "${response_raw}" >/dev/null \
  || fail "Push response missing required fields."

plan_create="$(jq -r '.plan.create_count // 0' "${response_raw}")"
plan_update="$(jq -r '.plan.update_count // 0' "${response_raw}")"
plan_unchanged="$(jq -r '.plan.unchanged_count // 0' "${response_raw}")"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Push dry-run completed."
  plan_removed="$(jq -r '.plan.removed_count // 0' "${response_raw}")"
  echo "Plan: create=${plan_create} update=${plan_update} unchanged=${plan_unchanged} removed=${plan_removed}"
  echo "response=${response_pretty}"
  exit 0
fi

jq -e '.applied == true and .schema_hash_after' "${response_raw}" >/dev/null \
  || fail "Push apply response missing required fields (applied/schema_hash_after)."

schema_hash_after="$(jq -r '.schema_hash_after' "${response_raw}")"
echo "Push applied."
plan_removed="$(jq -r '.plan.removed_count // 0' "${response_raw}")"
echo "Plan: create=${plan_create} update=${plan_update} unchanged=${plan_unchanged} removed=${plan_removed}"
if [[ "${DELETE_MISSING}" -eq 1 ]]; then
  delete_attempted="$(jq -r '.delete_report.attempted // 0' "${response_raw}")"
  delete_deleted="$(jq -r '.delete_report.deleted // 0' "${response_raw}")"
  delete_missing_file="$(jq -r '.delete_report.missing_file // 0' "${response_raw}")"
  echo "Delete report: attempted=${delete_attempted} deleted=${delete_deleted} missing_file=${delete_missing_file}"
fi
echo "schema_hash_after=${schema_hash_after}"
echo "response=${response_pretty}"

# Generate before/after diff
for file in "${group_files[@]}"; do
  jq -S '.' "${file}" > "${diff_after_dir}/$(basename "${file}")"
done

timestamp="$(date +%Y%m%d-%H%M%S)"
diff_file="${DIFFS_RUNTIME_DIR}/schema-push-${timestamp}.diff"
mkdir -p "${DIFFS_RUNTIME_DIR}"
if diff -ruN "${diff_before_dir}" "${diff_after_dir}" > "${diff_file}" 2>&1; then
  echo "# No schema changes detected." > "${diff_file}"
fi
echo "diff=${diff_file}"
