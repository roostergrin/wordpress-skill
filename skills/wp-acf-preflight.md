# WP ACF Preflight

Safely verify that a target workspace is ready for WordPress ACF automation before schema or content work begins.

**Use when:** onboarding a new workspace, validating a new WordPress connection, or debugging auth/schema/content setup.

**Runtime model:** use the global wrapper, but operate on the local target workspace. See `skills/config.md` for the shared env contract.

## Required Inputs

- A target workspace with a resolved `.env`
- One existing WordPress resource ID for content verification: `--id <id>`
- Optional `PREFLIGHT_GLOBALDATA_ID` or `--globaldata-id <id>` to verify the `globaldata` CPT path too
- Optional `--live` for real schema apply plus content write/rollback

## Hard Guardrails

- Never expose secrets from the resolved env file.
- Refuse to run against a dirty resolved `ACF_JSON_DIR` unless `--allow-dirty` is explicitly set.
- Safe mode performs schema pull, schema push dry-run, allowlist generation, content pull, and content push dry-run.
- When `PREFLIGHT_GLOBALDATA_ID` is present, safe mode also runs a `globaldata` pull and content push dry-run.
- Live mode performs a schema apply plus one temporary content write with automatic rollback.

## Quick Start

```bash
wp-acf preflight --id 8
wp-acf preflight --id 8 --live
wp-acf preflight --id 8 --globaldata-id 200
```

Direct script path, if needed:

```bash
wp-acf-preflight/scripts/preflight.sh --id 8
```

## What It Verifies

1. Local dependencies (`bash`, `curl`, `jq`)
2. Resolved env file exists and can be loaded
3. Schema pull works
4. Schema push dry-run works
5. Optional live schema push apply works
6. Content allowlist generation works
7. Content pull works
8. Content push dry-run works
9. Optional `globaldata` content pull and dry-run push work
10. Optional live content write and rollback work

## Optional `globaldata` Target

If the site stores shared settings in a `globaldata` CPT record, add one of these:

```bash
export PREFLIGHT_GLOBALDATA_ID="200"
wp-acf preflight --id 8
```

or:

```bash
wp-acf preflight --id 8 --globaldata-id 200
```

Use the route token `globaldata` here, not `globalData`.

## Runtime Outputs

Default preflight artifacts live under:

```text
<workspace>/tmp/wp-acf/preflight/
```

Override with `ACF_PREFLIGHT_RUNTIME_DIR` if needed.

## References

- `skills/config.md`
- `skills/acf-schema-deploy.md`
- `skills/wp-acf-content-api.md`
- `wp-acf-preflight/references/troubleshooting.md`
