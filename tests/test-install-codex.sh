#!/bin/bash
# Installer smoke test for --with-codex.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_REPO=$(mktemp -d)
TMP_BOTH=$(mktemp -d)
TMP_MIGRATE=$(mktemp -d)
trap 'rm -rf "$TMP_REPO" "$TMP_BOTH" "$TMP_MIGRATE"' EXIT

git init -q "$TMP_REPO"

fail=0
echo "[install-codex]"

bash "$ROOT/install.sh" --target "$TMP_REPO" --with-codex >/dev/null || {
  echo "  FAIL  install --with-codex"
  exit 1
}

for path in \
  "$TMP_REPO/.uplift/task-proof/core/cmd/task-proof-run.sh" \
  "$TMP_REPO/.uplift/task-proof/adapter/hooks/codex-pre-tool-use.sh" \
  "$TMP_REPO/.uplift/task-proof/adapter/hooks/codex-user-prompt-submit.sh" \
  "$TMP_REPO/.codex/config.toml" \
  "$TMP_REPO/.codex/hooks.json" \
  "$TMP_REPO/.agents/skills/task-proof/SKILL.md"
do
  if [ -e "$path" ]; then
    echo "  PASS  installed ${path#$TMP_REPO/}"
  else
    echo "  FAIL  missing ${path#$TMP_REPO/}"
    fail=1
  fi
done

if grep -Fq 'codex_hooks = true' "$TMP_REPO/.codex/config.toml"; then
  echo "  PASS  codex hooks feature enabled"
else
  echo "  FAIL  codex hooks feature missing"
  fail=1
fi

first_hooks=$(cat "$TMP_REPO/.codex/hooks.json")
first_config=$(cat "$TMP_REPO/.codex/config.toml")
bash "$ROOT/install.sh" --target "$TMP_REPO" --with-codex >/dev/null || {
  echo "  FAIL  repeated install --with-codex"
  exit 1
}
second_hooks=$(cat "$TMP_REPO/.codex/hooks.json")
second_config=$(cat "$TMP_REPO/.codex/config.toml")

if [ "$first_hooks" = "$second_hooks" ] && [ "$first_config" = "$second_config" ]; then
  echo "  PASS  install is idempotent"
else
  echo "  FAIL  install changed config on second run"
  fail=1
fi

git init -q "$TMP_BOTH"
bash "$ROOT/install.sh" --target "$TMP_BOTH" --with-claude-code --with-codex >/dev/null || {
  echo "  FAIL  install both hosts"
  exit 1
}

for hook in pre-bash.sh user-prompt-submit.sh codex-pre-tool-use.sh codex-user-prompt-submit.sh; do
  if [ -e "$TMP_BOTH/.uplift/task-proof/adapter/hooks/$hook" ]; then
    echo "  PASS  both-host install kept $hook"
  else
    echo "  FAIL  both-host install missing $hook"
    fail=1
  fi
done

git init -q "$TMP_MIGRATE"
mkdir -p "$TMP_MIGRATE/.claude"
cat > "$TMP_MIGRATE/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.task-proof/adapter/hooks/pre-bash.sh\"",
            "timeout": 135000
          },
          {
            "type": "command",
            "command": "echo unrelated"
          }
        ]
      }
    ]
  }
}
JSON
bash "$ROOT/install.sh" --target "$TMP_MIGRATE" --with-claude-code >/dev/null || {
  echo "  FAIL  legacy hook migration install"
  exit 1
}
if grep -Fq '.task-proof/adapter/hooks' "$TMP_MIGRATE/.claude/settings.json"; then
  echo "  FAIL  legacy .task-proof hook remained after migration"
  fail=1
else
  echo "  PASS  legacy .task-proof hook removed"
fi
if grep -Fq 'echo unrelated' "$TMP_MIGRATE/.claude/settings.json"; then
  echo "  PASS  unrelated hook preserved"
else
  echo "  FAIL  unrelated hook was removed"
  fail=1
fi

exit "$fail"
