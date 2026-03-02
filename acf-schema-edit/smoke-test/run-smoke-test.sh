#!/usr/bin/env bash
# run-smoke-test.sh — End-to-end smoke test for acf-schema-edit skill
#
# What it does:
#   1. Snapshots all acf-json files as a baseline
#   2. Adds a new "smoke_test" layout to Page Sections (following the skill's rules)
#   3. Runs validate-acf.sh against the result
#   4. Restores the original files
#
# Usage: ./run-smoke-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(pwd -P)"
ACF_DIR="${WORKSPACE_ROOT}/wp-content/acf-json"
BASELINE_DIR="/tmp/acf-smoke-baseline"
PAGE_SECTIONS="$ACF_DIR/group_62211673cd81a.json"

cleanup() {
    echo ""
    echo "── Restoring baseline ──"
    if [ -d "$BASELINE_DIR" ]; then
        cp "$BASELINE_DIR"/*.json "$ACF_DIR/"
        rm -rf "$BASELINE_DIR"
        echo "  Original files restored."
    fi
}
trap cleanup EXIT

# ── Step 1: Snapshot baseline ─────────────────────────────────────
echo "=== ACF Schema Edit — Smoke Test ==="
echo ""
echo "── Step 1: Taking baseline snapshot ──"
rm -rf "$BASELINE_DIR"
mkdir -p "$BASELINE_DIR"
cp "$ACF_DIR"/*.json "$BASELINE_DIR/"
FILE_COUNT=$(ls "$BASELINE_DIR"/*.json | wc -l)
echo "  Backed up $FILE_COUNT files to $BASELINE_DIR"

# ── Step 2: Validate baseline is clean ────────────────────────────
echo ""
echo "── Step 2: Validating baseline (pre-edit) ──"
if ! bash "$SCRIPT_DIR/validate-acf.sh" "$ACF_DIR"; then
    echo "  Baseline already has issues — aborting."
    exit 1
fi

# ── Step 3: Perform a real edit (simulate skill invocation) ───────
echo ""
echo "── Step 3: Performing test edit ──"
echo "  Task: Add 'smoke_test' layout to Page Sections"

# Generate keys the way the skill prescribes
KEY1=$(openssl rand -hex 7 | cut -c1-13)
KEY2=$(openssl rand -hex 7 | cut -c1-13)
KEY3=$(openssl rand -hex 7 | cut -c1-13)
LAYOUT_KEY=$(openssl rand -hex 7 | cut -c1-13)
TIMESTAMP=$(date +%s)

echo "  Generated keys:"
echo "    layout_$LAYOUT_KEY"
echo "    field_$KEY1 (content clone)"
echo "    field_$KEY2 (image clone)"
echo "    field_$KEY3 (component_options clone)"

# Build the new layout as a JSON fragment
NEW_LAYOUT=$(cat <<ENDJSON
{
    "key": "layout_$LAYOUT_KEY",
    "name": "smoke_test",
    "label": "Smoke Test",
    "display": "block",
    "sub_fields": [
        {
            "key": "field_$KEY1",
            "label": "Content",
            "name": "content",
            "type": "clone",
            "clone": ["group_6377f7f384a4c"],
            "display": "seamless",
            "layout": "block",
            "prefix_label": 0,
            "prefix_name": 0
        },
        {
            "key": "field_$KEY2",
            "label": "Image",
            "name": "image",
            "type": "clone",
            "clone": ["group_637d51daf049c"],
            "display": "seamless",
            "layout": "block",
            "prefix_label": 0,
            "prefix_name": 0
        },
        {
            "key": "field_$KEY3",
            "label": "Component Options",
            "name": "component_options",
            "type": "clone",
            "clone": ["group_63894140af6e3"],
            "display": "seamless",
            "layout": "block",
            "prefix_label": 0,
            "prefix_name": 0
        }
    ],
    "min": "",
    "max": ""
}
ENDJSON
)

# Insert the layout into Page Sections using jq
# Also update the modified timestamp
jq --argjson layout "$NEW_LAYOUT" \
   --arg lkey "layout_$LAYOUT_KEY" \
   --argjson ts "$TIMESTAMP" \
   '.fields[0].layouts[$lkey] = $layout | .modified = $ts' \
   "$PAGE_SECTIONS" > "${PAGE_SECTIONS}.tmp" \
   && mv "${PAGE_SECTIONS}.tmp" "$PAGE_SECTIONS"

echo "  Edit applied. Modified timestamp set to $TIMESTAMP"

# Verify the layout was actually added
NEW_COUNT=$(jq '.fields[0].layouts | length' "$PAGE_SECTIONS")
echo "  Layout count: 20 -> $NEW_COUNT"

# ── Step 4: Validate the edited state ─────────────────────────────
echo ""
echo "── Step 4: Validating post-edit state ──"
bash "$SCRIPT_DIR/validate-acf.sh" "$ACF_DIR" "$BASELINE_DIR"
RESULT=$?

echo ""
if [ "$RESULT" -eq 0 ]; then
    echo "=== SMOKE TEST PASSED ==="
else
    echo "=== SMOKE TEST FAILED ==="
fi

# cleanup runs via trap
exit $RESULT
