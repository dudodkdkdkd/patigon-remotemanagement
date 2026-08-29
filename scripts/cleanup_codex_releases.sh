#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
CODEX_HOME="${CODEX_HOME:-/root/.codex}"
RELEASES_DIR=""
PROC_ROOT="${CODEX_PROC_ROOT:-/proc}"

usage() {
  cat <<'EOF'
Usage: cleanup_codex_releases.sh [OPTIONS]

Safely remove obsolete Codex standalone releases.

Options:
  --codex-home PATH    Codex home to manage (default: /root/.codex)
  --releases-dir PATH  Explicit standalone releases directory
  --dry-run            Show what would be removed without deleting anything
  -h, --help           Show this help

The current release, every running release, and one additional newest rollback
release are always preserved.
EOF
}

log() {
  printf '[codex-release-cleanup] %s\n' "$1"
}

fail() {
  printf '[codex-release-cleanup] Error: %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex-home)
      [[ $# -ge 2 ]] || fail "--codex-home requires a path"
      CODEX_HOME="$2"
      shift 2
      ;;
    --releases-dir)
      [[ $# -ge 2 ]] || fail "--releases-dir requires a path"
      RELEASES_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -z "$RELEASES_DIR" ]]; then
  RELEASES_DIR="${CODEX_HOME%/}/packages/standalone/releases"
fi

case "$RELEASES_DIR" in
  */.codex/packages/standalone/releases) ;;
  *)
    fail "refusing unexpected releases directory: $RELEASES_DIR"
    ;;
esac

if [[ ! -d "$RELEASES_DIR" ]]; then
  log "No releases directory found at $RELEASES_DIR"
  exit 0
fi

RELEASES_DIR="$(cd "$RELEASES_DIR" && pwd -P)"
case "$RELEASES_DIR" in
  */.codex/packages/standalone/releases) ;;
  *)
    fail "refusing releases directory after symlink resolution: $RELEASES_DIR"
    ;;
esac
STANDALONE_DIR="$(dirname "$RELEASES_DIR")"

declare -a RELEASE_NAMES=()
declare -a PROTECTED_RELEASES=()

is_protected_release() {
  local expected="$1"
  local protected_release

  for protected_release in "${PROTECTED_RELEASES[@]:-}"; do
    if [[ "$protected_release" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

protect_release_path() {
  local release_path="$1"
  local resolved
  local relative
  local release_name

  resolved="$(readlink -f "$release_path" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || return 1

  case "$resolved" in
    "$RELEASES_DIR"/*) ;;
    *) return 1 ;;
  esac

  relative="${resolved#"$RELEASES_DIR"/}"
  release_name="${relative%%/*}"
  [[ -n "$release_name" && -d "$RELEASES_DIR/$release_name" ]] || return 1

  if ! is_protected_release "$release_name"; then
    PROTECTED_RELEASES+=("$release_name")
  fi
}

current_target="$(readlink -f "$STANDALONE_DIR/current" 2>/dev/null || true)"
if [[ -z "$current_target" ]] || ! protect_release_path "$current_target"; then
  fail "current symlink is missing or does not point into $RELEASES_DIR"
fi

while IFS= read -r -d '' release_dir; do
  RELEASE_NAMES+=("$(basename "$release_dir")")
done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ ${#RELEASE_NAMES[@]} -eq 0 ]]; then
  log "No release directories found"
  exit 0
fi

for process_exe in "${PROC_ROOT%/}"/[0-9]*/exe; do
  resolved_exe="$(readlink -f "$process_exe" 2>/dev/null || true)"
  [[ -n "$resolved_exe" ]] || continue
  protect_release_path "$resolved_exe" || true
done

while IFS= read -r release_name; do
  [[ -n "$release_name" ]] || continue
  if ! is_protected_release "$release_name"; then
    PROTECTED_RELEASES+=("$release_name")
    break
  fi
done < <(printf '%s\n' "${RELEASE_NAMES[@]}" | sort -Vr)

declare -a REMOVAL_CANDIDATES=()
for release_name in "${RELEASE_NAMES[@]}"; do
  if ! is_protected_release "$release_name"; then
    REMOVAL_CANDIDATES+=("$release_name")
  fi
done

log "Protected releases:"
printf '%s\n' "${PROTECTED_RELEASES[@]}" | sort -V | sed 's/^/[codex-release-cleanup]   /'

if [[ ${#REMOVAL_CANDIDATES[@]} -eq 0 ]]; then
  log "No obsolete releases found"
  exit 0
fi

reclaimable_kib=0
for release_name in "${REMOVAL_CANDIDATES[@]}"; do
  release_kib="$(du -sk -- "$RELEASES_DIR/$release_name" | awk '{print $1}')"
  reclaimable_kib=$((reclaimable_kib + release_kib))
done

log "Obsolete releases:"
printf '%s\n' "${REMOVAL_CANDIDATES[@]}" | sort -V | sed 's/^/[codex-release-cleanup]   /'
log "Reclaimable size: $((reclaimable_kib / 1024)) MiB"

if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run complete; no files were removed"
  exit 0
fi

for release_name in "${REMOVAL_CANDIDATES[@]}"; do
  release_path="$RELEASES_DIR/$release_name"
  [[ "$(dirname "$release_path")" == "$RELEASES_DIR" ]] ||
    fail "refusing unsafe release path: $release_path"
  rm -rf -- "$release_path"
done

log "Removed ${#REMOVAL_CANDIDATES[@]} obsolete release(s)"
