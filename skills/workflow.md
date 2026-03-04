# ACF WordPress Workflow

This document connects the four ACF skills into a single workflow. Read it for high-level requests such as "build this page from a design" or "make this section match the mockup."

## Skill Chain

| Step | Skill | What it does |
|------|-------|--------------|
| 0. Verify setup | `skills/wp-acf-preflight.md` | Confirm auth, schema pull/push, content pull, and dry-run/live verification |
| 1. Edit schema | `skills/acf-schema-edit.md` | Create or modify ACF field group JSON locally |
| 2. Deploy schema | `skills/acf-schema-deploy.md` | Pull and push schema JSON through the WordPress plugin API |
| 3. Update content | `skills/wp-acf-content-api.md` | Read and write field values through the WordPress REST API |

Not every request needs every step.

## Wrapper-first workflow

### Step 0: Verify the workspace

```bash
wp-acf preflight --id 8
wp-acf preflight --id 8 --live
```

### Step 1: Analyze the design

- Map each section to an existing ACF layout before creating anything new.
- Prefer small field additions over new layouts.

### Step 2: Edit schema if needed

- Read `skills/acf-schema-edit.md`
- Modify trusted schema JSON under the resolved `ACF_JSON_DIR`

### Step 3: Deploy schema

```bash
wp-acf schema bootstrap --claim-token <token>
wp-acf schema pull
wp-acf schema push --dry-run
wp-acf schema push
```

### Step 4: Populate content

```bash
wp-acf content allowlist
wp-acf content pull --resource-type pages --id 8
wp-acf content push --resource-type pages --id 8 --payload payload.json --dry-run
wp-acf content push --resource-type pages --id 8 --payload payload.json
```

### Step 5: Verify

- Pull content again and confirm values match.
- Check the WordPress admin to confirm field groups render correctly.
