---
name: acf-schema-deploy
description: Safely manage ACF schema-as-code for headless WordPress through a pull/push API workflow. Use when requests involve wp-content/acf-json updates, schema pull, schema push, bootstrap, or plugin deployment.
---

# ACF Schema Deploy

## Purpose

Use this skill for a strict schema workflow:

1. Pull schema from the WordPress plugin API into trusted local JSON.
2. Review or edit local JSON.
3. Push local JSON back through the plugin API.

Validation, duplicate checks, and field-key stability checks are enforced server-side by the plugin.

## Runtime Model

- Scripts live in the installed skill package.
- The target workspace holds `.env`, `wp-content/acf-json/`, and generated artifacts.
- Prefer the wrapper:

```bash
wp-acf schema pull
wp-acf schema push --dry-run
wp-acf schema push
```

Direct script paths remain supported:

```bash
acf-schema-deploy/scripts/pull.sh
acf-schema-deploy/scripts/push.sh --dry-run
```

See `skills/config.md` for the shared env and path contract.

## Required Inputs

- A target workspace
- Trusted schema JSON in the resolved `ACF_JSON_DIR`
- WordPress API credentials or plugin-managed automation auth in the resolved env file
- A request to pull, push, bootstrap, or deploy the plugin

## Hard Guardrails

- Edit only trusted schema JSON.
- Never expose secrets from `.env`, `wp-config.php`, or SSH keys.
- Use the declared scripts for schema transport.
- Keep schema canonical in local Git under the resolved `ACF_JSON_DIR`.

## Commands

```bash
wp-acf schema bootstrap --claim-token <token>
wp-acf schema pull
wp-acf schema push --dry-run
wp-acf schema push
wp-acf schema deploy-plugin
```

## Outputs

Default artifacts:

```text
<workspace>/tmp/wp-acf/schema-deploy/
```

## References

- `skills/acf-schema-deploy.md`
- `skills/config.md`
- `references/bootstrap.md`
