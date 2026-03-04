# ACF WordPress Skills

Neutral ACF automation skills for headless WordPress. The repo is designed to work across multiple LLM runtimes by separating:

- a shared core of shell scripts and `skills/*.md` docs
- thin runtime adapters for Codex/OpenAI, Claude, Copilot, Cursor, and Windsurf

The WordPress schema transport plugin lives in the separate `wp-acf-schema-api-plugin` repository.

## Command Surface

The preferred entrypoint is the wrapper:

```bash
wp-acf preflight [args...]
wp-acf schema pull [args...]
wp-acf schema push [args...]
wp-acf schema bootstrap [args...]
wp-acf schema deploy-plugin [args...]
wp-acf content allowlist [args...]
wp-acf content pull [args...]
wp-acf content push [args...]
wp-acf content test [args...]
```

Direct script paths remain supported, but the wrapper is the primary documented interface.

## Target Workspace Contract

The installed scripts are global. The workspace is local.

```text
<workspace>/
├── .env
├── tmp/
│   └── wp-acf/
│       ├── preflight/
│       ├── schema-deploy/
│       └── content-api/
└── wp-content/
    └── acf-json/
```

- `.env` contains WordPress credentials and site settings.
- `wp-content/acf-json/` is the trusted local schema source.
- `tmp/wp-acf/` holds generated artifacts only.

See [skills/config.md](/Users/gordonlewis/wordpress-skill/skills/config.md) for the full path contract.

## Install

### Wrapper

Symlink the wrapper into your `PATH`:

```bash
ln -sf /Users/gordonlewis/wordpress-skill/bin/wp-acf ~/.local/bin/wp-acf
```

Any equivalent `PATH` setup is fine.

### Codex install

Install these skills into `$CODEX_HOME/skills` with the built-in installer:

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo Gordoburrito/wordpress-skill \
  --ref main \
  --path wp-acf-preflight acf-schema-edit acf-schema-deploy wp-acf-content-api \
  --method git
```

## Quick Start

### 1. Configure the target workspace

From the target workspace, create or update `.env`.

Minimum manual config:

```bash
cat > .env <<'EOF'
TARGET_BASE_URL="https://example.com"
WP_API_USER="your-user"
WP_API_APP_PASSWORD="your-app-password"
EOF
```

Preferred setup from WordPress:

1. Open `Settings > Codex Automation`
2. Generate the copyable `.env` block
3. Paste it into the target workspace as `.env`

### 2. Run preflight

```bash
wp-acf preflight --id 8
wp-acf preflight --id 8 --live
wp-acf preflight --id 8 --globaldata-id 200
```

### 3. Pull or push schema

```bash
wp-acf schema pull
wp-acf schema push --dry-run
wp-acf schema push
```

### 4. Read or update content

```bash
wp-acf content allowlist
wp-acf content pull --resource-type pages --id 8
wp-acf content push --resource-type pages --id 8 --payload payload.json --dry-run
wp-acf content push --resource-type pages --id 8 --payload payload.json
```

## Running From Another Directory

If you are not in the target workspace, point the scripts at it explicitly:

```bash
export ACF_WORKSPACE_ROOT="/abs/path/to/project"
export ACF_JSON_DIR="/abs/path/to/project/wp-content/acf-json"

wp-acf content pull --resource-type pages --id 8
```

Default generated artifacts go to:

```text
<workspace>/tmp/wp-acf/
```

## Skills

- [skills/wp-acf-preflight.md](/Users/gordonlewis/wordpress-skill/skills/wp-acf-preflight.md): verify setup, auth, schema, and content automation
- [skills/acf-schema-edit.md](/Users/gordonlewis/wordpress-skill/skills/acf-schema-edit.md): edit field groups safely by hand
- [skills/acf-schema-deploy.md](/Users/gordonlewis/wordpress-skill/skills/acf-schema-deploy.md): pull and push schema through the WordPress plugin API
- [skills/wp-acf-content-api.md](/Users/gordonlewis/wordpress-skill/skills/wp-acf-content-api.md): build allowlists, pull content, and push content changes
- [skills/workflow.md](/Users/gordonlewis/wordpress-skill/skills/workflow.md): full design-to-schema-to-content workflow

## LLM Runtime Notes

- `skills/*.md` are the canonical workflow docs.
- Runtime-specific files should only describe when to use a skill and where the shared docs live.
- No runtime-specific file should contain unique workflow logic.
