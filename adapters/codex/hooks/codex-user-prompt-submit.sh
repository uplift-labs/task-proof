#!/bin/bash
# codex-user-prompt-submit.sh — Codex UserPromptSubmit adapter for task-proof.
# Translates task-proof-run.sh prompt-recommend output to Codex hook JSON.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${TASK_PROOF_ROOT:-}" ]; then
  ROOT="$TASK_PROOF_ROOT"
elif [ -f "$HOOK_DIR/../../core/cmd/task-proof-run.sh" ]; then
  ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
else
  ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"
fi

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/task-proof-run.sh" prompt-recommend 2>/dev/null) || true

_tp_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=$(printf '%s' "$s" | LC_ALL=C tr '\000-\037' ' ')
  printf '%s' "$s"
}

case "$RESULT" in
  WARN:*)
    ctx=$(_tp_escape "${RESULT#WARN:}")
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' "$ctx"
    ;;
  BLOCK:*)
    reason=$(_tp_escape "${RESULT#BLOCK:}")
    printf '{"decision":"block","reason":"%s"}' "$reason"
    ;;
  ASK:*)
    reason=$(_tp_escape "${RESULT#ASK:}")
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' "$reason"
    ;;
esac
exit 0
