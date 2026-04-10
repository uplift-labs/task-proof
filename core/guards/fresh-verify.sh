#!/bin/bash
# fresh-verify.sh — task-proof guard
# Spawns a fresh LLM session (no shared context) to independently verify
# staged changes before push/commit. Closes the self-certification gap:
# the agent that wrote the code physically cannot judge it cleanly.
#
# Input:  JSON tool payload on stdin (Claude Code-style PreToolUse Bash)
# Output: BLOCK:<reason> | ASK:<reason> | empty (allow)
# Exit:   0 always (fail-open)

set -u

INPUT=$(cat)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/json-field.sh"

# Extract command from tool_input
CMD=$(json_field "command" "$INPUT")
[ -z "$CMD" ] && exit 0

# Only trigger on git push or git commit
IS_PUSH=false
IS_COMMIT=false
case "$CMD" in
  *git\ push*|*git\ \ push*) IS_PUSH=true ;;
  *git\ commit*|*git\ \ commit*) IS_COMMIT=true ;;
  *) exit 0 ;;
esac

# Skip WIP commits (intentional partial work)
case "$CMD" in
  *--wip*|*WIP*|*wip:*|*"wip "*) exit 0 ;;
esac

# Resolve git repo locally — no singularity env vars assumed
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$GIT_ROOT" ] && exit 0

# Get the diff to verify
if [ "$IS_PUSH" = true ]; then
  CURRENT_BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null)
  DIFF=$(git -C "$GIT_ROOT" diff "origin/$CURRENT_BRANCH..HEAD" 2>/dev/null)
  [ -z "$DIFF" ] && DIFF=$(git -C "$GIT_ROOT" diff HEAD~1 2>/dev/null)
elif [ "$IS_COMMIT" = true ]; then
  DIFF=$(git -C "$GIT_ROOT" diff --cached 2>/dev/null)
  [ -z "$DIFF" ] && DIFF=$(git -C "$GIT_ROOT" diff 2>/dev/null)
fi

# No changes to verify — skip
[ -z "$DIFF" ] && exit 0

# Skip trivially small diffs (< 3 lines of actual change)
CHANGE_LINES=$(printf '%s' "$DIFF" | grep -c '^[+-][^+-]' 2>/dev/null || echo 0)
[ "${CHANGE_LINES:-0}" -lt 3 ] && exit 0

# Extract last user prompt from transcript for task context
TRANSCRIPT=$(json_field "transcript_path" "$INPUT")
TASK_DESCRIPTION=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TASK_DESCRIPTION=$(grep -o '"type":"human"[^}]*"content":"[^"]*"' "$TRANSCRIPT" 2>/dev/null | tail -1 | sed 's/.*"content":"//;s/"$//' | head -c 500)
fi
[ -z "$TASK_DESCRIPTION" ] && TASK_DESCRIPTION="(no task description available — review the diff on its own merits)"

# Truncate diff to fit context budget
DIFF_TRUNCATED=$(printf '%s' "$DIFF" | head -200)
if [ "$(printf '%s' "$DIFF" | wc -l)" -gt 200 ]; then
  DIFF_TRUNCATED="$DIFF_TRUNCATED
... (diff truncated, $(printf '%s' "$DIFF" | wc -l | tr -d ' ') total lines)"
fi

PROMPT="You are an independent code reviewer with no prior context. You see only (1) a task description and (2) a diff.

Your job is to surface real risks — NOT to rubber-stamp. Default to CONCERN or FAIL on ambiguity; PASS should be reserved for small, obviously-correct changes.

Flag as FAIL any of:
- Diff does not address the stated task (or task is vague and diff could drift).
- Obvious bugs: off-by-one, wrong condition, null/empty deref, wrong variable name.
- Swallowed errors or silent exception handlers without an explicit reason.
- Security: hardcoded secrets, unsanitized input concatenated into shell/SQL/HTML, unsafe file permissions.
- Deleted tests or assertions weakened without justification in the diff.
- Missing edge cases the diff itself implies (e.g. added an if without its else).

Flag as CONCERN any of:
- New public API with no test.
- Refactor touches unrelated files.
- Magic numbers, TODO comments, commented-out code shipped in the diff.
- Dependencies added without a comment on why.

Reply with EXACTLY one of these three formats, no other text, no preamble:
PASS
FAIL: <one-sentence reason, naming the specific file or line-type if possible>
CONCERN: <one-sentence note>

Task description: $TASK_DESCRIPTION

Code diff:
$DIFF_TRUNCATED"

VERDICT=$(printf '%s' "$PROMPT" | bash "$SCRIPT_DIR/../lib/llm-client.sh" 2>/dev/null)
LLM_EXIT=$?
if [ "$LLM_EXIT" -ne 0 ] || [ -z "$VERDICT" ]; then
  # Degrade gracefully — never block on backend failure
  exit 0
fi

# Strip leading/trailing whitespace and collapse to single line for matching
VERDICT_TRIMMED=$(printf '%s' "$VERDICT" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

case "$VERDICT_TRIMMED" in
  PASS*)
    exit 0
    ;;
  FAIL*)
    REASON=$(printf '%s' "$VERDICT_TRIMMED" | sed 's/^FAIL:[[:space:]]*//')
    printf 'BLOCK:[fresh-verify] independent reviewer FAILED the changes: %s' "$REASON"
    exit 0
    ;;
  CONCERN*)
    NOTE=$(printf '%s' "$VERDICT_TRIMMED" | sed 's/^CONCERN:[[:space:]]*//')
    printf 'ASK:[fresh-verify] independent reviewer raised a concern: %s' "$NOTE"
    exit 0
    ;;
  *)
    # Unparseable response — log to stderr (multiplexer drops it) but don't block
    printf '[fresh-verify] unexpected LLM response: %s\n' "$VERDICT_TRIMMED" >&2
    exit 0
    ;;
esac
