# ACF Schema Deploy (API Pull/Push)

This skill manages ACF schema JSON through the WordPress plugin API:

- Pull from `POST /wp-json/acf-schema/v1/pull`
- Push to `POST /wp-json/acf-schema/v1/push`

Local schema remains canonical in `wp-content/acf-json/group_*.json`.
The plugin code is maintained in the standalone `wp-acf-schema-api-plugin` repository rather than this skills repo.
Skill entrypoint for Codex is this directory's `SKILL.md`.

## Commands

```bash
# Run from the target repo root.

# Pull latest schema from WordPress
scripts/pull.sh

# Push dry-run (recommended first)
scripts/push.sh --dry-run

# Push apply
scripts/push.sh

# Intentionally changing field keys
scripts/push.sh --allow-field-key-changes
```

`scripts/deploy-main.sh` is a backward-compatible alias to `scripts/push.sh`.

## Configure Target

Set root-level env (preferred):
```bash
cp .env.example .env

cat > .env <<'EOF'
TARGET_BASE_URL="https://api-gordon-acf-demo.roostergrintemplates.com"
WP_API_USER="your-user"
WP_API_APP_PASSWORD="your-app-password"
EOF
```

Optional when a site explicitly opts back into signed pushes:

```bash
ACF_SCHEMA_API_HMAC_SECRET="your-hmac-secret"
```

## Validation Model

Validation is server-side in the plugin:

- JSON payload structure checks
- Duplicate sibling field name checks
- Field-key stability checks (unless `allow_field_key_changes=true`)
- Optional schema hash lock (`expected_hash`)
- Optional signed push verification when the site enables it

## Notes

- This flow does not require SSH for day-to-day schema updates.
- WP-CLI is optional and only needed for server diagnostics or plugin operations.
