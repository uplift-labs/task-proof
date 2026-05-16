#!/bin/bash
# llm-client.sh - backend abstraction for fresh-verify and other guards.
#
# Usage:
#   bash llm-client.sh "<prompt text>"
#   printf '%s' "<prompt>" | bash llm-client.sh
#
# Reads the prompt from $1 if given, otherwise from stdin.
# Writes the model's raw text reply to stdout.
# Exit codes: 0 on success, 1 if no backend available, >1 on backend error.
#
# Backend selection (first match wins):
#   1. $TASK_PROOF_LLM_CMD    - user override. The value is eval'd with the
#                                prompt piped to its stdin. Use this to plug
#                                in any LLM (ollama, vLLM, openai CLI, etc.)
#                                or to mock the backend in tests.
#   2. opencode run in $PATH - OpenCode CLI, plugin-pure nested verifier
#
# Optional config:
#   TASK_PROOF_LLM_BACKEND    - force "opencode"
#   TASK_PROOF_OPENCODE_MODEL - optional model override for opencode run

set -u

OPENCODE_MODEL="${TASK_PROOF_OPENCODE_MODEL:-}"

if [ $# -ge 1 ]; then
  prompt="$1"
else
  prompt=$(cat)
fi

[ -z "$prompt" ] && { printf 'llm-client: empty prompt\n' >&2; exit 1; }

# 1. User override - read prompt from stdin
if [ -n "${TASK_PROOF_LLM_CMD:-}" ]; then
  printf '%s' "$prompt" | eval "$TASK_PROOF_LLM_CMD"
  exit $?
fi

run_opencode_backend() {
  if ! command -v opencode >/dev/null 2>&1; then
    printf 'llm-client: opencode backend requested but opencode CLI is not available\n' >&2
    return 1
  fi

  local prompt_file
  prompt_file=$(mktemp) || return 2
  printf '%s' "$prompt" > "$prompt_file" || { rm -f "$prompt_file"; return 2; }

  # shellcheck disable=SC2206
  local args=(run --pure --file "$prompt_file")
  if [ -n "$OPENCODE_MODEL" ]; then
    args+=(--model "$OPENCODE_MODEL")
  fi

  TASK_PROOF_DISABLED=1 \
    opencode "${args[@]}" "Read the attached prompt file and answer exactly as requested." 2>/dev/null
  local status=$?
  rm -f "$prompt_file"
  return "$status"
}

case "${TASK_PROOF_LLM_BACKEND:-}" in
  opencode)
    run_opencode_backend
    exit $?
    ;;
  "")
    ;;
  *)
    printf 'llm-client: unknown TASK_PROOF_LLM_BACKEND=%s\n' "$TASK_PROOF_LLM_BACKEND" >&2
    exit 1
    ;;
esac

# 2. opencode run in PATH.
if command -v opencode >/dev/null 2>&1; then
  run_opencode_backend
  exit $?
fi

printf 'llm-client: no LLM backend available - set TASK_PROOF_LLM_CMD or install opencode CLI\n' >&2
exit 1
