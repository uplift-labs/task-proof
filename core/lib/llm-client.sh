#!/bin/bash
# llm-client.sh — backend abstraction for fresh-verify and other guards.
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
#   1. $TASK_PROOF_LLM_CMD     — user override. The value is eval'd with the
#                                 prompt piped to its stdin. Use this to plug
#                                 in any LLM (ollama, vLLM, openai CLI, etc.)
#                                 or to mock the backend in tests.
#   2. claude -p in $PATH     — Claude Code CLI (Max subscription, no API key)
#   3. ANTHROPIC_API_KEY      — direct call to api.anthropic.com via curl
#
# Optional config:
#   TASK_PROOF_MODEL          — default "claude-haiku-4-5" (fast, cheap)
#   TASK_PROOF_MAX_TOKENS     — default 1024

set -u

MODEL="${TASK_PROOF_MODEL:-claude-haiku-4-5}"
MAX_TOKENS="${TASK_PROOF_MAX_TOKENS:-1024}"

if [ $# -ge 1 ]; then
  prompt="$1"
else
  prompt=$(cat)
fi

[ -z "$prompt" ] && { printf 'llm-client: empty prompt\n' >&2; exit 1; }

# 1. User override — read prompt from stdin
if [ -n "${TASK_PROOF_LLM_CMD:-}" ]; then
  printf '%s' "$prompt" | eval "$TASK_PROOF_LLM_CMD"
  exit $?
fi

# 2. claude -p in PATH (Claude Code Max subscription)
if command -v claude >/dev/null 2>&1; then
  printf '%s' "$prompt" | claude -p --model "$MODEL" 2>/dev/null
  exit $?
fi

# 3. Anthropic API via curl (requires ANTHROPIC_API_KEY and jq)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf 'llm-client: ANTHROPIC_API_KEY backend requires curl and jq\n' >&2
    exit 1
  fi
  payload=$(jq -n \
    --arg model "$MODEL" \
    --argjson max "$MAX_TOKENS" \
    --arg p "$prompt" \
    '{model:$model, max_tokens:$max, messages:[{role:"user",content:$p}]}')
  response=$(curl -sS https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload") || {
      printf 'llm-client: curl failed\n' >&2
      exit 2
    }
  printf '%s' "$response" | jq -r '.content[0].text // empty'
  exit 0
fi

printf 'llm-client: no LLM backend available — set TASK_PROOF_LLM_CMD, install claude CLI, or export ANTHROPIC_API_KEY\n' >&2
exit 1
