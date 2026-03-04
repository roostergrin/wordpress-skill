---
name: wp-acf-preflight
description: Verify that a target workspace is ready for WordPress ACF automation by checking local tooling, auth loading, schema pull/push, allowlist generation, content pull, and optional live write/rollback.
---

# WP ACF Preflight

## Purpose

Use this skill before schema or content work.
It verifies that the resolved workspace can safely talk to the target WordPress site and that the end-to-end automation flow is actually working.

## Runtime Model

- Scripts live in the installed skill package.
- The target workspace holds `.env`, trusted schema JSON, and generated artifacts.
- Prefer the wrapper:

```bash
wp-acf preflight --id 8
```

Direct script path remains supported:

```bash
wp-acf-preflight/scripts/preflight.sh --id 8
```

See `skills/config.md` for path overrides.

## Required Inputs

- A resolved env file
- A trusted schema directory
- One existing WordPress resource ID for content verification
- Optional `PREFLIGHT_GLOBALDATA_ID` or `--globaldata-id` when the site relies on a `globaldata` CPT record
- Optional `--live` for apply + rollback checks

## Hard Guardrails

- Never expose secrets from the resolved env file.
- Default mode is safe: schema pull, schema push dry-run, allowlist generation, content pull, and content push dry-run only.
- When `PREFLIGHT_GLOBALDATA_ID` is set, safe mode also verifies a `globaldata` pull and dry-run push.
- `--live` performs a schema apply plus one temporary content update with rollback.
- Refuse to run if the resolved `ACF_JSON_DIR` is dirty unless `--allow-dirty` is set.

## Outputs

Default artifacts:

```text
<workspace>/tmp/wp-acf/preflight/
```

## References

- `skills/wp-acf-preflight.md`
- `skills/config.md`
- `skills/acf-schema-deploy.md`
- `skills/wp-acf-content-api.md`
