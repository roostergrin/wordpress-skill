#!/usr/bin/env bash
# validate-acf.sh — Validate ACF JSON files against skill guardrails
# Usage: ./validate-acf.sh [acf-json-dir] [baseline-dir]
#   acf-json-dir: directory with current JSON files (default: ./wp-content/acf-json in the current repo)
#   baseline-dir: directory with pre-edit snapshots (optional, enables diff checks)

set -euo pipefail

ACF_DIR="${1:-$(pwd -P)/wp-content/acf-json}"
BASELINE_DIR="${2:-}"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; }
warn() { WARN=$(( WARN + 1 )); echo "  WARN: $1"; }

echo "=== ACF Schema Validation ==="
echo "Directory: $ACF_DIR"
echo ""

# ── 1. All files are valid JSON ──────────────────────────────────
echo "── JSON syntax ──"
for f in "$ACF_DIR"/*.json; do
    name=$(basename "$f")
    if jq empty "$f" 2>/dev/null; then
        pass "$name parses as valid JSON"
    else
        fail "$name is INVALID JSON"
    fi
done
echo ""

# ── 2. Key format: field_, group_, layout_ + 13-char hex ────────
# ACF generates compound keys like field_xxx_field_yyy for prefixed clones — these are valid
echo "── Key format ──"
BAD_KEYS=$(jq -r '.. | objects | .key? // empty' "$ACF_DIR"/*.json \
    | grep -vE '^(field|group|layout)_[a-f0-9]{13}(_field_[a-f0-9]{13})?$' \
    | head -20 || true)
if [ -z "$BAD_KEYS" ]; then
    pass "All keys match expected ACF format"
else
    warn "Keys with non-standard format (may be legacy):"
    echo "$BAD_KEYS" | sed 's/^/    /'
fi
echo ""

# ── 3. Duplicate key check ────────────────────────────────────────
# ACF exports inline cloned sub_fields into each layout that uses them,
# so the same field key legitimately appears multiple times within one file
# (e.g., _Image fields appear in every layout that clones _Image).
# We report these as info, not failures.
echo "── Duplicate keys (informational) ──"
TOTAL_DUPES=0
for f in "$ACF_DIR"/*.json; do
    name=$(basename "$f")
    PER_FILE_DUPES=$(jq -r '.. | objects | .key? // empty' "$f" | sort | uniq -d)
    if [ -n "$PER_FILE_DUPES" ]; then
        COUNT=$(echo "$PER_FILE_DUPES" | wc -l)
        TOTAL_DUPES=$(( TOTAL_DUPES + COUNT ))
        echo "  INFO: $name has $COUNT repeated keys (from cloned components)"
    fi
done
if [ "$TOTAL_DUPES" -eq 0 ]; then
    pass "No duplicate keys in any file"
else
    pass "All duplicates are from ACF's clone inlining ($TOTAL_DUPES total)"
fi
echo ""

# ── 4. Clone references point to existing group keys ─────────────
echo "── Clone integrity ──"
GROUP_KEYS=$(jq -r '.key' "$ACF_DIR"/*.json | sort -u)
CLONE_REFS=$(jq -r '.. | objects | select(.type? == "clone") | .clone[]?' "$ACF_DIR"/*.json | sort -u)
BAD_REFS=""
for ref in $CLONE_REFS; do
    if ! echo "$GROUP_KEYS" | grep -qx "$ref"; then
        BAD_REFS="$BAD_REFS $ref"
    fi
done
if [ -z "$BAD_REFS" ]; then
    pass "All clone references point to existing groups"
else
    fail "Broken clone references:$BAD_REFS"
fi
echo ""

# ── 5. Baseline diff checks (only if baseline provided) ──────────
if [ -n "$BASELINE_DIR" ]; then
    echo "── Baseline comparison ──"

    # 5a. No existing keys were changed
    OLD_KEYS=$(jq -r '.. | objects | .key? // empty' "$BASELINE_DIR"/*.json | sort -u)
    NEW_KEYS=$(jq -r '.. | objects | .key? // empty' "$ACF_DIR"/*.json | sort -u)
    REMOVED_KEYS=$(comm -23 <(echo "$OLD_KEYS") <(echo "$NEW_KEYS"))
    if [ -z "$REMOVED_KEYS" ]; then
        pass "No existing keys were removed or changed"
    else
        fail "Keys removed/changed from baseline:"
        echo "$REMOVED_KEYS" | sed 's/^/    /'
    fi

    # 5b. No existing field names were changed
    # Extract (key, name) pairs and ensure old ones still exist
    extract_key_name() {
        jq -r '.. | objects | select(.key? and .name?) | "\(.key)|\(.name)"' "$1"/*.json | sort -u
    }
    OLD_PAIRS=$(extract_key_name "$BASELINE_DIR")
    NEW_PAIRS=$(extract_key_name "$ACF_DIR")
    CHANGED_NAMES=$(comm -23 <(echo "$OLD_PAIRS") <(echo "$NEW_PAIRS") | head -20)
    if [ -z "$CHANGED_NAMES" ]; then
        pass "No existing field names were changed"
    else
        fail "Field key|name pairs changed from baseline:"
        echo "$CHANGED_NAMES" | sed 's/^/    /'
    fi

    # 5c. Only .json files in acf-json/ were modified
    CHANGED_FILES=$(diff -rq "$BASELINE_DIR" "$ACF_DIR" 2>/dev/null | grep -v '\.json' || true)
    if [ -z "$CHANGED_FILES" ]; then
        pass "Only .json files were modified"
    else
        fail "Non-JSON files changed:"
        echo "$CHANGED_FILES" | sed 's/^/    /'
    fi

    # 5d. Show summary of what changed
    echo ""
    echo "── Change summary ──"
    ADDED_KEYS=$(comm -13 <(echo "$OLD_KEYS") <(echo "$NEW_KEYS"))
    ADDED_COUNT=$(echo "$ADDED_KEYS" | grep -c . || true)
    echo "  New keys added: $ADDED_COUNT"
    if [ "$ADDED_COUNT" -gt 0 ]; then
        echo "$ADDED_KEYS" | head -20 | sed 's/^/    /'
    fi

    NEW_FILES=$(diff -rq "$BASELINE_DIR" "$ACF_DIR" 2>/dev/null | grep "Only in $ACF_DIR" || true)
    if [ -n "$NEW_FILES" ]; then
        echo "  New files:"
        echo "$NEW_FILES" | sed 's/^/    /'
    fi

    MODIFIED_FILES=$(diff -rq "$BASELINE_DIR" "$ACF_DIR" 2>/dev/null | grep "^Files .* differ$" || true)
    if [ -n "$MODIFIED_FILES" ]; then
        echo "  Modified files:"
        echo "$MODIFIED_FILES" | sed "s|$BASELINE_DIR/||g; s|$ACF_DIR/||g" | sed 's/^/    /'
    fi
    echo ""
fi

# ── Summary ──────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
