#!/bin/bash
# Installer smoke test for --with-opencode.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_REPO=$(mktemp -d)
TMP_BOTH=$(mktemp -d)
trap 'rm -rf "$TMP_REPO" "$TMP_BOTH"' EXIT

git init -q "$TMP_REPO"
mkdir -p "$TMP_REPO/.opencode/plugins"
printf 'export default { id: "other", server: async () => ({}) }\n' > "$TMP_REPO/.opencode/plugins/other.js"
printf '{"permission":{"bash":"ask"}}\n' > "$TMP_REPO/opencode.json"

fail=0
echo "[install-opencode]"

bash "$ROOT/install.sh" --target "$TMP_REPO" --with-opencode >/dev/null || {
  echo "  FAIL  install --with-opencode"
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

first_plugin=$(cat "$TMP_REPO/.opencode/plugins/task-proof.js")
first_skill=$(cat "$TMP_REPO/.opencode/skills/task-proof/SKILL.md")
bash "$ROOT/install.sh" --target "$TMP_REPO" --with-opencode >/dev/null || {
  echo "  FAIL  repeated install --with-opencode"
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

git init -q "$TMP_BOTH"
bash "$ROOT/install.sh" --target "$TMP_BOTH" --with-claude-code --with-codex --with-opencode >/dev/null || {
  echo "  FAIL  install all hosts"
  exit 1
}

for path in \
  "$TMP_BOTH/.uplift/task-proof/adapter/hooks/pre-bash.sh" \
  "$TMP_BOTH/.uplift/task-proof/adapter/hooks/user-prompt-submit.sh" \
  "$TMP_BOTH/.uplift/task-proof/adapter/hooks/codex-pre-tool-use.sh" \
  "$TMP_BOTH/.uplift/task-proof/adapter/hooks/codex-user-prompt-submit.sh" \
  "$TMP_BOTH/.opencode/plugins/task-proof.js"
do
  if [ -e "$path" ]; then
    echo "  PASS  all-host install kept ${path#$TMP_BOTH/}"
  else
    echo "  FAIL  all-host install missing ${path#$TMP_BOTH/}"
    fail=1
  fi
done

exit "$fail"
