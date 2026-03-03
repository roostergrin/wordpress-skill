# ACF WordPress Workflow

This document connects the four ACF skills into a unified workflow. Read this when handling high-level requests like "build this page section" or "make this look like this design."

## Skill Chain

| Step | Skill | What it does |
|------|-------|-------------|
| 0. Verify setup | `skills/wp-acf-preflight.md` | Confirm auth, schema pull/push, content pull, and dry-run/live verification |
| 1. Edit schema | `skills/acf-schema-edit.md` | Create/modify ACF field group JSON locally |
| 2. Deploy schema | `skills/acf-schema-deploy.md` | Pull/push schema JSON through WordPress plugin API |
| 3. Update content | `skills/wp-acf-content-api.md` | Read/write field values via REST API |

Not every request needs all three steps. Schema-only changes skip step 3. Content-only updates skip steps 1-2.

## Design-to-Schema Mapping

When given a screenshot, mockup, or design description of a page section, map the visual elements to existing ACF layouts before creating anything new.

### Existing Page Section Layouts (Page Sections: `group_62211673cd81a`)

| Visual Pattern | Layout Name | Key Components |
|---------------|-------------|----------------|
| Full-width banner with text overlay | `hero` | _Content + _Image + _Component-Options |
| Image on one side, text on the other | `image_text` | _Content + _Image + _Component-Options |
| Full-width image, no text | `image_only` | _Image + _Component-Options |
| Text block with large headline | `block_text_fh` | _Content + _Component-Options |
| Simple text block | `block_text_simple` | _Content + _Component-Options |
| Grid of cards/items | `block_grid` | Repeater of items with _Content + _Image |
| Masonry-style grid | `block_masonary_grid` | Repeater of items with _Image |
| Expandable FAQ/panels | `accordion` | Repeater of title/body pairs |
| Tabbed content sections | `tabs` | Repeater of tab panels |
| Row of items (features, services) | `multi_item_row` | Repeater of _Content + _Image items |
| Customer quotes (multiple) | `multi_item_testimonial` | Repeater of testimonial items |
| Single customer quote | `single_testimonial` | Text + author fields |
| Image carousel/slider | `single_image_slider` | Repeater of _Image items |
| Video carousel/slider | `single_video_slider` | Repeater of _Video items |
| Before/after comparison | `before_after_slider` | Repeater of image pairs |
| Row of logos | `logo_banner` | Repeater of _Image items |
| Promotional banner / CTA strip | `multi_use_banner` | _Content + _Image + CTA options |
| Blog post listing | `blog_posts` | Auto-populated from posts |
| Contact form | `form` | Linked to form config |
| Embedded map | `map` | Address/coordinates |

### Reusable Components (Tier 1)

Every layout above is built from these components via clone fields:

| Component | What it provides |
|-----------|-----------------|
| `_Content` | Header, subheader, body text, buttons, text alignment |
| `_Image` | Image source, WebP variant, alt text, display options |
| `_Video` | Video source with poster image |
| `_Button` | Button with type (link/anchor/nuxt), style, and link options |
| `_Form-Inputs` | Form field types (text, email, phone, textarea) |
| `_Component-Options` | Padding, margins, background color/image settings |

### Decision Process

1. **Can an existing layout handle it?** Check the table above. Most designs fit an existing layout.
2. **Does it need a small tweak?** Add a field to an existing layout (e.g., a toggle for a variant style).
3. **Is it truly new?** Create a new layout in Page Sections, cloning existing Tier 1 components.
4. **Does it need a new component type?** Only if no existing component covers the data shape — create a new Tier 1 component.

## Full Workflow: Screenshot to Live Page

Given a design/screenshot, follow these steps:

### Step 0: Verify the repo is ready
- Read `skills/wp-acf-preflight.md`
- Run preflight from the target repo root
- Use `--live` before demos or first production use

### Step 1: Analyze the design
- Identify each section/block in the layout
- Map each to an existing ACF layout (see table above)
- Note which sections need new layouts or field changes

### Step 2: Edit schema (if needed)
- Read `skills/acf-schema-edit.md`
- Modify or create field groups in `$ACF_JSON_DIR`
- Validate JSON after every edit

### Step 3: Deploy to WordPress
- Read `skills/acf-schema-deploy.md`
- Run from the target repo root
- Bootstrap repo-local automation auth once per site if needed:
  `scripts/bootstrap-repo.sh --claim-token <token>`
- Pull baseline if needed: `scripts/pull.sh`
- Dry-run push: `scripts/push.sh --dry-run`
- Apply push: `scripts/push.sh`

### Step 4: Populate content
- Read `skills/wp-acf-content-api.md`
- Build the local field allowlist from `./wp-content/acf-json/`
- Pull current page content to see structure
- Build payload with field **names** (not keys)
- Dry-run, then push

### Step 5: Verify
- Pull the page content again to confirm values match
- Check the WordPress admin to verify field groups appear correctly
