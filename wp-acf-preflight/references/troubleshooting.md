# WP ACF Preflight Troubleshooting

## Common Failures

### `.env` missing or incomplete
- Confirm the repo root contains `./.env`.
- Preferred fix: copy the plugin-generated `.env` block from WordPress.
- Fallback fix: add `TARGET_BASE_URL`, plus either:
  - `ACF_AUTOMATION_SITE_ID` + `ACF_AUTOMATION_SECRET`, or
  - `WP_API_USER` + `WP_API_APP_PASSWORD`

### Schema pull fails
- Confirm the `wp-acf-schema-api-plugin` is installed and active.
- Confirm the target user or automation secret can reach the schema endpoints.
- Re-run bootstrap if the plugin-managed secret was rotated.

### Content pull fails
- Confirm the resource ID exists and matches the allowlisted resource type.
- Confirm the resource exposes an `acf` object in the REST response.
- Confirm the authenticated user has permission to view the resource.

### Content dry-run passes but live write fails
- The selected field may not accept free-form string values.
- Re-run preflight with `--write-field <name>` using a known text or textarea field.
- Confirm WordPress Application Password auth or plugin-secret auth still has write access.

### Live rollback fails
- Inspect the logs under `./runtime/preflight/`.
- Pull the resource again and compare the current value against the rollback payload.
- If needed, restore the field manually using the logged rollback payload.
