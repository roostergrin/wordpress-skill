---
name: acf-schema-deploy
description: Safely manage ACF schema-as-code for headless WordPress through a pull/push API workflow. Use when requests involve wp-content/acf-json updates, schema pull, or schema push to the single main WordPress backend.
---

# ACF Schema Deploy

## Purpose
Use this skill for a strict two-command schema workflow:
1. Pull schema from WordPress plugin API to local JSON.
2. Push local JSON back through the plugin API.

Treat the current working directory as the target repo root. Schema remains canonical in local Git under `./wp-content/acf-json/**`.
Validation, duplicate checks, and field-key stability checks are enforced server-side by the plugin.

## Required Inputs
- Schema change request.
- Target is always single `main` backend.

## Hard Guardrails
- Edit only `wp-content/acf-json/**` inside the schema repo.
- Never edit frontend repositories.
- Never print or expose secrets (`.env`, `wp-config.php`, SSH private keys).
- Never run arbitrary shell commands outside declared scripts.
- Use only `pull.sh` and `push.sh` for schema transport.
- Push uses authenticated WordPress API requests and optimistic lock (`expected_hash`).

## Quick Start
```bash
# Run from the target repo root.

# 1) Pull latest schema from WordPress
scripts/pull.sh

# 2) Edit local JSON files in ./wp-content/acf-json/

# 3) Push schema back (dry-run first, then apply)
scripts/push.sh --dry-run
scripts/push.sh

# If intentionally adding/removing/changing field keys:
scripts/push.sh --allow-field-key-changes
```

## Configuration
Set root-level env in:
```bash
./.env
```

Required values:
- `TARGET_BASE_URL` (or `WP_API_BASE_URL`)
- `WP_API_USER` (or `WP_API_USERNAME` / `TARGET_API_USER`)
- `WP_API_APP_PASSWORD` (or `TARGET_API_APP_PASSWORD`)

Optional for sites that explicitly require signed pushes:
- `ACF_SCHEMA_API_HMAC_SECRET` (or `TARGET_API_HMAC_SECRET`)

## Scripts
| Script | Purpose |
|--------|---------|
| `scripts/pull.sh` | Pull schema from `/wp-json/acf-schema/v1/pull` and write local `group_*.json` files |
| `scripts/push.sh` | Push local schema to `/wp-json/acf-schema/v1/push` |
| `scripts/deploy-main.sh` | Backward-compatible alias to `scripts/push.sh` |

## Workflow Detail
1. Pull latest schema: `scripts/pull.sh`
2. Apply local edits under `./wp-content/acf-json/**`.
3. Review diff in Git.
4. Run push dry-run: `scripts/push.sh --dry-run`
5. Apply push: `scripts/push.sh`

## References
- `references/bootstrap.md`: plugin/API bootstrap and config.
- `references/github-actions-main.yml`: push-to-main CI workflow template.

## Expected Response Pattern
1. State changed files under `wp-content/acf-json/**`.
2. State pull/push result (dry-run vs apply).
3. Provide concise diff summary.
4. If requested, provide exact command invocations.
