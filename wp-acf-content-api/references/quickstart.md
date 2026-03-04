# Quickstart

## 1) Configure the target workspace

Create or update the resolved env file:

```bash
cp .env.example .env
```

Preferred when the plugin exposes a claim token:

```bash
wp-acf schema bootstrap --claim-token <token>
```

Minimum env values:

- `TARGET_BASE_URL`
- `WP_API_USER`
- `WP_API_APP_PASSWORD`
- optional plugin-managed auth:
  - `ACF_AUTOMATION_SITE_ID`
  - `ACF_AUTOMATION_SECRET`
  - `ACF_AUTOMATION_CONTENT_BASE_PATH`
- `ALLOWED_RESOURCE_TYPES` defaults to `pages,posts`

If you are running from another current working directory:

```bash
export ACF_WORKSPACE_ROOT="/abs/path/to/project"
export ACF_JSON_DIR="/abs/path/to/project/wp-content/acf-json"
```

## 2) Generate the field-name allowlist

```bash
wp-acf content allowlist
```

Default outputs:

- `tmp/wp-acf/content-api/allowed-field-names.txt`
- `tmp/wp-acf/content-api/allowed-field-keys.txt`

## 3) Pull current content

```bash
wp-acf content pull --resource-type pages --id 8
```

Default outputs:

- `tmp/wp-acf/content-api/pull-pages-8-raw.json`
- `tmp/wp-acf/content-api/pull-pages-8-acf.json`

## 4) Build a payload

Use field names, not field keys:

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

## 5) Dry-run the write

```bash
wp-acf content push --resource-type pages --id 8 --payload /ABS/PATH/payload.json --dry-run
```

## 6) Apply the write

```bash
wp-acf content push --resource-type pages --id 8 --payload /ABS/PATH/payload.json
```

## 7) Verify

```bash
wp-acf content pull --resource-type pages --id 8
jq '.seo.page_title' tmp/wp-acf/content-api/pull-pages-8-acf.json
```
