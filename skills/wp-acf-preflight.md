# WP ACF Preflight

Safely verify that the current repo is ready for WordPress ACF automation before schema or content work begins.

**Use when:** onboarding a new repo, validating a new WordPress connection, or debugging auth/schema/content setup.

**Paths:** see `skills/config.md`. When this global skill runs, the current working directory is the target repo root. It reads `./.env`, checks schema in `./wp-content/acf-json/`, and writes logs to `./runtime/preflight/`.

## Required Inputs
- Run from the target repo root.
- One existing WordPress resource ID for content verification (`--id <id>`), or set `PREFLIGHT_RESOURCE_ID` in `./.env`.
- Optional `--live` to verify real schema apply plus content write/rollback.

## Hard Guardrails
- Never expose secrets from `./.env`.
- Refuse to run against a dirty `./wp-content/acf-json/` unless `--allow-dirty` is explicitly set.
- Safe mode performs only non-destructive checks plus schema pull.
- Live mode uses the just-pulled schema for a no-op push apply and automatically rolls back the temporary content write.

## Quick Start
```bash
# Safe preflight
scripts/preflight.sh --id 8

# Full live verification
scripts/preflight.sh --id 8 --live
```

## What It Verifies
1. Local dependencies (`bash`, `curl`, `jq`)
2. Repo-local `.env`
3. Schema pull
4. Schema push dry-run
5. Optional live schema push apply
6. Allowlist generation from local schema
7. Content pull
8. Content push dry-run
9. Optional live content write + rollback

## Script
| Script | Purpose |
|--------|---------|
| `scripts/preflight.sh` | Unified readiness check for schema deploy + content API |

## References
- `wp-acf-preflight/references/troubleshooting.md`
- `skills/acf-schema-deploy.md`
- `skills/wp-acf-content-api.md`
