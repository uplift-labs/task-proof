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
#   2. codex exec in $PATH    — Codex CLI, preferred inside Codex sessions
#   3. claude -p in $PATH     — Claude Code CLI (Max subscription, no API key)
#   4. ANTHROPIC_API_KEY      — direct call to api.anthropic.com via curl
#
# Optional config:
#   TASK_PROOF_MODEL          — default "claude-haiku-4-5" (fast, cheap)
#   TASK_PROOF_LLM_BACKEND    — force "codex", "claude", or "anthropic"
#   TASK_PROOF_CODEX_MODEL    — optional model override for codex exec
#   TASK_PROOF_MAX_TOKENS     — default 1024

set -u

MODEL="${TASK_PROOF_MODEL:-claude-haiku-4-5}"
CODEX_MODEL="${TASK_PROOF_CODEX_MODEL:-}"
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

run_codex_backend() {
  if ! command -v codex >/dev/null 2>&1; then
    printf 'llm-client: codex backend requested but codex CLI is not available\n' >&2
    return 1
  fi

  # shellcheck disable=SC2206
  local args=(exec --ephemeral --skip-git-repo-check --sandbox read-only --ask-for-approval never -c features.codex_hooks=false)
  if [ -n "$CODEX_MODEL" ]; then
    args+=(--model "$CODEX_MODEL")
  fi

  printf '%s' "$prompt" | \
    SINGULARITY_NESTED=1 TASK_PROOF_DISABLED=1 REINFORCE_DISABLED=1 \
    codex "${args[@]}" - 2>/dev/null
}

run_claude_backend() {
  if ! command -v claude >/dev/null 2>&1; then
    printf 'llm-client: claude backend requested but claude CLI is not available\n' >&2
    return 1
  fi

  printf '%s' "$prompt" | \
    SINGULARITY_NESTED=1 TASK_PROOF_DISABLED=1 REINFORCE_DISABLED=1 \
    claude -p --model "$MODEL" 2>/dev/null
}

FORCE_ANTHROPIC=0
case "${TASK_PROOF_LLM_BACKEND:-}" in
  codex)
    run_codex_backend
    exit $?
    ;;
  claude)
    run_claude_backend
    exit $?
    ;;
  anthropic)
    FORCE_ANTHROPIC=1
    ;;
  "")
    ;;
  *)
    printf 'llm-client: unknown TASK_PROOF_LLM_BACKEND=%s\n' "$TASK_PROOF_LLM_BACKEND" >&2
    exit 1
    ;;
esac

# 2. codex exec in PATH when running inside Codex.
if [ "$FORCE_ANTHROPIC" -ne 1 ] && [ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}${CODEX_SANDBOX_NETWORK_DISABLED:-}" ] && command -v codex >/dev/null 2>&1; then
  run_codex_backend
  exit $?
fi

# 3. claude -p in PATH (Claude Code Max subscription)
# Env vars prevent the subprocess from re-entering the same hooks and
# causing a fan-out process explosion when this runs inside an active
# Claude Code session. SINGULARITY_NESTED is read by Singularity's
# guard-multiplexer; TASK_PROOF_DISABLED and REINFORCE_DISABLED disable
# those pipelines in the nested session.
if [ "$FORCE_ANTHROPIC" -ne 1 ] && command -v claude >/dev/null 2>&1; then
  run_claude_backend
  exit $?
fi

# 4. codex exec in PATH outside Codex, after claude for compatibility.
if [ "$FORCE_ANTHROPIC" -ne 1 ] && command -v codex >/dev/null 2>&1; then
  run_codex_backend
  exit $?
fi

# 5. Anthropic API via curl (requires ANTHROPIC_API_KEY and jq)
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
  # -f makes curl exit non-zero on HTTP >= 400, surfacing API errors
  # instead of silently swallowing them. -sS keeps it quiet on success
  # while still printing error messages to stderr.
  response=$(curl -sSf https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload") || {
      printf 'llm-client: anthropic API call failed (curl exit %d)\n' "$?" >&2
      exit 2
    }
  # Check for an explicit error envelope even on 2xx (defensive)
  if printf '%s' "$response" | jq -e '.error' >/dev/null 2>&1; then
    err=$(printf '%s' "$response" | jq -r '.error.message // "unknown error"')
    printf 'llm-client: anthropic API returned error: %s\n' "$err" >&2
    exit 2
  fi
  text=$(printf '%s' "$response" | jq -r '.content[0].text // empty')
  if [ -z "$text" ]; then
    printf 'llm-client: anthropic API returned empty content\n' >&2
    exit 2
  fi
  printf '%s' "$text"
  exit 0
fi

printf 'llm-client: no LLM backend available — set TASK_PROOF_LLM_CMD, install codex/claude CLI, or export ANTHROPIC_API_KEY\n' >&2
exit 1
