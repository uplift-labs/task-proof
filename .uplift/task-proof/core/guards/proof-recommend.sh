#!/bin/bash
# proof-recommend.sh — task-proof guard
# Once per session, nudge the agent to consider the task-proof skill for
# tasks with 3+ acceptance criteria, multi-file refactors, or complex work.
#
# Input:  JSON UserPromptSubmit payload on stdin
# Output: WARN:<message> | empty (no nudge needed)
# Exit:   0 always

set -u

INPUT=$(cat)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/json-field.sh"

# Extract the user's message. Claude Code sends "content"; Codex sends
# "prompt" for UserPromptSubmit. Both names are host payload fields, but the
# guard only needs the user-facing text.
USER_MSG=$(json_field_long "content" "$INPUT")
[ -z "$USER_MSG" ] && USER_MSG=$(json_field_long "prompt" "$INPUT")
[ -z "$USER_MSG" ] && exit 0

# Skip short messages (confirmations: "yes", "ok", "go ahead")
WORD_COUNT=$(printf '%s' "$USER_MSG" | wc -w | tr -d ' ')
[ "${WORD_COUNT:-0}" -lt 5 ] && exit 0

# Fire once per session to avoid recommendation fatigue
SESSION_ID=$(json_field "session_id" "$INPUT")
MARKER="${TMPDIR:-/tmp}/task-proof-recommend-${SESSION_ID:-unknown}"
[ -f "$MARKER" ] && exit 0
touch "$MARKER" 2>/dev/null || true

MSG="[task-proof] Assess this task: does it have 3+ acceptance criteria, touch 3+ files, or involve a multi-step refactor? If yes, run the task-proof skill (structured spec freeze, build, evidence pack, independent verification, fix loop). If the task is simple, proceed normally."

printf 'WARN:%s' "$MSG"
exit 0
