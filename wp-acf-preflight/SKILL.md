---
name: wp-acf-preflight
description: Verify that a target repo is ready for WordPress ACF automation by checking local tooling, repo-local auth, schema pull/push, allowlist generation, content pull, and optional live write/rollback.
---

# WP ACF Preflight

## Purpose
Use this skill before any schema or content work.
It verifies that the current repo can safely talk to the target WordPress site and that the end-to-end automation flow is actually working.

## Use When
- Setting up a repo for the first time.
- Connecting a repo to a new WordPress site.
- Troubleshooting schema/content automation failures.
- Confirming onboarding is complete before a demo.

## Required Inputs
- Run from the target repo root.
- A configured `./.env` in the current repo, or plugin-managed automation auth written by bootstrap.
- One existing WordPress resource ID to verify content pull/write (recommended: a non-critical page used for testing).

## Hard Guardrails
- Never edit frontend code.
- Never expose secrets from `./.env`.
- Default mode is safe: it performs schema pull, schema push dry-run, allowlist generation, content pull, and content push dry-run.
- `--live` mode performs a no-op schema apply plus one temporary content update with automatic rollback.
- Refuse to run if `./wp-content/acf-json/` has uncommitted changes unless `--allow-dirty` is set.

## Quick Start
```bash
# Safe verification
scripts/preflight.sh --id 8

# Full live verification
scripts/preflight.sh --id 8 --live
```

Optional overrides:
```bash
scripts/preflight.sh --id 8 --resource-type pages --write-field page_title
scripts/preflight.sh --id 8 --live --allow-dirty
```

## What It Checks
1. Required local commands are installed.
2. Repo-local `.env` exists and auth can load.
3. Schema pull works.
4. Schema push dry-run works.
5. Optional live schema push apply works.
6. Content allowlist generation works.
7. Content pull works.
8. Content push dry-run works.
9. Optional live content write and rollback work.

## Scripts
| Script | Purpose |
|--------|---------|
| `scripts/preflight.sh` | Unified repo-level readiness check for schema + content automation |

## References
- `wp-acf-preflight/references/troubleshooting.md`
- `skills/config.md`
- `skills/acf-schema-deploy.md`
- `skills/wp-acf-content-api.md`
