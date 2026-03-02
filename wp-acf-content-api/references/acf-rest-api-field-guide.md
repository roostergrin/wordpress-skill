# ACF REST API Field Guide

How to format payloads for each ACF field type when posting via the WordPress REST API.

## Key Principle

**Use field names, not field keys.** The REST API expects human-readable field names
(`seo`, `sections`, `title`) in the `acf` payload object — not internal keys (`field_abc123`).
The `build-allowlist.sh` script generates `runtime/content-api/allowed-field-names.txt` for validation.

**Mirror the GET response.** The safest approach: pull the current content, see the structure,
and format your POST payload to match it.

## Enabling Fields in the REST API

ACF field groups must be opted in individually:
1. Edit the field group in WP Admin
2. Settings tab > **Show in REST API** > Yes

Without this, the `acf` key will not appear in API responses.

## Payload Structure

```json
{
  "acf": {
    "field_name": "value"
  }
}
```

Partial updates are supported — only include fields you want to change.
Omitted fields remain unchanged.

## Field Type Reference

### Text / Textarea / WYSIWYG

```json
{
  "acf": {
    "my_text": "A string",
    "my_textarea": "Line 1\nLine 2",
    "my_wysiwyg": "<h2>Heading</h2><p>Paragraph.</p>"
  }
}
```

Type: `string` or `null`. WYSIWYG accepts raw HTML.

### True/False

```json
{ "acf": { "my_toggle": true } }
```

Type: `boolean` or `null`. Strings `"0"` / `"1"` also accepted.

### Select / Radio / Button Group

```json
{
  "acf": {
    "my_select": "option_value",
    "my_multi_select": ["value_1", "value_2"],
    "my_radio": "option_value"
  }
}
```

Single select = string. Multi-select = array of strings.

### Checkbox

```json
{ "acf": { "my_checkbox": ["value_1", "value_2"] } }
```

Always an array, even for a single selection.

### Number / Range

```json
{ "acf": { "my_number": 42 } }
```

Type: `number` or `null`.

### Date / Time

```json
{
  "acf": {
    "my_date": "20260219",
    "my_datetime": "2026-02-19 14:30:00",
    "my_time": "14:30:00"
  }
}
```

**Formats:** Date = `Ymd`, DateTime = `Y-m-d H:i:s`, Time = `H:i:s`.
Must match the stored format, not the display format.

### Image / File

```json
{ "acf": { "my_image": 456 } }
```

Type: `integer` (WordPress attachment ID) or `null`.
Always use the attachment ID regardless of the field's "Return Format" setting.
Upload files to `/wp-json/wp/v2/media` first, then use the returned ID.

### Gallery

```json
{ "acf": { "my_gallery": [123, 456, 789] } }
```

Array of attachment IDs.

### Link

```json
{
  "acf": {
    "my_link": {
      "title": "Click Here",
      "url": "https://example.com",
      "target": "_blank"
    }
  }
}
```

Object with `title`, `url`, `target` (empty string or `"_blank"`).

### Post Object / Relationship

```json
{
  "acf": {
    "my_post_object": 42,
    "my_relationship": [10, 20, 30]
  }
}
```

Single = integer post ID. Multiple = array of post IDs.

### Taxonomy

```json
{ "acf": { "my_taxonomy": ["slug-one", "slug-two"] } }
```

Uses term **slugs** (not term IDs).

### Group

```json
{
  "acf": {
    "my_group": {
      "sub_field_text": "text",
      "sub_field_number": 42
    }
  }
}
```

Object with sub-field name/value pairs.

### Repeater

```json
{
  "acf": {
    "my_repeater": [
      { "sub_text": "Row 1", "sub_image": 123 },
      { "sub_text": "Row 2", "sub_image": 456 }
    ]
  }
}
```

Array of objects. **Replaces the entire repeater** — you cannot patch a single row.
To add a row: GET current data, modify in code, PUT entire array back.

### Flexible Content

```json
{
  "acf": {
    "sections": [
      {
        "acf_fc_layout": "hero",
        "title": "Welcome",
        "image": 123
      },
      {
        "acf_fc_layout": "text_block",
        "content": "<p>Text here.</p>"
      }
    ]
  }
}
```

Array of objects. **Every object MUST include `acf_fc_layout`** matching the exact
layout name. Missing or wrong layout name = 400 error.

Like repeaters, the entire flexible content field is replaced.

### Tab / Accordion / Message

**Not present in the REST API.** These are purely UI elements in WP admin.
They have no data and are not included in responses or payloads.

## Gotchas

| Issue | Detail |
|-------|--------|
| Fields not showing | Enable "Show in REST API" per field group |
| `context=edit` 401 | User needs `edit_post` capability; fall back to view context |
| Null clears fields | `"my_field": null` empties the value |
| Repeaters replace entirely | Cannot append/update single rows |
| Flexible content needs layout | Every row needs `acf_fc_layout` |
| Images use attachment IDs | Not URLs, regardless of return format setting |
| Dates use stored format | `Ymd` not display format |
| New fields on old posts | May not appear until post is re-saved in admin |
| Application passwords required | Regular WP passwords do not grant REST API write access |
| **GET/POST schema mismatch** | **GET returns values that POST rejects — see critical section below** |

## Critical: GET/POST Schema Mismatch

**The most common failure when posting flexible content.** ACF's GET response
returns field values in a loose format that its own POST validation rejects.

You CANNOT simply pull the data and push it back unchanged. You must fix
mismatched values first.

### Known mismatches (confirmed in production)

| Field | GET returns | POST expects | Fix |
|-------|------------|--------------|-----|
| `button.icon` | `false` | string (min length 1) or null | Change to `""` |
| `video.type` | `false` | string (min length 1) or null | Change to `""` |
| `button_type` (in sub-fields) | `""` (empty string) | one of `nuxt_link`, `ext_link`, `button` | Set to `"nuxt_link"` or valid value |
| `social_links` | `false` | array | Change to `[]` |
| `multi_item_row` item `text` | any length | max 200 characters | Shorten text to fit |

### Fix pattern with jq

When building a payload from pulled data, apply fixes before pushing:

```bash
jq '
  # Fix boolean false -> empty string for string-typed fields
  (.. | objects | select(.icon? == false)) .icon = "" |
  (.. | objects | select(.video?) | select(.video.type? == false)).video.type = "" |
  # Fix empty enum values to default
  (.. | objects | select(.button_type? == "")) .button_type = "nuxt_link" |
  # Fix boolean false -> empty array for array-typed fields
  (.. | objects | select(.social_links? == false)) .social_links = []
' pulled-data.json > fixed-payload.json
```

### Why this happens

ACF stores `false` in the database for "no value" on fields that have select/choice
semantics. The GET response returns this stored `false` directly. But the POST
validation schema has strict type requirements (string, array, enum) that reject
`false`.

### Debugging approach

When you get a 400 error on POST, read the full error response:
```bash
curl -sS -u "user:pass" -H "Content-Type: application/json" \
  -X POST --data-binary '@payload.json' \
  "https://site.com/wp-json/wp/v2/pages/8" | jq '.data.params.acf'
```

The error message tells you the exact path and reason: fix that field and retry.
Iterate until it succeeds — usually only 2-3 fixes are needed.

## Application Passwords vs Regular Passwords

WordPress REST API write operations require **Application Passwords** (WP 5.6+).
Regular login passwords authenticate for read-only on some configurations but
**cannot write** via the REST API.

To create an Application Password:
1. WP Admin > Users > Your Profile
2. Scroll to "Application Passwords"
3. Enter a name, click "Add New Application Password"
4. Copy the generated password (format: `xxxx xxxx xxxx xxxx xxxx xxxx`)

Store it in `./.env` in the current repo as `WP_API_APP_PASSWORD` (gitignored)
or export it as an environment variable.

## The `acf_format` Query Parameter

Controls how ACF formats field values in GET responses:
- `?acf_format=light` (default) — raw/stored values (image fields = attachment IDs)
- `?acf_format=standard` — full formatting (image fields = full image objects/URLs)

POST payloads always use the raw/stored format regardless of this parameter.
