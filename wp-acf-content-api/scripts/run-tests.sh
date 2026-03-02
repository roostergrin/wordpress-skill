#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# run-tests.sh  –  Integration test runner for wp-acf-content-api
#
# Safe by default: tests 1-6 + 9 run without touching live data.
# Tests 7-8 (real write + rollback) require --live flag.
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

PAGE_ID=""
LIVE=0

usage() {
  cat <<'EOF'
Usage: run-tests.sh --id <page-id> [--live]

Options:
  --id            WordPress page/post ID to test against (required)
  --live          Enable tests 7-8 (real write + rollback). Without this
                  flag only read-only and dry-run tests execute.
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)          PAGE_ID="$2";     shift 2 ;;
    --live)        LIVE=1;           shift   ;;
    -h|--help)     usage; exit 0            ;;
    *)             echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "${PAGE_ID}" ]]     || { echo "ERROR: --id is required" >&2; exit 1; }

# Load workspace .env if password is not already in environment
if [[ -z "${WP_API_APP_PASSWORD:-}" ]]; then
  if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${WORKSPACE_ENV_FILE}"
  fi
fi
[[ -n "${WP_API_APP_PASSWORD:-}" ]] || { echo "ERROR: WP_API_APP_PASSWORD must be set in ${WORKSPACE_ENV_FILE} or environment" >&2; exit 1; }

TEST_RUNTIME_DIR="${CONTENT_API_RUNTIME_DIR}/tests"
mkdir -p "${TEST_RUNTIME_DIR}"

# ─── Counters ───
PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL: $1" >&2; FAIL=$(( FAIL + 1 )); }
skip() { echo "  SKIP: $1"; SKIP=$(( SKIP + 1 )); }

# ─── Test 1: Config sanity (--help) ─────────────────────────
echo ""
echo "=== Test 1: Config sanity (--help output) ==="

for script in build-allowlist.sh pull-content.sh push-content.sh; do
  if bash "${SKILL_ROOT}/scripts/${script}" --help >/dev/null 2>&1; then
    pass "${script} --help"
  else
    fail "${script} --help"
  fi
done

# ─── Test 2: Allowlist generation ────────────────────────────
echo ""
echo "=== Test 2: Allowlist generation ==="

if bash "${SKILL_ROOT}/scripts/build-allowlist.sh"; then
  ALLOWLIST="${CONTENT_API_FIELD_KEYS_FILE}"
  if [[ -f "${ALLOWLIST}" ]]; then
    KEY_COUNT="$(wc -l < "${ALLOWLIST}" | tr -d ' ')"
    if [[ "${KEY_COUNT}" -gt 0 ]]; then
      pass "allowlist has ${KEY_COUNT} keys"
    else
      fail "allowlist file exists but is empty"
    fi
  else
    fail "allowlist file not created"
  fi
else
  fail "build-allowlist.sh exited with error"
fi

# ─── Test 3: Pull ACF content ───────────────────────────────
echo ""
echo "=== Test 3: Read current ACF content ==="

ACF_FILE="${CONTENT_API_RUNTIME_DIR}/pull-pages-${PAGE_ID}-acf.json"

if bash "${SKILL_ROOT}/scripts/pull-content.sh" --resource-type pages --id "${PAGE_ID}"; then
  if [[ -f "${ACF_FILE}" ]]; then
    ACF_KEY_COUNT="$(jq 'keys | length' "${ACF_FILE}")"
    if [[ "${ACF_KEY_COUNT}" -gt 0 ]]; then
      pass "pulled ACF JSON with ${ACF_KEY_COUNT} keys"
    else
      fail "ACF JSON has zero keys"
    fi
  else
    fail "ACF output file not created"
  fi
else
  fail "pull-content.sh exited with error"
fi

# ─── Test 4: Blocked endpoint type ──────────────────────────
echo ""
echo "=== Test 4: Blocked endpoint type (safety) ==="

if bash "${SKILL_ROOT}/scripts/pull-content.sh" --resource-type users --id 1 2>/dev/null; then
  fail "users endpoint should be blocked but succeeded"
else
  pass "users endpoint correctly rejected"
fi

# ─── Test 5: Dry-run valid update ───────────────────────────
echo ""
echo "=== Test 5: Dry-run valid update ==="

# Use field names (what the REST API expects), not field keys
NAMES_LIST="${CONTENT_API_FIELD_NAMES_FILE}"
FIELD_NAME="$(head -n 1 "${NAMES_LIST}")"

VALID_PAYLOAD="$(mktemp "${TEST_RUNTIME_DIR}/valid-payload.XXXXXX.json")"
jq -n --arg k "${FIELD_NAME}" --arg v "API dry run test $(date +%s)" \
  '{acf:{($k):$v}}' > "${VALID_PAYLOAD}"

if bash "${SKILL_ROOT}/scripts/push-content.sh" \
     --resource-type pages --id "${PAGE_ID}" \
     --payload "${VALID_PAYLOAD}" --dry-run; then
  pass "dry-run accepted valid payload (field name: ${FIELD_NAME})"
else
  fail "dry-run rejected a valid payload"
fi

# ─── Test 6a: Reject non-allowlisted field key ──────────────
echo ""
echo "=== Test 6a: Reject non-allowlisted field (safety) ==="

BAD_KEY_PAYLOAD="$(mktemp "${TEST_RUNTIME_DIR}/reject-non-allowlisted.XXXXXX.json")"
cat > "${BAD_KEY_PAYLOAD}" <<'JSON'
{"acf":{"field_not_allowlisted":"bad"}}
JSON

if bash "${SKILL_ROOT}/scripts/push-content.sh" \
     --resource-type pages --id "${PAGE_ID}" \
     --payload "${BAD_KEY_PAYLOAD}" --dry-run 2>/dev/null; then
  fail "non-allowlisted key should be rejected but passed"
else
  pass "non-allowlisted key correctly rejected"
fi

# ─── Test 6b: Reject invalid payload shape ──────────────────
echo ""
echo "=== Test 6b: Reject invalid payload shape (safety) ==="

BAD_SHAPE_PAYLOAD="$(mktemp "${TEST_RUNTIME_DIR}/reject-invalid-shape.XXXXXX.json")"
cat > "${BAD_SHAPE_PAYLOAD}" <<'JSON'
{"acf":{"field_x":"x"},"title":"not allowed"}
JSON

if bash "${SKILL_ROOT}/scripts/push-content.sh" \
     --resource-type pages --id "${PAGE_ID}" \
     --payload "${BAD_SHAPE_PAYLOAD}" --dry-run 2>/dev/null; then
  fail "extra top-level keys should be rejected but passed"
else
  pass "extra top-level keys correctly rejected"
fi

# ─── Test 7: Real update + verify (requires --live) ─────────
echo ""
echo "=== Test 7: Real update + verify ==="

if [[ "${LIVE}" -eq 0 ]]; then
  skip "real write (use --live to enable)"
else
  # Use a simple text field name for write test.
  # Pick a known top-level field from the pulled ACF data.
  WRITE_FIELD="${FIELD_NAME}"

  # Snapshot original value for rollback
  ORIGINAL_VALUE="$(jq -r --arg k "${WRITE_FIELD}" '.[$k] // ""' "${ACF_FILE}")"

  TEST_VALUE="run-tests $(date +%s)"
  LIVE_PAYLOAD="$(mktemp "${TEST_RUNTIME_DIR}/live-update.XXXXXX.json")"
  jq -n --arg k "${WRITE_FIELD}" --arg v "${TEST_VALUE}" \
    '{acf:{($k):$v}}' > "${LIVE_PAYLOAD}"

  if bash "${SKILL_ROOT}/scripts/push-content.sh" \
       --resource-type pages --id "${PAGE_ID}" \
       --payload "${LIVE_PAYLOAD}"; then

    # Re-pull and verify
    bash "${SKILL_ROOT}/scripts/pull-content.sh" --resource-type pages --id "${PAGE_ID}"
    PULLED_VALUE="$(jq -r --arg k "${WRITE_FIELD}" '.[$k] // ""' "${ACF_FILE}")"

    if [[ "${PULLED_VALUE}" == "${TEST_VALUE}" ]]; then
      pass "pushed value matches pulled value"
    else
      fail "value mismatch: expected '${TEST_VALUE}', got '${PULLED_VALUE}'"
    fi
  else
    fail "push-content.sh exited with error"
  fi
fi

# ─── Test 8: Rollback (requires --live) ─────────────────────
echo ""
echo "=== Test 8: Rollback ==="

if [[ "${LIVE}" -eq 0 ]]; then
  skip "rollback (use --live to enable)"
else
  ROLLBACK_PAYLOAD="$(mktemp "${TEST_RUNTIME_DIR}/rollback.XXXXXX.json")"
  jq -n --arg k "${WRITE_FIELD}" --arg v "${ORIGINAL_VALUE}" \
    '{acf:{($k):$v}}' > "${ROLLBACK_PAYLOAD}"

  if bash "${SKILL_ROOT}/scripts/push-content.sh" \
       --resource-type pages --id "${PAGE_ID}" \
       --payload "${ROLLBACK_PAYLOAD}"; then

    bash "${SKILL_ROOT}/scripts/pull-content.sh" --resource-type pages --id "${PAGE_ID}"
    RESTORED_VALUE="$(jq -r --arg k "${WRITE_FIELD}" '.[$k] // ""' "${ACF_FILE}")"

    if [[ "${RESTORED_VALUE}" == "${ORIGINAL_VALUE}" ]]; then
      pass "rollback restored original value"
    else
      fail "rollback mismatch: expected '${ORIGINAL_VALUE}', got '${RESTORED_VALUE}'"
    fi
  else
    fail "rollback push failed"
  fi
fi

# ─── Test 9: Auth failure (safety) ──────────────────────────
echo ""
echo "=== Test 9: Auth failure (safety) ==="

# Build a valid payload so we get past local validation and hit the server
AUTH_TEST_PAYLOAD="$(mktemp "${TEST_RUNTIME_DIR}/auth-test.XXXXXX.json")"
jq -n --arg k "${FIELD_NAME}" --arg v "auth-test" '{acf:{($k):$v}}' > "${AUTH_TEST_PAYLOAD}"

# Push with wrong password — should fail at the curl/server level
if WP_API_APP_PASSWORD="wrong-password" bash "${SKILL_ROOT}/scripts/push-content.sh" \
     --resource-type pages --id "${PAGE_ID}" \
     --payload "${AUTH_TEST_PAYLOAD}" 2>/dev/null; then
  fail "bad password should fail but push succeeded"
else
  pass "bad password correctly rejected on push"
fi

# ─── Summary ────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: ${PASS}   FAIL: ${FAIL}   SKIP: ${SKIP}"
echo "════════════════════════════════════════"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
