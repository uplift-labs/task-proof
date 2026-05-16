#!/bin/bash
# Installer smoke test for OpenCode-only installs.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

git init -q "$TMP_REPO"
mkdir -p "$TMP_REPO/.opencode/plugins"
mkdir -p "$TMP_REPO/.uplift/task-proof/adapter/hooks" "$TMP_REPO/.uplift/task-proof/core/lib"
printf 'export default { id: "other", server: async () => ({}) }\n' > "$TMP_REPO/.opencode/plugins/other.js"
printf '{"permission":{"bash":"ask"}}\n' > "$TMP_REPO/opencode.json"
printf 'old hook\n' > "$TMP_REPO/.uplift/task-proof/adapter/hooks/old.sh"
printf 'old helper\n' > "$TMP_REPO/.uplift/task-proof/core/lib/old.py"

fail=0
echo "[install-opencode]"

bash "$ROOT/install.sh" --target "$TMP_REPO" >/dev/null || {
  echo "  FAIL  install"
  exit 1
}

for path in \
  "$TMP_REPO/.uplift/task-proof/core/cmd/task-proof-run.sh" \
  "$TMP_REPO/.opencode/.gitignore" \
  "$TMP_REPO/.opencode/plugins/task-proof.js" \
  "$TMP_REPO/.opencode/skills/task-proof/SKILL.md"
do
  if [ -e "$path" ]; then
    echo "  PASS  installed ${path#$TMP_REPO/}"
  else
    echo "  FAIL  missing ${path#$TMP_REPO/}"
    fail=1
  fi
done

if [ -e "$TMP_REPO/.opencode/plugins/other.js" ] && grep -Fq '"permission"' "$TMP_REPO/opencode.json"; then
  echo "  PASS  existing OpenCode files preserved"
else
  echo "  FAIL  existing OpenCode files changed"
  fail=1
fi

if grep -Fq 'node_modules/' "$TMP_REPO/.opencode/.gitignore" && grep -Fq 'package-lock.json' "$TMP_REPO/.opencode/.gitignore"; then
  echo "  PASS  OpenCode generated dependencies ignored"
else
  echo "  FAIL  OpenCode generated dependency ignores missing"
  fail=1
fi

if [ ! -e "$TMP_REPO/.uplift/task-proof/adapter" ] && [ ! -e "$TMP_REPO/.uplift/task-proof/core/lib/old.py" ]; then
  echo "  PASS  stale non-OpenCode install files removed"
else
  echo "  FAIL  stale non-OpenCode install files remained"
  fail=1
fi

first_plugin=$(cat "$TMP_REPO/.opencode/plugins/task-proof.js")
first_skill=$(cat "$TMP_REPO/.opencode/skills/task-proof/SKILL.md")
bash "$ROOT/install.sh" --target "$TMP_REPO" >/dev/null || {
  echo "  FAIL  repeated install"
  exit 1
}
second_plugin=$(cat "$TMP_REPO/.opencode/plugins/task-proof.js")
second_skill=$(cat "$TMP_REPO/.opencode/skills/task-proof/SKILL.md")

if [ "$first_plugin" = "$second_plugin" ] && [ "$first_skill" = "$second_skill" ]; then
  echo "  PASS  install is idempotent"
else
  echo "  FAIL  install changed OpenCode files on second run"
  fail=1
fi

exit "$fail"
