# ACF WordPress — Active Repo Contract

These skills are intended to be installed globally and run from the target repo root.
They do not use the skill install directory as the workspace.

## Required repo-local paths

| Path | Purpose |
|------|---------|
| `./.env` | Repo-local WordPress API config and credentials |
| `./wp-content/acf-json/` | Canonical ACF schema JSON used for editing, deploy, and allowlist generation |
| `./runtime/content-api/` | Generated allowlists, pulled content snapshots, push responses, and test payloads |
| `./runtime/schema-deploy/` | Generated schema pull/push API responses |

## Rules

- Run the skill from the target repo root.
- The current working directory is treated as the workspace exactly as-is.
- `acf-schema-edit` works against `./wp-content/acf-json/`.
- `acf-schema-deploy` reads `./.env`, writes schema JSON into `./wp-content/acf-json/`, and stores API logs under `./runtime/schema-deploy/`.
- `wp-acf-content-api` reads `./.env`, builds allowlists from `./wp-content/acf-json/`, and stores artifacts under `./runtime/content-api/`.
