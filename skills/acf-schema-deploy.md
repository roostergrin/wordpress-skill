# ACF Schema Deploy

Safely manage ACF schema-as-code for a single main WordPress backend using a plugin API pull/push flow.

**Use when:** requests involve pulling schema to local JSON or pushing updated schema JSON to WordPress.
Assumes the standalone `wp-acf-schema-api-plugin` repository is already installed on the target WordPress site.

**Paths:** see `skills/config.md`. When this global skill runs, the current working directory is the target repo root. It uses `./.env`, `./wp-content/acf-json/`, and `./runtime/schema-deploy/`.

## Required Inputs
- Schema change to deploy, or request to pull latest schema.
- Confirmation this is for the single `main` backend.
- For bootstrap setup: a one-time claim token or claim URL from the WordPress plugin.

## Hard Guardrails
- Edit only `wp-content/acf-json/**` inside the schema repo.
- Never edit frontend repositories.
- Never print or expose secrets (`.env`, `wp-config.php`, private keys).
- Never run arbitrary shell outside declared scripts.
- Use only `pull.sh` and `push.sh` for schema transport.
- Push auth comes from WordPress API credentials; signed push is optional.

## Quick Start
```bash
# Run from the target repo root.

# Preferred: bootstrap once from a claim token exposed by the plugin
scripts/bootstrap-repo.sh --claim-token <token>

# Pull from WordPress
scripts/pull.sh

# Edit JSON files locally (see skills/acf-schema-edit.md)

# Push dry-run then apply
scripts/push.sh --dry-run
scripts/push.sh

# For intentional field-key set changes
scripts/push.sh --allow-field-key-changes
```

## Scripts
| Script | Purpose |
|--------|---------|
| `scripts/pull.sh` | Pull schema from WordPress API into local `wp-content/acf-json/` |
| `scripts/push.sh` | Push local `group_*.json` to WordPress API |
| `scripts/deploy-main.sh` | Backward-compatible alias to `push.sh` |
| `scripts/bootstrap-repo.sh` | Claim a plugin-managed automation secret and write repo-local `.env` keys |
| `scripts/deploy-plugin-ssh.sh` | Build and upload the WordPress plugin over SSH using repo-local target config |

Validation now runs in the plugin API:
- payload structure checks
- duplicate sibling field-name checks
- field-key stability checks (unless explicitly allowed)
- optional signed push checks when the site enables them

## Workflow Detail
1. Pull: `scripts/pull.sh`
2. Edit JSON locally.
3. Review diff.
4. Push dry-run: `scripts/push.sh --dry-run`
5. Push apply: `scripts/push.sh`

## References
- `acf-schema-deploy/references/bootstrap.md`
- `acf-schema-deploy/references/github-actions-main.yml`
