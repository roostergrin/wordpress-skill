# ACF Schema Deploy

Safely manage ACF schema-as-code for a single main WordPress backend using the plugin API pull/push workflow.

**Use when:** requests involve pulling schema to local JSON, pushing updated schema JSON, bootstrapping automation auth, or deploying the plugin over SSH.

**Runtime model:** the scripts are global; the resolved workspace owns `.env`, `wp-content/acf-json/`, and `tmp/wp-acf/schema-deploy/`.

## Required Inputs

- A target workspace
- WordPress API config in the resolved env file
- A trusted schema directory, usually `wp-content/acf-json`
- Confirmation that the change targets the single `main` backend

## Hard Guardrails

- Edit only trusted schema JSON under the resolved `ACF_JSON_DIR`.
- Never expose secrets from `.env`, `wp-config.php`, or SSH keys.
- Use `pull` and `push` for schema transport.
- Treat push validation as server-side and authoritative.

## Quick Start

```bash
wp-acf schema bootstrap --claim-token <token>
wp-acf schema pull
wp-acf schema push --dry-run
wp-acf schema push
```

Intentional field-key changes:

```bash
wp-acf schema push --allow-field-key-changes
```

Direct script paths remain supported:

```bash
acf-schema-deploy/scripts/pull.sh
acf-schema-deploy/scripts/push.sh --dry-run
```

## Runtime Outputs

Default schema deploy artifacts live under:

```text
<workspace>/tmp/wp-acf/schema-deploy/
```

Override with `ACF_SCHEMA_DEPLOY_RUNTIME_DIR` if needed.

## Supported Commands

| Wrapper Command | Purpose |
|-----------------|---------|
| `wp-acf schema pull` | Pull schema from the WordPress API into the resolved `ACF_JSON_DIR` |
| `wp-acf schema push` | Push local `group_*.json` to the WordPress API |
| `wp-acf schema bootstrap` | Claim plugin-managed automation auth and write it into the resolved env file |
| `wp-acf schema deploy-plugin` | Build and upload the plugin over SSH using resolved env settings |

Both `pull.sh` and `push.sh` automatically generate a timestamped diff file under `<workspace>/tmp/wp-acf/diffs/` showing schema before and after the operation. The diff path is printed as the last output line (for example `diff=/abs/path/to/workspace/tmp/wp-acf/diffs/schema-push-20260303-143022.diff`).

## References

- `skills/config.md`
- `skills/acf-schema-edit.md`
- `acf-schema-deploy/references/bootstrap.md`
