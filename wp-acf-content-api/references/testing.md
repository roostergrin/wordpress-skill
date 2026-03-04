# Testing

## Test runner

`wp-acf content test` runs integration checks for the content API scripts.

### Prerequisites

- `jq` installed
- A resolved env file with either:
  - `ACF_AUTOMATION_SITE_ID` + `ACF_AUTOMATION_SECRET`
  - or `WP_API_APP_PASSWORD` plus the matching username variable
- Access to trusted schema JSON in the resolved `ACF_JSON_DIR`

### Usage

```bash
wp-acf content test --id 8
wp-acf content test --id 8 --live
```

Direct script path remains supported:

```bash
wp-acf-content-api/scripts/run-tests.sh --id 8
```

### Coverage

| # | Test | Writes? | Needs `--live`? |
|---|------|---------|-----------------|
| 1 | `--help` exits clean for all core scripts | No | No |
| 2 | Allowlist generation writes key and name files | No | No |
| 3 | Content pull writes valid ACF JSON | No | No |
| 4 | Blocked endpoint types are rejected | No | No |
| 5 | Dry-run accepts a valid allowlisted field name | No | No |
| 6a | Non-allowlisted field name is rejected | No | No |
| 6b | Extra top-level payload keys are rejected | No | No |
| 7 | Real write and re-pull verification | Yes | Yes |
| 8 | Rollback to the original value | Yes | Yes |
| 9 | Wrong legacy password or plugin secret is rejected on write | No | No |

### Artifact location

Default test payloads and responses are written under:

```text
<workspace>/tmp/wp-acf/content-api/tests/
```

### Offline safety checks

Some validation checks work without live credentials:

```bash
export WP_API_APP_PASSWORD="dummy"

wp-acf content pull --resource-type users --id 1
```
