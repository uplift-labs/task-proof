#!/bin/bash
# user-prompt-submit.sh — Claude Code UserPromptSubmit adapter for task-proof.
# Translates task-proof-run.sh prompt-recommend group output to Claude Code JSON.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/task-proof-run.sh" prompt-recommend 2>/dev/null) || true

_tp_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

case "$RESULT" in
  WARN:*)
    ctx=$(_tp_escape "${RESULT#WARN:}")
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' "$ctx"
    ;;
esac
exit 0
