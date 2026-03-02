# Quickstart

## 1) Configure API target
Create or update the repo-local env file:
```bash
cp .env.example .env
```

Edit `./.env`:
- `TARGET_BASE_URL` — your WordPress site URL
- `WP_API_USER` — WordPress username
- `WP_API_APP_PASSWORD` — WordPress Application Password (not regular password)
- `ALLOWED_RESOURCE_TYPES` — comma-separated endpoint types (default: `pages,posts`)

The `.env` file is gitignored. Alternatively, set `WP_API_APP_PASSWORD` as an environment variable:
```bash
export WP_API_APP_PASSWORD='xxxx xxxx xxxx xxxx xxxx xxxx'
```

### Creating an Application Password
Regular WordPress passwords do not work for REST API writes.
1. WP Admin > Users > Your Profile
2. Scroll to "Application Passwords"
3. Enter a name, click "Add New Application Password"
4. Copy the generated password (format: `xxxx xxxx xxxx xxxx xxxx xxxx`)

## 2) Generate field-name allowlist from trusted schema

```bash
scripts/build-allowlist.sh
```

Outputs:
- `runtime/content-api/allowed-field-names.txt` — used by push-content.sh for validation
- `runtime/content-api/allowed-field-keys.txt` — internal field keys for reference

Regenerate after any schema changes.

## 3) Pull current content snapshot

```bash
scripts/pull-content.sh --resource-type pages --id 8
```

Outputs:
- `runtime/content-api/pull-pages-8-raw.json` — full API response
- `runtime/content-api/pull-pages-8-acf.json` — extracted ACF object only

The pull script tries `context=edit` first (returns raw values, needs edit capability)
and falls back to view context if the user lacks permissions.

## 4) Create update payload

Payload must contain only the `acf` object. Use **field names** (not field keys):

```json
{
  "acf": {
    "seo": {
      "page_title": "Updated Page Title",
      "page_description": "Updated description."
    }
  }
}
```

Partial updates are supported — only include fields you want to change.

See `references/acf-rest-api-field-guide.md` for formatting rules per field type.

## 5) Validate with dry-run

```bash
scripts/push-content.sh --resource-type pages --id 8 --payload /ABS/PATH/payload.json --dry-run
```

## 6) Apply update

```bash
scripts/push-content.sh --resource-type pages --id 8 --payload /ABS/PATH/payload.json
```

## 7) Verify

```bash
scripts/pull-content.sh --resource-type pages --id 8
# Check the updated field:
jq '.seo.page_title' runtime/content-api/pull-pages-8-acf.json
```
