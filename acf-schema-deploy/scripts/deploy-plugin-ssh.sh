#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-plugin-ssh.sh [--plugin-repo <path>]

Build the local wp-acf-schema-api-plugin zip and deploy it over SSH to the current target in ./.env.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./api-common.sh
source "${SCRIPT_DIR}/api-common.sh"

PLUGIN_REPO="/Users/gordonlewis/wp-acf-schema-api-plugin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-repo)
      [[ $# -ge 2 ]] || fail "Missing value for --plugin-repo"
      PLUGIN_REPO="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ -f "${WORKSPACE_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${WORKSPACE_ENV_FILE}"
fi

: "${TARGET_SSH_HOST:?TARGET_SSH_HOST must be set in ${WORKSPACE_ENV_FILE}}"
: "${TARGET_SSH_USER:?TARGET_SSH_USER must be set in ${WORKSPACE_ENV_FILE}}"
: "${TARGET_SSH_PORT:?TARGET_SSH_PORT must be set in ${WORKSPACE_ENV_FILE}}"
: "${TARGET_SSH_KEY:?TARGET_SSH_KEY must be set in ${WORKSPACE_ENV_FILE}}"
: "${TARGET_REMOTE_PHP_DIR:?TARGET_REMOTE_PHP_DIR must be set in ${WORKSPACE_ENV_FILE}}"
: "${TARGET_WP_ROOT:?TARGET_WP_ROOT must be set in ${WORKSPACE_ENV_FILE}}"

require_command ssh
require_command scp
require_command zip

[[ -d "${PLUGIN_REPO}" ]] || fail "Plugin repo not found: ${PLUGIN_REPO}"

bash "${PLUGIN_REPO}/scripts/build-zip.sh" >/dev/null
ZIP_PATH="${PLUGIN_REPO}/dist/acf-schema-api.zip"
[[ -f "${ZIP_PATH}" ]] || fail "Build did not produce ${ZIP_PATH}"

timestamp="$(date +%Y%m%d-%H%M%S)"
remote_tmp="/tmp/acf-schema-api-deploy-${timestamp}"
remote_plugin_dir="${TARGET_WP_ROOT}/wp-content/plugins/acf-schema-api"
remote_backup_dir="${TARGET_WP_ROOT}/wp-content/plugins/.acf-schema-api-backups"

ssh_opts=(-i "${TARGET_SSH_KEY}" -p "${TARGET_SSH_PORT}" -o StrictHostKeyChecking=accept-new)
scp_opts=(-i "${TARGET_SSH_KEY}" -P "${TARGET_SSH_PORT}" -o StrictHostKeyChecking=accept-new)
remote="${TARGET_SSH_USER}@${TARGET_SSH_HOST}"

ssh "${ssh_opts[@]}" "${remote}" "mkdir -p '${remote_tmp}' '${remote_backup_dir}'"
scp "${scp_opts[@]}" "${ZIP_PATH}" "${remote}:${remote_tmp}/acf-schema-api.zip"

ssh "${ssh_opts[@]}" "${remote}" "bash -s" <<EOF
set -euo pipefail
REMOTE_TMP='${remote_tmp}'
REMOTE_PLUGIN_DIR='${remote_plugin_dir}'
REMOTE_BACKUP_DIR='${remote_backup_dir}'
TARGET_REMOTE_PHP_DIR='${TARGET_REMOTE_PHP_DIR}'
TARGET_WP_ROOT='${TARGET_WP_ROOT}'
STAMP='${timestamp}'

mkdir -p "\${REMOTE_TMP}/unpack"
unzip -oq "\${REMOTE_TMP}/acf-schema-api.zip" -d "\${REMOTE_TMP}/unpack"

if [[ ! -d "\${REMOTE_TMP}/unpack/acf-schema-api" ]]; then
  echo "Unpacked plugin directory not found." >&2
  exit 1
fi

if [[ -d "\${REMOTE_PLUGIN_DIR}" ]]; then
  cp -a "\${REMOTE_PLUGIN_DIR}" "\${REMOTE_BACKUP_DIR}/acf-schema-api-\${STAMP}"
fi

rm -rf "\${REMOTE_PLUGIN_DIR}.new"
cp -a "\${REMOTE_TMP}/unpack/acf-schema-api" "\${REMOTE_PLUGIN_DIR}.new"
rm -rf "\${REMOTE_PLUGIN_DIR}"
mv "\${REMOTE_PLUGIN_DIR}.new" "\${REMOTE_PLUGIN_DIR}"

PATH="\${TARGET_REMOTE_PHP_DIR}:\$PATH" wp --path="\${TARGET_WP_ROOT}" plugin activate acf-schema-api >/dev/null 2>&1 || \
  PATH="\${TARGET_REMOTE_PHP_DIR}:\$PATH" wp --path="\${TARGET_WP_ROOT}" plugin is-active acf-schema-api >/dev/null
EOF

echo "Plugin deployed to ${TARGET_SSH_HOST}"
echo "Remote temp dir: ${remote_tmp}"
echo "Remote plugin dir: ${remote_plugin_dir}"
