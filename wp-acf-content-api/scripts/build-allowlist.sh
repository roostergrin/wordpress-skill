#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-allowlist.sh [--out <path>]

Generate allowlisted ACF field names and field keys from ./wp-content/acf-json in the current repo.

Outputs:
  ./runtime/content-api/allowed-field-names.txt  — human-readable names (used by push-content.sh)
  ./runtime/content-api/allowed-field-keys.txt   — internal field_* keys (reference/audit)
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

OUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 ]] || fail "Missing value for --out"
      OUT_PATH="$2"
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

require_command jq

if [[ -z "${OUT_PATH}" ]]; then
  OUT_PATH="${CONTENT_API_FIELD_KEYS_FILE}"
  NAMES_OUT="${CONTENT_API_FIELD_NAMES_FILE}"
else
  NAMES_OUT="$(dirname -- "${OUT_PATH}")/allowed-field-names.txt"
fi

acf_dir="${ACF_JSON_DIR}"
[[ -d "${acf_dir}" ]] || fail "Expected ACF schema at ${acf_dir}. Run this from the target repo root."

tmp_keys="$(mktemp)"
tmp_names="$(mktemp)"
files_found=0

while IFS= read -r -d '' file; do
  files_found=1
  # Extract field_* keys (internal identifiers)
  jq -r '.. | objects | .key? // empty | select(type=="string" and startswith("field_"))' "${file}" >> "${tmp_keys}"
  # Extract field names (what the REST API uses)
  jq -r '.. | objects | select(.key? // "" | startswith("field_")) | .name // empty | select(type=="string" and length > 0)' "${file}" >> "${tmp_names}"
done < <(find "${acf_dir}" -type f -name '*.json' -print0)

if [[ "${files_found}" -eq 0 ]]; then
  rm -f "${tmp_keys}" "${tmp_names}"
  fail "No JSON files found under ${acf_dir}"
fi

sort -u "${tmp_keys}" > "${tmp_keys}.sorted"
mv "${tmp_keys}.sorted" "${tmp_keys}"
sort -u "${tmp_names}" > "${tmp_names}.sorted"
mv "${tmp_names}.sorted" "${tmp_names}"

if [[ ! -s "${tmp_keys}" ]]; then
  rm -f "${tmp_keys}" "${tmp_names}"
  fail "No field keys detected in schema JSON."
fi
if [[ ! -s "${tmp_names}" ]]; then
  rm -f "${tmp_keys}" "${tmp_names}"
  fail "No field names detected in schema JSON."
fi

mkdir -p "$(dirname -- "${OUT_PATH}")"
mv "${tmp_keys}" "${OUT_PATH}"

mkdir -p "$(dirname -- "${NAMES_OUT}")"
mv "${tmp_names}" "${NAMES_OUT}"

echo "Field keys allowlist: ${OUT_PATH}"
echo "  Key count: $(wc -l < "${OUT_PATH}" | tr -d ' ')"
echo "Field names allowlist: ${NAMES_OUT}"
echo "  Name count: $(wc -l < "${NAMES_OUT}" | tr -d ' ')"
