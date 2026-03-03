# ACF WordPress — Active Repo Contract

These skills are intended to be installed globally and run from the target repo root.
They do not use the skill install directory as the workspace.

## Required repo-local paths

| Path | Purpose |
|------|---------|
| `./.env` | Repo-local WordPress API config and credentials |
| `./wp-content/acf-json/` | Canonical ACF schema JSON used for editing, deploy, and allowlist generation |
| `./runtime/preflight/` | Preflight logs, verification payloads, and troubleshooting output |
| `./runtime/content-api/` | Generated allowlists, pulled content snapshots, push responses, and test payloads |
| `./runtime/schema-deploy/` | Generated schema pull/push API responses |
| `./runtime/bootstrap/` | Claim/bootstrap responses and setup verification logs |

## Rules

- Run the skill from the target repo root.
- The current working directory is treated as the workspace exactly as-is.
- `acf-schema-edit` works against `./wp-content/acf-json/`.
- `wp-acf-preflight` reads `./.env`, verifies schema/content access, and stores logs under `./runtime/preflight/`.
- `acf-schema-deploy` reads `./.env`, writes schema JSON into `./wp-content/acf-json/`, and stores API logs under `./runtime/schema-deploy/`.
- `wp-acf-content-api` reads `./.env`, builds allowlists from `./wp-content/acf-json/`, and stores artifacts under `./runtime/content-api/`.
- If `ACF_AUTOMATION_SITE_ID` + `ACF_AUTOMATION_SECRET` are present, both skills use plugin-secret auth first.
- Otherwise they fall back to `WP_API_USER` + `WP_API_APP_PASSWORD`.
