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

On activation, the plugin creates the automation defaults used by the local scripts.

## 2) Preferred setup: copy the generated `.env` block

- Open WordPress `Settings > AI Automation`
- Click `Generate Copyable .env Block`
- Paste the output into the target workspace `.env`

This is the normal path now. In most cases, installing and activating the plugin is all you need on the WordPress side.

## 3) Optional fallback: Create Application Password user

- Use a WordPress user with capability required by plugin (`manage_options` by default).
- Generate an Application Password for that user.

## 4) Configure local target manually

```bash
cat > .env <<'EOF'
TARGET_BASE_URL="https://api-gordon-acf-demo.roostergrintemplates.com"
WP_API_USER="your-user"
WP_API_APP_PASSWORD="your-app-password"
EOF
```

Advanced CLI bootstrap if you explicitly need claim-token flow:

```bash
wp-acf schema bootstrap --claim-token <token>
```

Optional for sites that explicitly enable `acf_schema_api_require_signed_push`:

```bash
ACF_SCHEMA_API_HMAC_SECRET="your-hmac-secret"
```

Optional: set endpoint overrides directly in `./.env`:
- `TARGET_API_PULL_PATH`
- `TARGET_API_PUSH_PATH`
- `TARGET_API_PUSH_ROUTE`

## 5) Pull baseline schema

```bash
wp-acf schema pull
```

## 6) Smoke test push (dry-run)

```bash
wp-acf schema push --dry-run
```

If dry-run succeeds, plugin auth and schema validation are wired correctly.
