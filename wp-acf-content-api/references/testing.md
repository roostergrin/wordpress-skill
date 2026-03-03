# Testing

## Test runner

`scripts/run-tests.sh` automates integration tests for all core scripts.

### Prerequisites
- `jq` installed
- `./.env` configured in the current repo with either:
  - `ACF_AUTOMATION_SITE_ID` + `ACF_AUTOMATION_SECRET`
  - or `WP_API_APP_PASSWORD` plus the matching username variable
- Access to `./wp-content/acf-json/` in the current repo

### Usage

```bash
# Read-only tests (safe, no writes to WordPress)
scripts/run-tests.sh --id 8

# Full suite including real write + automatic rollback
scripts/run-tests.sh --id 8 --live
```

### What each test covers

| # | Test | Writes? | Needs `--live`? |
|---|------|---------|-----------------|
| 1 | `--help` exits clean for all 3 scripts | No | No |
| 2 | Allowlist generation: files created, key + name counts > 0 | No | No |
| 3 | Pull ACF content: JSON written, has fields | No | No |
| 4 | Blocked `users` endpoint rejected | No | No |
| 5 | Dry-run with valid allowlisted field name passes | No | No |
| 6a | Non-allowlisted field name rejected | No | No |
| 6b | Extra top-level keys in payload rejected | No | No |
| 7 | Real write + re-pull verification | Yes | Yes |
| 8 | Rollback to original value | Yes | Yes |
| 9 | Wrong legacy password or wrong plugin secret rejected on write path | No | No |

### Exit codes
- `0` — all tests passed (skips are OK)
- `1` — at least one FAIL

### Design notes
- **Safe by default.** Tests 7-8 are skipped unless `--live` is passed.
- **Automatic rollback.** Test 8 restores the original value snapshotted before test 7's write.
- **Repo-local test payloads.** Test payloads are written under `./runtime/content-api/tests/`.
- **Uses field names** (from `allowed-field-names.txt`), matching what the REST API expects.
- **Auth test uses push** (test 9), because public pages can be read without auth via
  the view context fallback — the real safety concern is unauthorized writes.
- **Auth from workspace env.** The runner prefers plugin-secret auth from `./.env`
  and falls back to `WP_API_APP_PASSWORD` if the automation vars are absent.

## Offline testing (no credentials)

Several safety tests work without real WordPress credentials by passing a
dummy value for `WP_API_APP_PASSWORD` when you are testing the legacy path:

```bash
export WP_API_APP_PASSWORD="dummy"

# Endpoint allowlist (should fail with "not allowlisted")
scripts/pull-content.sh --resource-type users --id 1

# Field-name allowlist (should fail with "outside allowlist")
echo '{"acf":{"totally_fake_field":"x"}}' > /tmp/t.json
scripts/push-content.sh --resource-type pages --id 8 --payload /tmp/t.json --dry-run

# Payload shape (should fail with "only an 'acf' object")
echo '{"acf":{"seo":"x"},"title":"bad"}' > /tmp/t.json
scripts/push-content.sh --resource-type pages --id 8 --payload /tmp/t.json --dry-run

# Empty acf (should fail with "no ACF keys")
echo '{"acf":{}}' > /tmp/t.json
scripts/push-content.sh --resource-type pages --id 8 --payload /tmp/t.json --dry-run

# Invalid ID formats (should fail with "positive integer")
scripts/pull-content.sh --resource-type pages --id abc
scripts/pull-content.sh --resource-type pages --id 0
```

## Validated edge cases

Tested and confirmed working:

| Input | Script | Result |
|-------|--------|--------|
| `--resource-type users` | pull / push | Rejected: "not allowlisted" |
| `--id abc` | pull / push | Rejected: "positive integer" |
| `--id 0` | pull / push | Rejected: "positive integer" |
| Missing `--id` | pull / push | Rejected: "--id is required" |
| `{"acf":{}}` (empty) | push --dry-run | Rejected: "no ACF keys to update" |
| `{"acf":{...},"title":"x"}` | push --dry-run | Rejected: "only an 'acf' object" |
| Name not in allowlist | push --dry-run | Rejected: "outside allowlist" |
| Missing auth vars | pull / push | Rejected: setup/auth error |
| Wrong legacy password on push | push | Rejected: curl 401 |
| Wrong plugin secret on push | push | Rejected: curl 401 |
| Wrong password on pull | pull | Legacy mode falls back to public view context (expected) |

## Lessons learned

### Field names vs field keys
The REST API uses field **names** (`seo`, `sections`) not field **keys** (`field_abc123`).
The `build-allowlist.sh` script generates both lists; `push-content.sh` validates against names.

### `context=edit` requires edit capability
The `?context=edit` query parameter returns raw/unrendered field values but requires
the `edit_post` capability. Regular passwords or read-only Application Passwords get 401.
The pull script now falls back to view context automatically.

### Public pages are readable without auth
WordPress pages with `status: publish` return ACF data on public view context.
Auth failure on pull doesn't mean the page is inaccessible — it means `context=edit` failed.
This is expected behavior, not a bug.

### Bash pitfall: arithmetic with set -e
Avoid `(( VAR++ ))` for counters that start at 0. The expression `(( 0++ ))` evaluates to 0,
which is falsy in arithmetic context, causing bash to exit with `set -e`. Use
`VAR=$(( VAR + 1 ))` instead.
