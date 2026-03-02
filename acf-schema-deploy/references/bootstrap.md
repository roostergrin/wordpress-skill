# Bootstrap (Plugin API Flow)

This runbook configures the schema repo for pull/push via the ACF Schema API plugin.
The plugin is maintained in the separate `wp-acf-schema-api-plugin` repository.

## 1) Install/enable plugin on WordPress

- Plugin repo: `wp-acf-schema-api-plugin`
- Plugin file: `acf-schema-api.php`
- Endpoint namespace: `acf-schema/v1`
- Required routes:
  - `POST /wp-json/acf-schema/v1/pull`
  - `POST /wp-json/acf-schema/v1/push`

## 2) Create Application Password user

- Use a WordPress user with capability required by plugin (`manage_options` by default).
- Generate an Application Password for that user.

## 3) Configure local target

```bash
cat > .env <<'EOF'
TARGET_BASE_URL="https://api-gordon-acf-demo.roostergrintemplates.com"
WP_API_USER="your-user"
WP_API_APP_PASSWORD="your-app-password"
EOF
```

Optional for sites that explicitly enable `acf_schema_api_require_signed_push`:

```bash
ACF_SCHEMA_API_HMAC_SECRET="your-hmac-secret"
```

Optional: set endpoint overrides directly in `./.env`:
- `TARGET_API_PULL_PATH`
- `TARGET_API_PUSH_PATH`
- `TARGET_API_PUSH_ROUTE`

## 4) Pull baseline schema

```bash
scripts/pull.sh
```

## 5) Smoke test push (dry-run)

```bash
scripts/push.sh --dry-run
```

If dry-run succeeds, plugin auth and schema validation are wired correctly.
