# ACF WordPress Runtime Contract

These skills are intended to be installed globally, but they always operate on a target workspace that holds the real `.env`, schema JSON, and generated artifacts.

The preferred command surface is the repo wrapper:

```bash
wp-acf ...
```

Direct script invocation is still supported, but the wrapper is the primary documented entrypoint.

## Default workspace layout

```text
<workspace>/
├── .env
├── tmp/
│   └── wp-acf/
│       ├── diffs/
│       ├── preflight/
│       ├── schema-deploy/
│       │   └── bootstrap/
│       └── content-api/
└── wp-content/
    └── acf-json/
```

Schema remains canonical in `wp-content/acf-json/`.
Generated logs, allowlists, pull snapshots, push responses, and before/after diffs go under `tmp/wp-acf/` by default.

## Shared environment variables

All runtime-aware scripts support the same path contract:

| Variable | Default | Purpose |
|----------|---------|---------|
| `ACF_WORKSPACE_ROOT` | current working directory | Target workspace root |
| `ACF_ENV_FILE` | `.env` | Env file path relative to `ACF_WORKSPACE_ROOT` or absolute |
| `ACF_RUNTIME_DIR` | `tmp/wp-acf` | Shared runtime root relative to `ACF_WORKSPACE_ROOT` or absolute |
| `ACF_JSON_DIR` | `wp-content/acf-json` | Trusted schema directory relative to `ACF_WORKSPACE_ROOT` or absolute |
| `ACF_PREFLIGHT_RUNTIME_DIR` | `${ACF_RUNTIME_DIR}/preflight` | Preflight logs and payloads |
| `ACF_SCHEMA_DEPLOY_RUNTIME_DIR` | `${ACF_RUNTIME_DIR}/schema-deploy` | Schema pull/push and bootstrap artifacts |
| `ACF_CONTENT_API_RUNTIME_DIR` | `${ACF_RUNTIME_DIR}/content-api` | Content allowlists, pulls, pushes, and tests |

## Resolution rules

- Absolute paths stay absolute.
- Relative paths resolve against `ACF_WORKSPACE_ROOT`.
- Scripts never write generated files into the installed skill package.
- `ACF_JSON_DIR` is always explicit; scripts never auto-discover a schema directory from nearby folders.
- Existing auth variables such as `TARGET_BASE_URL`, `WP_API_USER`, `WP_API_APP_PASSWORD`, `ACF_AUTOMATION_SITE_ID`, and `ACF_AUTOMATION_SECRET` remain unchanged.

## Recommended usage

Run from the target workspace root when convenient:

```bash
wp-acf preflight --id 8
```

If the site uses a shared `globaldata` CPT record, add its ID so preflight verifies that path too:

```bash
export PREFLIGHT_GLOBALDATA_ID="200"
wp-acf preflight --id 8
```

Run from another current working directory by setting explicit overrides:

```bash
export ACF_WORKSPACE_ROOT="/abs/path/to/project"
export ACF_JSON_DIR="/abs/path/to/project/wp-content/acf-json"

wp-acf content pull --resource-type pages --id 8
```

Override only the artifact location when you want a custom local path:

```bash
export ACF_CONTENT_API_RUNTIME_DIR="tmp/wp-acf/content-api"
```

Schema pull/push and content push also write timestamped before/after diffs under `${ACF_RUNTIME_DIR}/diffs`.

## Rules

- Treat `skills/*.md` as the neutral source of truth for workflow and safety.
- Treat runtime-specific files as thin adapters only.
- Keep `tmp/` gitignored in target workspaces.
- Never commit live credentials from `.env`.
