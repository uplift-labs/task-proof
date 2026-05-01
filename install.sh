#!/bin/bash
# install.sh — install task-proof into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--prefix <dir>] [--with-claude-code] [--with-codex]
#
# By default installs only the core multiplexer and guards. With --with-claude-code,
# also installs the Claude Code adapter hooks, the task-proof skill, and merges
# hook config into .claude/settings.json. With --with-codex, installs Codex
# hooks, a repo-scoped Codex skill, and project .codex hook config.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
PREFIX=".uplift"
WITH_CC=0
WITH_CODEX=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --prefix)           PREFIX="$2"; shift 2 ;;
    --with-claude-code) WITH_CC=1; shift ;;
    --with-codex)       WITH_CODEX=1; shift ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
# .git is a directory in normal repos, a file in worktrees
[ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

# --- Migration from legacy path ---
migrate_old_path() {
  local old="$1" new="$2"
  [ -d "$old" ] || return 0
  [ -d "$new" ] && { printf '[migrate] both %s and %s exist — manual merge needed\n' "$old" "$new" >&2; return 1; }
  mkdir -p "$(dirname "$new")"
  mv "$old" "$new"
  printf '[migrate] moved %s → %s\n' "$old" "$new"
}

INSTALL_ROOT="$TARGET/$PREFIX/task-proof"
migrate_old_path "$TARGET/.task-proof" "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT/core/lib" "$INSTALL_ROOT/core/cmd" "$INSTALL_ROOT/core/guards"

# sync_files <src_dir> <dest_dir> <glob> — mirror files matching glob from src into dest.
sync_files() {
  local src="$1" dest="$2" glob="$3"
  # shellcheck disable=SC2206
  local files=( "$src"/$glob )
  if [ ! -e "${files[0]}" ]; then
    printf 'install: no %s files in %s\n' "$glob" "$src" >&2
    exit 1
  fi
  rm -f "$dest"/$glob
  cp "${files[@]}" "$dest/" || {
    printf 'install: copy failed %s -> %s\n' "$src" "$dest" >&2
    exit 1
  }
}

# copy_files <src_dir> <dest_dir> <glob> — additive copy, used when multiple
# host adapters share the installed adapter/hooks directory.
copy_files() {
  local src="$1" dest="$2" glob="$3"
  # shellcheck disable=SC2206
  local files=( "$src"/$glob )
  if [ ! -e "${files[0]}" ]; then
    printf 'install: no %s files in %s\n' "$glob" "$src" >&2
    exit 1
  fi
  cp "${files[@]}" "$dest/" || {
    printf 'install: copy failed %s -> %s\n' "$src" "$dest" >&2
    exit 1
  }
}

printf '[install] copying core to %s\n' "$INSTALL_ROOT/core"
# core/lib has a mix of .sh and .py — copy both
sync_files "$SCRIPT_DIR/core/lib"    "$INSTALL_ROOT/core/lib" "*.sh"
sync_files "$SCRIPT_DIR/core/lib"    "$INSTALL_ROOT/core/lib" "*.py"
sync_files "$SCRIPT_DIR/core/cmd"    "$INSTALL_ROOT/core/cmd" "*.sh"
sync_files "$SCRIPT_DIR/core/guards" "$INSTALL_ROOT/core/guards" "*.sh"
chmod +x "$INSTALL_ROOT/core/cmd/"*.sh "$INSTALL_ROOT/core/guards/"*.sh

if [ "$WITH_CC" -eq 1 ]; then
  ADAPTER_DIR="$INSTALL_ROOT/adapter"
  mkdir -p "$ADAPTER_DIR/hooks"
  printf '[install] copying Claude Code adapter to %s\n' "$ADAPTER_DIR"
  copy_files "$SCRIPT_DIR/adapters/claude-code/hooks" "$ADAPTER_DIR/hooks" "*.sh"
  chmod +x "$ADAPTER_DIR/hooks/"*.sh

  # Install the task-proof skill into .claude/skills/
  SKILL_SRC="$SCRIPT_DIR/adapters/claude-code/skills/task-proof"
  SKILL_DEST="$TARGET/.claude/skills/task-proof"
  if [ -d "$SKILL_SRC" ]; then
    mkdir -p "$SKILL_DEST"
    cp "$SKILL_SRC"/*.md "$SKILL_DEST/" 2>/dev/null || {
      printf '[install] WARNING: skill copy from %s failed\n' "$SKILL_SRC" >&2
    }
    printf '[install] skill installed at %s\n' "$SKILL_DEST"
  fi

  # Patch settings-hooks.json template for the actual PREFIX before merging.
  _SRC_SNIPPET="$SCRIPT_DIR/adapters/claude-code/settings-hooks.json"
  PATCHED_SNIPPET=$(mktemp)
  sed \
    -e "s|/\\.task-proof/adapter/hooks/|/$PREFIX/task-proof/adapter/hooks/|g" \
    -e "s|/\\.uplift/task-proof/adapter/hooks/|/$PREFIX/task-proof/adapter/hooks/|g" \
    "$_SRC_SNIPPET" > "$PATCHED_SNIPPET"

  SETTINGS="$TARGET/.claude/settings.json"
  mkdir -p "$TARGET/.claude"

  MERGER="$SCRIPT_DIR/core/lib/json-merge.py"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[install] ERROR: python3 required to merge hooks into settings.json.\n' >&2
    exit 1
  fi
  printf '[install] merging hooks into %s\n' "$SETTINGS"
  python3 "$MERGER" "$SETTINGS" "$PATCHED_SNIPPET"
  rm -f "$PATCHED_SNIPPET"
fi

if [ "$WITH_CODEX" -eq 1 ]; then
  ADAPTER_DIR="$INSTALL_ROOT/adapter"
  mkdir -p "$ADAPTER_DIR/hooks"
  printf '[install] copying Codex adapter to %s\n' "$ADAPTER_DIR"
  copy_files "$SCRIPT_DIR/adapters/codex/hooks" "$ADAPTER_DIR/hooks" "*.sh"
  chmod +x "$ADAPTER_DIR/hooks/"*.sh

  # Install the task-proof skill into Codex's repo-scoped skill location.
  SKILL_SRC="$SCRIPT_DIR/adapters/codex/skills/task-proof"
  SKILL_DEST="$TARGET/.agents/skills/task-proof"
  if [ -d "$SKILL_SRC" ]; then
    mkdir -p "$SKILL_DEST"
    cp "$SKILL_SRC"/*.md "$SKILL_DEST/" 2>/dev/null || {
      printf '[install] WARNING: Codex skill copy from %s failed\n' "$SKILL_SRC" >&2
    }
    printf '[install] Codex skill installed at %s\n' "$SKILL_DEST"
  fi

  _SRC_SNIPPET="$SCRIPT_DIR/adapters/codex/hooks.json"
  PATCHED_SNIPPET=$(mktemp)
  sed "s|/\\.uplift/task-proof/adapter/hooks/|/$PREFIX/task-proof/adapter/hooks/|g" "$_SRC_SNIPPET" > "$PATCHED_SNIPPET"

  CODEX_DIR="$TARGET/.codex"
  CODEX_HOOKS="$CODEX_DIR/hooks.json"
  CODEX_CONFIG="$CODEX_DIR/config.toml"
  mkdir -p "$CODEX_DIR"

  MERGER="$SCRIPT_DIR/core/lib/json-merge.py"
  CODEX_CONFIG_PATCHER="$SCRIPT_DIR/core/lib/codex-config.py"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[install] ERROR: python3 required to merge Codex config.\n' >&2
    exit 1
  fi
  printf '[install] merging Codex hooks into %s\n' "$CODEX_HOOKS"
  python3 "$MERGER" "$CODEX_HOOKS" "$PATCHED_SNIPPET"
  rm -f "$PATCHED_SNIPPET"

  printf '[install] enabling Codex hooks in %s\n' "$CODEX_CONFIG"
  python3 "$CODEX_CONFIG_PATCHER" "$CODEX_CONFIG" --enable-hooks
fi

printf '[install] done.\n'
printf '  core installed at: %s\n' "$INSTALL_ROOT/core"
[ "$WITH_CC" -eq 1 ] && printf '  claude-code adapter: %s\n' "$INSTALL_ROOT/adapter"
[ "$WITH_CODEX" -eq 1 ] && printf '  codex adapter: %s\n' "$INSTALL_ROOT/adapter"
printf '\n  Commit %s/ and any host config/skill directories created\n' "$INSTALL_ROOT"
printf '  (.claude/, .codex/, .agents/) so that the proof loop is available in worktrees.\n'
