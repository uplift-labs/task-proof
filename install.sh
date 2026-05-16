#!/bin/bash
# install.sh - install task-proof into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--prefix <dir>]
#
# Installs the core multiplexer and guards under .uplift/task-proof, plus the
# project-local OpenCode plugin and skill under .opencode/.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
PREFIX=".uplift"

while [ $# -gt 0 ]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --prefix)           PREFIX="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
# .git is a directory in normal repos, a file in worktrees
[ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

INSTALL_ROOT="$TARGET/$PREFIX/task-proof"
mkdir -p "$INSTALL_ROOT/core/lib" "$INSTALL_ROOT/core/cmd" "$INSTALL_ROOT/core/guards"
rm -rf "$INSTALL_ROOT/adapter"
rm -f "$INSTALL_ROOT/core/lib/"*.py 2>/dev/null || true

# sync_files <src_dir> <dest_dir> <glob> - mirror files matching glob from src into dest.
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

# copy_files <src_dir> <dest_dir> <glob> - additive copy into a target directory.
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
sync_files "$SCRIPT_DIR/core/lib"    "$INSTALL_ROOT/core/lib" "*.sh"
sync_files "$SCRIPT_DIR/core/cmd"    "$INSTALL_ROOT/core/cmd" "*.sh"
sync_files "$SCRIPT_DIR/core/guards" "$INSTALL_ROOT/core/guards" "*.sh"
chmod +x "$INSTALL_ROOT/core/cmd/"*.sh "$INSTALL_ROOT/core/guards/"*.sh

OPENCODE_DIR="$TARGET/.opencode"
OPENCODE_PLUGIN_DIR="$OPENCODE_DIR/plugins"
mkdir -p "$OPENCODE_PLUGIN_DIR"
OPENCODE_GITIGNORE="$OPENCODE_DIR/.gitignore"
if [ ! -e "$OPENCODE_GITIGNORE" ]; then
  printf 'node_modules/\npackage.json\npackage-lock.json\nbun.lock\n' > "$OPENCODE_GITIGNORE"
fi
printf '[install] copying OpenCode plugin to %s\n' "$OPENCODE_PLUGIN_DIR"
copy_files "$SCRIPT_DIR/adapters/opencode/plugins" "$OPENCODE_PLUGIN_DIR" "*.js"

# Install the task-proof skill into OpenCode's repo-scoped skill location.
SKILL_SRC="$SCRIPT_DIR/adapters/opencode/skills/task-proof"
SKILL_DEST="$OPENCODE_DIR/skills/task-proof"
if [ -d "$SKILL_SRC" ]; then
  mkdir -p "$SKILL_DEST"
  cp "$SKILL_SRC"/*.md "$SKILL_DEST/" 2>/dev/null || {
    printf '[install] WARNING: OpenCode skill copy from %s failed\n' "$SKILL_SRC" >&2
  }
  printf '[install] OpenCode skill installed at %s\n' "$SKILL_DEST"
fi

printf '[install] done.\n'
printf '  core installed at: %s\n' "$INSTALL_ROOT/core"
printf '  opencode plugin: %s\n' "$TARGET/.opencode/plugins"
printf '\n  Commit %s/ and any host config/skill directories created\n' "$INSTALL_ROOT"
printf '  (.opencode/) so that the proof loop is available in worktrees.\n'
