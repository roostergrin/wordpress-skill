# ACF WordPress Skills

Claude Code skills for managing Advanced Custom Fields on a headless WordPress site. Four skills cover the full lifecycle: **preflight**, **schema editing**, **deployment**, and **content management**.

The WordPress schema transport plugin now lives in a separate repository, `wp-acf-schema-api-plugin`. This repo no longer vendors the plugin source or zip artifact.

## Global Install, Repo-Local Runtime

Install these skills globally once. When they run, they should operate on the current repo, not on the skill install directory.

Target repo contract:

```text
.
├── .env
├── runtime/
│   ├── preflight/
│   ├── content-api/
│   └── schema-deploy/
└── wp-content/
    └── acf-json/
```

Run the skill from the target repo root. The current working directory is treated as the workspace exactly as-is.

## Project Structure

```
.
├── .env.example               # Shared env template for all skills
├── CLAUDE.md                  # Claude Code instructions (auto-loaded)
├── skills/                    # Skill definitions
│   ├── workflow.md            # End-to-end workflow (design → live page)
│   ├── wp-acf-preflight.md    # Verify setup/auth/schema/content readiness
│   ├── acf-schema-edit.md     # Create/modify ACF field group JSON
│   ├── acf-schema-deploy.md   # Pull/push schema JSON via WordPress plugin API
│   ├── wp-acf-content-api.md  # Read/write field values via REST API
│   └── config.md              # Path configuration reference
├── wp-acf-preflight/          # Skill package: setup verification
│   ├── SKILL.md               # Skill entrypoint
│   └── scripts/               # preflight runner
├── acf-schema-edit/           # Skill package: schema editing
│   ├── SKILL.md               # Skill entrypoint
│   └── references/            # Schema editing references
├── acf-schema-deploy/         # Deployment scripts & server config
│   ├── SKILL.md               # Skill entrypoint
│   ├── scripts/               # pull, push (API flow)
│   └── wp-content/acf-json/   # ACF field group JSON files (11 groups)
└── wp-acf-content-api/        # Skill package: content API
    ├── SKILL.md               # Skill entrypoint
    └── scripts/               # build-allowlist, pull-content, push-content
```

## Install in Codex

Install these skills into your global Codex skills directory (`$CODEX_HOME/skills`)
using the built-in `skill-installer` script.

### Install all skills

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo Gordoburrito/wordpress-skill \
  --ref main \
  --path wp-acf-preflight acf-schema-edit acf-schema-deploy wp-acf-content-api \
  --method git
```

### Install one skill

```bash
# Replace <skill-path> with one of:
# wp-acf-preflight | acf-schema-edit | acf-schema-deploy | wp-acf-content-api
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo Gordoburrito/wordpress-skill \
  --ref main \
  --path <skill-path> \
  --method git
```

Restart Codex to pick up new skills.

## Quick Start

### 1. Configure credentials

From the target repo root, either paste the copyable `.env` block from WordPress
`Settings > Codex Automation`, or create/update `.env` manually.

```bash
cp .env.example .env
# Edit with your WordPress URL, username, and Application Password
```

Minimum required values:

```bash
cat > .env <<'EOF'
TARGET_BASE_URL="https://api-gordon-acf-demo.roostergrintemplates.com"
WP_API_USER="your-user"
WP_API_APP_PASSWORD="your-app-password"
EOF
```

Optional for WordPress installs that explicitly re-enable signed schema pushes:

```bash
ACF_SCHEMA_API_HMAC_SECRET="your-hmac-secret"
```

Preferred setup flow from the plugin admin page:

1. Open WordPress `Settings > Codex Automation`
2. Click `Generate Copyable .env Block`
3. Paste that block into the target repo root as `.env`

Alternative CLI bootstrap flow when the plugin exposes a claim token:

```bash
scripts/bootstrap-repo.sh --claim-token <token>
```

### 2. Run preflight

```bash
scripts/preflight.sh --id 8
```

Use `--live` when you want to verify real schema apply plus content write/rollback:

```bash
scripts/preflight.sh --id 8 --live
```

### 3. Build the field allowlist

```bash
scripts/build-allowlist.sh
```

### 4. Pull current page content

```bash
scripts/pull-content.sh --resource-type pages --id 8
```

### 4. Push a content update

```bash
# Always dry-run first
scripts/push-content.sh --resource-type pages --id 8 --payload payload.json --dry-run

# Then push for real
scripts/push-content.sh --resource-type pages --id 8 --payload payload.json
```

## Skills Reference

### Preflight (`skills/wp-acf-preflight.md`)

Verify that the repo, auth, schema API, and content API are ready before you start a recipe.

| Command | Script |
|---------|--------|
| Safe preflight | `scripts/preflight.sh --id <id>` |
| Full live verification | `scripts/preflight.sh --id <id> --live` |
| Override live write field | `scripts/preflight.sh --id <id> --write-field <field-name>` |

### Schema Editing (`skills/acf-schema-edit.md`)

Edit ACF field group JSON files locally. Handles new fields, new layouts, new reusable components, and modifications to existing structures.

| Task | What to do |
|------|-----------|
| Add a field to an existing layout | Edit the layout's `sub_fields` in the Page Sections JSON |
| Create a new page section layout | Add a layout entry, clone Tier 1 components |
| Create a new reusable component | New `group_*.json` file prefixed with `_` |
| Modify field options | Edit the field's properties, keep `key` and `name` unchanged |

### Schema Deployment (`skills/acf-schema-deploy.md`)

Pull and push schema JSON through the WordPress ACF Schema API plugin. The plugin itself is maintained in the separate `wp-acf-schema-api-plugin` repository.

| Command | Script |
|---------|--------|
| Pull schema | `scripts/pull.sh` |
| Push schema dry-run | `scripts/push.sh --dry-run` |
| Push schema apply | `scripts/push.sh` |
| Push with intentional key changes | `scripts/push.sh --allow-field-key-changes` |
| Backward-compatible alias | `scripts/deploy-main.sh` |
| Bootstrap repo from claim token | `scripts/bootstrap-repo.sh --claim-token <token>` |
| Deploy plugin over SSH | `scripts/deploy-plugin-ssh.sh` |

### Content Management (`skills/wp-acf-content-api.md`)

Read and write ACF field values via the WordPress REST API. Uses Application Passwords for authentication.

| Command | Script |
|---------|--------|
| Build field allowlist | `scripts/build-allowlist.sh` |
| Pull page/post content | `scripts/pull-content.sh --resource-type pages --id <id>` |
| Push content update | `scripts/push-content.sh --resource-type pages --id <id> --payload <file>` |
| Run test suite (read-only) | `scripts/run-tests.sh --id <id>` |
| Run test suite (with writes) | `scripts/run-tests.sh --id <id> --live` |

## Common Workflows

### Verify onboarding before a demo

Run preflight first. This confirms auth, schema pull/push, allowlist generation, content pull, and optional live write/rollback.

```bash
scripts/preflight.sh --id 8
scripts/preflight.sh --id 8 --live
```

### Update text on an existing page

Content API only — no schema changes needed.

```bash
scripts/pull-content.sh --resource-type pages --id 8    # See current values
# Create payload.json with your changes
scripts/push-content.sh --resource-type pages --id 8 --payload payload.json --dry-run
scripts/push-content.sh --resource-type pages --id 8 --payload payload.json
```

### Add a new section type and populate it

Full skill chain: edit → deploy → content.

```bash
# 1. Edit schema JSON
#    (modify ./wp-content/acf-json/group_62211673cd81a.json)

# 2. Pull + push schema
scripts/pull.sh
scripts/push.sh --dry-run
scripts/push.sh

# 3. Rebuild allowlist and push content
scripts/build-allowlist.sh
scripts/push-content.sh --resource-type pages --id 8 --payload payload.json
```

### Build a page from a design

Read `skills/workflow.md` for the full process. In short:

1. Map visual sections to existing ACF layouts (20+ available)
2. Edit schema only if new layouts or fields are needed
3. Deploy schema changes
4. Populate content via REST API
5. Pull content again to verify

## Key Concepts

- **Field names vs field keys**: The REST API uses human-readable names (`seo`, `sections`), not internal keys (`field_abc123`).
- **Three-tier architecture**: Tier 1 = reusable components (`_Content`, `_Image`, etc.), Tier 2 = page builders with flexible content, Tier 3 = global/meta settings.
- **Flexible content**: The entire `sections` array must be sent on every update — no partial updates. Every object needs `acf_fc_layout`.
- **Preflight first**: Use `wp-acf-preflight` to confirm the repo, plugin auth, schema endpoints, and content endpoints are all working before a demo or first edit.
- **Plugin-managed automation secrets**: Preferred when the plugin is installed and claimed. Local scripts use repo-local automation credentials first, then fall back to WordPress Application Passwords.
- **Application Passwords**: Still supported as a fallback for REST/API writes and bootstrap.
- **GET/POST mismatch**: ACF returns `false` for empty fields, but rejects it on POST. Fix before pushing: `false` → `""` for select fields, `false` → `[]` for arrays.

## Prerequisites

- **jq** — used by schema/content JSON tooling
- **curl** — used by content API scripts
- **A verification page/post ID** — recommended for preflight and content tests
- **Schema API plugin repo deployed to WordPress + credentials** — required for schema pull/push
- **WordPress Application Password** — required for content writes

## Testing

```bash
# Read-only tests (safe, no writes)
scripts/run-tests.sh --id 8

# Full test suite with write + automatic rollback
scripts/run-tests.sh --id 8 --live
```

All deploy and content scripts support `--dry-run` and `--help`.
