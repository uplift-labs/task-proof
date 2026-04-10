#!/bin/bash
# remote-install.sh — fetch task-proof and install into the current repo.
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh) [--with-claude-code]
#
# Clones the repo into a temp dir, runs install.sh, cleans up.
# Set TASK_PROOF_VERSION to pin a specific tag (default: v0.1.0).

set -u

REPO_URL="https://github.com/uplift-labs/task-proof.git"
VERSION="${TASK_PROOF_VERSION:-v0.1.0}"
TARGET="$(pwd)"
PASSTHROUGH_ARGS=("--target" "$TARGET")

for arg in "$@"; do
  PASSTHROUGH_ARGS+=("$arg")
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf '[remote-install] cloning task-proof@%s...\n' "$VERSION"
git clone --depth 1 --branch "$VERSION" "$REPO_URL" "$TMPDIR/task-proof" 2>/dev/null || {
  printf 'failed to clone %s\n' "$REPO_URL" >&2
  exit 1
}

bash "$TMPDIR/task-proof/install.sh" "${PASSTHROUGH_ARGS[@]}"
