#!/bin/bash
# pre-bash.sh — Claude Code PreToolUse Bash adapter for task-proof.
# Translates task-proof-run.sh output tags to Claude Code JSON.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

INPUT=$(cat)
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/task-proof-run.sh" pre-commit 2>/dev/null) || true

# JSON-safe escape — handles backslash, double-quote, and every C0 control
# character (0x00-0x1F). RFC 8259 forbids raw control chars inside string
# literals, so we collapse them to spaces; otherwise an LLM verdict that
# happens to contain a tab/backspace/etc. would emit malformed JSON to the
# host and the hook payload would be silently dropped.
_tp_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=$(printf '%s' "$s" | LC_ALL=C tr '\000-\037' ' ')
  printf '%s' "$s"
}

case "$RESULT" in
  BLOCK:*)
    reason=$(_tp_escape "${RESULT#BLOCK:}")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
    ;;
  ASK:*)
    reason=$(_tp_escape "${RESULT#ASK:}")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s","additionalContext":"%s"}}' "$reason" "$reason"
    ;;
  WARN:*)
    ctx=$(_tp_escape "${RESULT#WARN:}")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' "$ctx"
    ;;
esac
exit 0
