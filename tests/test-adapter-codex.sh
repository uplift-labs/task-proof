#!/bin/bash
# Smoke tests for the Codex hook adapter.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

git init -q "$TMP_REPO"
GIT_AUTHOR="-c user.email=t@t -c user.name=t"
# shellcheck disable=SC2086
git $GIT_AUTHOR -C "$TMP_REPO" commit --allow-empty -q -m init
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\n' > "$TMP_REPO/sample.txt"
git -C "$TMP_REPO" add sample.txt
# shellcheck disable=SC2086
git $GIT_AUTHOR -C "$TMP_REPO" commit -q -m baseline
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\n' > "$TMP_REPO/sample.txt"
git -C "$TMP_REPO" add sample.txt
: > "$TMP_REPO/transcript.jsonl"

fail=0

run_pre_tool() {
  local command="$1" mock="$2"
  local payload
  payload=$(cat <<JSON
{
  "session_id": "codex-adapter-test",
  "transcript_path": "$TMP_REPO/transcript.jsonl",
  "cwd": "$TMP_REPO",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {"command": "$command"}
}
JSON
)
  (cd "$TMP_REPO" && printf '%s' "$payload" | TASK_PROOF_ROOT="$ROOT" TASK_PROOF_LLM_CMD="$mock" bash "$ROOT/adapters/codex/hooks/codex-pre-tool-use.sh")
}

expect_contains() {
  local name="$1" out="$2" needle="$3"
  if printf '%s' "$out" | grep -Fq "$needle"; then
    echo "  PASS  $name"
  else
    echo "  FAIL  $name  expected to contain [$needle], got [$out]"
    fail=1
  fi
}

expect_empty() {
  local name="$1" out="$2"
  if [ -z "$out" ]; then
    echo "  PASS  $name"
  else
    echo "  FAIL  $name  expected empty, got [$out]"
    fail=1
  fi
}

echo "[codex-adapter]"

out=$(run_pre_tool "git commit -m test" 'echo "FAIL: synthetic codex adapter failure"')
expect_contains "pre-tool FAIL denies" "$out" '"permissionDecision":"deny"'
expect_contains "pre-tool FAIL reason" "$out" 'synthetic codex adapter failure'

out=$(run_pre_tool "git commit -m test" 'echo "CONCERN: synthetic codex adapter concern"')
expect_contains "pre-tool CONCERN default denies" "$out" '"permissionDecision":"deny"'

payload=$(cat <<JSON
{
  "session_id": "codex-adapter-test",
  "transcript_path": "$TMP_REPO/transcript.jsonl",
  "cwd": "$TMP_REPO",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {"command": "git commit -m test"}
}
JSON
)
out=$(cd "$TMP_REPO" && printf '%s' "$payload" | TASK_PROOF_CODEX_ASK_BEHAVIOR=warn TASK_PROOF_ROOT="$ROOT" TASK_PROOF_LLM_CMD='echo "CONCERN: warn-only concern"' bash "$ROOT/adapters/codex/hooks/codex-pre-tool-use.sh")
expect_contains "pre-tool CONCERN warn mode" "$out" '"systemMessage":"[fresh-verify] independent reviewer raised a concern: warn-only concern"'

out=$(run_pre_tool "npm test" 'echo "FAIL: should not be called"')
expect_empty "pre-tool non-git silent" "$out"

rm -f "${TMPDIR:-/tmp}"/task-proof-recommend-codex-prompt-test 2>/dev/null || true
prompt_payload='{"session_id":"codex-prompt-test","hook_event_name":"UserPromptSubmit","prompt":"Refactor the authentication system across services and update tests and documentation"}'
out=$(printf '%s' "$prompt_payload" | TASK_PROOF_ROOT="$ROOT" bash "$ROOT/adapters/codex/hooks/codex-user-prompt-submit.sh")
expect_contains "user-prompt prompt field warns" "$out" '"hookEventName":"UserPromptSubmit"'
expect_contains "user-prompt prompt field context" "$out" '[task-proof] Assess this task'

exit "$fail"
