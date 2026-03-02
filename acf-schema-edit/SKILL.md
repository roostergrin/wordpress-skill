---
name: acf-schema-edit
description: Safely edit ACF field group JSON files by hand, following existing schema patterns, reusing components via clone fields, and maintaining key stability. Use when requests involve creating or modifying ACF field groups, adding new fields, building new page section layouts, or creating reusable components.
---

# ACF Schema Edit

## Purpose
Use this skill to manually create or edit ACF Pro field group JSON files.
Treat the current working directory as the target repo root.
All edits target `./wp-content/acf-json/`.

## Required Inputs
- What to add or change (new field, new layout, new component, etc.)
- Which field group(s) to modify (or whether a new group is needed)

## Hard Guardrails
- Edit only `*.json` files inside `wp-content/acf-json/`.
- Never change an existing field `key` (breaks data linkage).
- Never change an existing field `name` (breaks stored meta data).
- Always generate new keys using `field_` + 13-char hex (use `openssl rand -hex 7 | cut -c1-13`).
- Always update the `modified` timestamp to current Unix time when editing a file.
- Always validate JSON after editing (run `python3 -m json.tool <file>`).
- Reuse existing components via clone fields before creating new ones.

## Architecture: Three-Tier Field Group System

### Tier 1: Reusable Components (underscore-prefixed)
Building blocks cloned into larger field groups. Located at post ID 1024 for development.

| Component | Key | Purpose |
|-----------|-----|---------|
| _Button | `group_6377f23bd0d95` | Button with type/style/link options |
| _Content | `group_6377f7f384a4c` | Header, subheader, body, buttons + alignment options |
| _Image | `group_637d51daf049c` | Image src/webp/alt + display options |
| _Video | `group_6410c804e62ee` | Video with poster image |
| _Form-Inputs | `group_638922bc44e99` | Flexible form input layouts |
| _Component-Options | `group_63894140af6e3` | Shared padding/margin/background settings |

### Tier 2: Page Builders
Use `flexible_content` with layouts that clone Tier 1 components.

| Group | Key | Layouts |
|-------|-----|---------|
| Page Sections | `group_62211673cd81a` | 20 layouts (hero, image_text, accordion, etc.) |
| Blog Post | `group_65a05d3d240f7` | Blog structure with cloned _Image |
| Form Input Fields | `group_640a5467bef99` | Form config with cloned _Content |

### Tier 3: Global / Meta
Site-wide settings not tied to page building.

| Group | Key | Purpose |
|-------|-----|---------|
| Global Data | `group_5f5fa4564ddd4` | Site-wide settings (contact, social, etc.) |
| SEO - Meta Data | `group_606757d748983` | Per-page SEO fields |

## How to Clone an Existing Component

To reuse _Image in a new layout, add a clone field:

```json
{
    "key": "field_<new-13-char-hex>",
    "label": "Image",
    "name": "image",
    "type": "clone",
    "clone": ["group_637d51daf049c"],
    "display": "seamless",
    "layout": "block",
    "prefix_label": 0,
    "prefix_name": 0
}
```

Set `prefix_name: 1` if you clone the same component multiple times in one layout
(e.g., `main_image` and `thumbnail_image` in Blog Post).

Available clone targets:
- `group_6377f23bd0d95` — _Button (button type, style, link)
- `group_6377f7f384a4c` — _Content (header, body, buttons, alignment)
- `group_637d51daf049c` — _Image (src, webp, alt, display options)
- `group_6410c804e62ee` — _Video (video src, poster)
- `group_638922bc44e99` — _Form-Inputs (text, email, phone, textarea)
- `group_63894140af6e3` — _Component-Options (padding, margins, background)

## How to Add a New Layout to Page Sections

1. Open `group_62211673cd81a.json` (Page Sections).
2. Find the `layouts` object inside the `page_sections` flexible_content field.
3. Add a new layout key:

```json
"layout_<new-13-char-hex>": {
    "key": "layout_<same-hex>",
    "name": "my_new_section",
    "label": "My New Section",
    "display": "block",
    "sub_fields": [
        {
            "key": "field_<new-hex>",
            "label": "Content",
            "name": "content",
            "type": "clone",
            "clone": ["group_6377f7f384a4c"],
            "display": "seamless",
            "layout": "block",
            "prefix_label": 0,
            "prefix_name": 0
        },
        {
            "key": "field_<new-hex>",
            "label": "Component Options",
            "name": "component_options",
            "type": "clone",
            "clone": ["group_63894140af6e3"],
            "display": "seamless",
            "layout": "block",
            "prefix_label": 0,
            "prefix_name": 0
        }
    ],
    "min": "",
    "max": ""
}
```

4. Update the `modified` timestamp at the top level.

## How to Create a New Reusable Component

1. Create a new file: `group_<new-13-char-hex>.json`
2. Use this template:

```json
{
    "key": "group_<same-hex>",
    "title": "_ComponentName",
    "fields": [
        {
            "key": "field_<new-hex>",
            "label": "Component Name",
            "name": "component_name",
            "type": "group",
            "layout": "block",
            "sub_fields": []
        }
    ],
    "location": [
        [
            {
                "param": "post",
                "operator": "==",
                "value": "1024"
            }
        ]
    ],
    "menu_order": 0,
    "position": "normal",
    "style": "default",
    "label_placement": "top",
    "instruction_placement": "label",
    "hide_on_screen": "",
    "active": 1,
    "description": "",
    "show_in_rest": 0,
    "modified": <current-unix-timestamp>
}
```

3. Prefix the title with `_` to mark it as reusable.
4. Assign location to post ID 1024 (the component library post).
5. Wrap fields in a `group` with `layout: "block"` for clean cloning.

## Field Naming Conventions

| Element | Convention | Examples |
|---------|-----------|----------|
| Field group key | `group_` + 13-char hex | `group_6377f23bd0d95` |
| Field key | `field_` + 13-char hex | `field_6377f23ce456f` |
| Layout key | `layout_` + 13-char hex | `layout_6389414178e93` |
| Field name | snake_case, descriptive | `button`, `text_alignment`, `src` |
| Field label | Title Case | `Text Alignment`, `Background Color` |
| Component title | `_PascalCase` | `_Button`, `_Content`, `_Image` |
| Layout name | snake_case | `image_text`, `block_grid`, `hero` |

## Conditional Logic Pattern

Used in _Button for type-dependent fields. Structure:

```json
"conditional_logic": [
    [
        {
            "field": "field_<key-of-trigger-field>",
            "operator": "==",
            "value": "anchor"
        }
    ]
]
```

Outer array = OR groups. Inner array = AND conditions within a group.
Operators: `==`, `!=`, `==empty`, `!=empty`, `pattern`, `contains`.

## Tab Organization Pattern

Components use tabs to separate content from styling options:

```json
{
    "key": "field_<hex>",
    "label": "Content",
    "name": "",
    "type": "tab",
    "placement": "top",
    "endpoint": 0
},
// ... content fields ...
{
    "key": "field_<hex>",
    "label": "Options",
    "name": "",
    "type": "tab",
    "placement": "top",
    "endpoint": 0
},
// ... option fields ...
```

## Workflow

1. Identify what to change/add.
2. Check if an existing component can be cloned (Tier 1).
3. Generate new field keys: `openssl rand -hex 7 | cut -c1-13`
4. Edit the JSON file.
5. Update the `modified` timestamp: `date +%s`
6. Validate: `python3 -m json.tool < file.json > /dev/null`
7. Deploy using `acf-schema-deploy` skill.

## References
- `references/acf-json-schema-reference.md` — Full ACF JSON schema reference (all field types, all settings)
- `../acf-schema-deploy/SKILL.md` — Deploy workflow (export, pull, deploy, import)
