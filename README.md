# ACF WordPress Skills

Use these skills when you want an agent to work with ACF-backed WordPress content and schema.

From a user perspective, the flow is simple:

1. Install the WordPress plugin.
2. Install the skills globally.
3. Paste the generated `.env` block into your local workspace.
4. Ask the agent to use the right skill for setup, content queries, or schema changes.

`skills/*.md` are the real workflow docs. The `wp-acf` wrapper is the normal command surface behind the skills.

## 1. Install The WordPress Plugin

On the WordPress site:

1. Install and activate the `acf-schema-api` plugin.
2. Open `Settings > AI Automation`.
3. Click `Generate Copyable .env Block`.
4. Paste that block into your local workspace as `.env`.

That is the normal setup path now. You should not need a separate bootstrap step just to get started.

## 2. Install The Skills Globally

If you are using Codex, install these skills once into `$CODEX_HOME/skills`:

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo Gordoburrito/wordpress-skill \
  --ref main \
  --path wp-acf-preflight acf-schema-edit acf-schema-deploy wp-acf-content-api \
  --method git
```

These skills are global. You install them once, then use them against any local WordPress workspace.

## 3. Put The Wrapper On Your PATH

```bash
ln -sf /ABS/PATH/TO/wordpress-skill/bin/wp-acf ~/.local/bin/wp-acf
```

## 4. Prepare A Local Workspace

Your local project should look like this:

```text
<workspace>/
├── .env
├── tmp/
│   └── wp-acf/
└── wp-content/
    └── acf-json/
```

- `.env` comes from `Settings > AI Automation`
- `wp-content/acf-json/` is your trusted local schema
- `tmp/wp-acf/` is where pulls, diffs, logs, and payloads are written

If you are not running from the workspace root:

```bash
export ACF_WORKSPACE_ROOT="/abs/path/to/project"
export ACF_JSON_DIR="/abs/path/to/project/wp-content/acf-json"
```

## 5. Use The Skills

### Set up and verify a workspace

Ask the agent:

```text
Use $wp-acf-preflight to verify this workspace against page 8.
```

What it does:
- checks local dependencies
- verifies `.env`
- tests schema pull/push
- tests content pull/push dry-run

Command behind the skill:

```bash
wp-acf preflight --id 8
```

If the site uses a `globaldata` record:

```text
Use $wp-acf-preflight to verify this workspace against page 8 and globaldata 200.
```

```bash
wp-acf preflight --id 8 --globaldata-id 200
```

### Run content queries

Ask the agent:

```text
Use $wp-acf-content-api to pull page 8 and show me seo.page_title.
Use $wp-acf-content-api to pull page 8 and show me the full seo group.
Use $wp-acf-content-api to pull page 8 and list the top-level ACF fields.
```

Typical commands behind those queries:

```bash
wp-acf content allowlist
wp-acf content pull --resource-type pages --id 8
jq '.seo.page_title' tmp/wp-acf/content-api/pull-pages-8-acf.json
```

```bash
jq '.seo' tmp/wp-acf/content-api/pull-pages-8-acf.json
```

```bash
jq 'keys' tmp/wp-acf/content-api/pull-pages-8-acf.json
```

### Update existing content

Ask the agent:

```text
Use $wp-acf-content-api to update seo.page_title on page 8 to "Spring Release Landing Page".
```

The normal flow is:

1. Pull current content.
2. Build a payload using field names, not field keys.
3. Dry-run the write.
4. Apply the write.
5. Pull again to verify.

Example payload:

```json
{
  "acf": {
    "seo": {
      "page_title": "Spring Release Landing Page"
    }
  }
}
```

### Add a new field or layout

Ask the agent:

```text
Use $acf-schema-edit and $acf-schema-deploy to add an eyebrow field to the _Content component and push the schema.
```

Use this path when you need to change `wp-content/acf-json/`.

Small concrete example in this repo:
- edit `wp-content/acf-json/group_6377f7f384a4c.json`
- add a new `eyebrow` text field inside `fields[0].sub_fields`
- generate a new `field_` key
- update the top-level `modified` timestamp
- validate the JSON
- push with `wp-acf schema push --dry-run` and then `wp-acf schema push`

### Build a page from a design

Ask the agent to follow `skills/workflow.md` first, then use the skills in this order:

1. `wp-acf-preflight`
2. `acf-schema-edit`
3. `acf-schema-deploy`
4. `wp-acf-content-api`

## Skill Map

- `skills/wp-acf-preflight.md`: first-run setup and verification
- `skills/wp-acf-content-api.md`: content pulls, queries, and updates
- `skills/acf-schema-edit.md`: local ACF JSON edits
- `skills/acf-schema-deploy.md`: schema pull and push
- `skills/workflow.md`: end-to-end page workflow
- `skills/config.md`: workspace and path rules
