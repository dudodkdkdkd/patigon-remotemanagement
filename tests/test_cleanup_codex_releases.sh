#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="${SCRIPT_DIR}/../scripts/cleanup_codex_releases.sh"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

assert_directory_exists() {
  if [[ ! -d "$1" ]]; then
    echo "Expected directory to exist: $1" >&2
    exit 1
  fi
}

assert_directory_missing() {
  if [[ -d "$1" ]]; then
    echo "Expected directory to be removed: $1" >&2
    exit 1
  fi
}

CODEX_HOME="${TEST_ROOT}/home/.codex"
RELEASES_DIR="${CODEX_HOME}/packages/standalone/releases"
STANDALONE_DIR="$(dirname "$RELEASES_DIR")"
PROC_ROOT="${TEST_ROOT}/proc"

for release in \
  0.1.0-x86_64-unknown-linux-musl \
  0.2.0-x86_64-unknown-linux-musl \
  0.3.0-x86_64-unknown-linux-musl \
  0.4.0-x86_64-unknown-linux-musl; do
  mkdir -p "${RELEASES_DIR}/${release}/bin"
  printf '%s\n' "$release" > "${RELEASES_DIR}/${release}/version"
done

ln -s "${RELEASES_DIR}/0.4.0-x86_64-unknown-linux-musl" "${STANDALONE_DIR}/current"
printf '#!/usr/bin/env sh\n' \
  > "${RELEASES_DIR}/0.1.0-x86_64-unknown-linux-musl/bin/codex"
chmod +x "${RELEASES_DIR}/0.1.0-x86_64-unknown-linux-musl/bin/codex"
mkdir -p "${PROC_ROOT}/1234"
ln -s "${RELEASES_DIR}/0.1.0-x86_64-unknown-linux-musl/bin/codex" \
  "${PROC_ROOT}/1234/exe"

CODEX_PROC_ROOT="$PROC_ROOT" \
  "$CLEANUP_SCRIPT" --codex-home "$CODEX_HOME" --dry-run

release_count="$(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[[ "$release_count" == "4" ]]

CODEX_PROC_ROOT="$PROC_ROOT" \
  "$CLEANUP_SCRIPT" --codex-home "$CODEX_HOME"

assert_directory_exists "${RELEASES_DIR}/0.1.0-x86_64-unknown-linux-musl"
assert_directory_missing "${RELEASES_DIR}/0.2.0-x86_64-unknown-linux-musl"
assert_directory_exists "${RELEASES_DIR}/0.3.0-x86_64-unknown-linux-musl"
assert_directory_exists "${RELEASES_DIR}/0.4.0-x86_64-unknown-linux-musl"

"$CLEANUP_SCRIPT" --codex-home "${TEST_ROOT}/missing/.codex"

if "$CLEANUP_SCRIPT" --releases-dir "${TEST_ROOT}/unsafe" >/dev/null 2>&1; then
  echo "Expected unsafe releases path to be rejected" >&2
  exit 1
fi

ESCAPE_STANDALONE="${TEST_ROOT}/escape/.codex/packages/standalone"
ESCAPE_TARGET="${TEST_ROOT}/escape-target"
mkdir -p \
  "${ESCAPE_STANDALONE}" \
  "${ESCAPE_TARGET}/0.1.0-x86_64-unknown-linux-musl/bin" \
  "${ESCAPE_TARGET}/0.2.0-x86_64-unknown-linux-musl/bin" \
  "${ESCAPE_TARGET}/0.3.0-x86_64-unknown-linux-musl/bin"
ln -s "$ESCAPE_TARGET" "${ESCAPE_STANDALONE}/releases"
ln -s "${ESCAPE_TARGET}/0.3.0-x86_64-unknown-linux-musl" "${TEST_ROOT}/current"

if "$CLEANUP_SCRIPT" \
  --releases-dir "${ESCAPE_STANDALONE}/releases" \
  --dry-run >/dev/null 2>&1; then
  echo "Expected a symlinked releases directory to be rejected" >&2
  exit 1
fi

assert_directory_exists "${ESCAPE_TARGET}/0.1.0-x86_64-unknown-linux-musl"
assert_directory_exists "${ESCAPE_TARGET}/0.2.0-x86_64-unknown-linux-musl"
assert_directory_exists "${ESCAPE_TARGET}/0.3.0-x86_64-unknown-linux-musl"

echo "Codex release cleanup tests passed"
