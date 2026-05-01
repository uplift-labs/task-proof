#!/bin/bash
# codex-pre-tool-use.sh — Codex PreToolUse adapter for task-proof.
# Translates task-proof-run.sh output tags to Codex hook JSON.
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
RESULT=$(printf '%s' "$INPUT" | \
  TASK_PROOF_LLM_BACKEND="${TASK_PROOF_LLM_BACKEND:-codex}" \
  bash "$ROOT/core/cmd/task-proof-run.sh" pre-commit 2>/dev/null) || true

_tp_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=$(printf '%s' "$s" | LC_ALL=C tr '\000-\037' ' ')
  printf '%s' "$s"
}

_tp_deny() {
  local reason
  reason=$(_tp_escape "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
}

case "$RESULT" in
  BLOCK:*)
    _tp_deny "${RESULT#BLOCK:}"
    ;;
  ASK:*)
    reason="${RESULT#ASK:}"
    case "${TASK_PROOF_CODEX_ASK_BEHAVIOR:-block}" in
      warn)
        reason=$(_tp_escape "$reason")
        printf '{"systemMessage":"%s"}' "$reason"
        ;;
      *)
        _tp_deny "$reason"
        ;;
    esac
    ;;
  WARN:*)
    ctx=$(_tp_escape "${RESULT#WARN:}")
    printf '{"systemMessage":"%s"}' "$ctx"
    ;;
esac
exit 0
