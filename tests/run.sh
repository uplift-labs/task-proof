#!/bin/bash
# tests/run.sh — fixture-based smoke runner for task-proof.
#
# For each fixture under tests/fixtures/<group>/:
#   - tp-*.json   (true positive) → guard MUST output BLOCK:/ASK:/WARN:
#   - tn-*.json   (true negative) → guard MUST stay silent (empty stdout)
#
# Sets up a throwaway git repo with a real staged diff so fresh-verify has
# something to verify, mocks the LLM backend with TASK_PROOF_LLM_CMD, then
# pipes each fixture through core/cmd/task-proof-run.sh <group>.
#
# Exit: 0 if all fixtures match expectations, 1 otherwise.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

git init -q "$TMP_REPO"
GIT_AUTHOR="-c user.email=t@t -c user.name=t"
# shellcheck disable=SC2086
git $GIT_AUTHOR -C "$TMP_REPO" commit --allow-empty -q -m init
# Commit a baseline so HEAD~1 exists and the git-push diff path
# (which compares HEAD to HEAD~1 when no remote is configured) returns
# a non-empty result for fresh-verify.
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\n' > "$TMP_REPO/sample.txt"
git -C "$TMP_REPO" add sample.txt
# shellcheck disable=SC2086
git $GIT_AUTHOR -C "$TMP_REPO" commit -q -m baseline
# Stage further unstaged changes so the git-commit diff path
# (git diff --cached) also returns a non-empty result.
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\n' > "$TMP_REPO/sample.txt"
git -C "$TMP_REPO" add sample.txt

# Empty transcript for fresh-verify task-description extraction
: > "$TMP_REPO/transcript.jsonl"

map_group() {
  case "$1" in
    fresh-verify)    echo "pre-commit" ;;
    proof-recommend) echo "prompt-recommend" ;;
    *) echo "" ;;
  esac
}

mock_llm() {
  case "$1" in
    fresh-verify)
      # Make the verifier deterministic — return FAIL so tp fixture
      # produces non-empty output. tn fixture skips the LLM entirely
      # (the guard exits before calling it on non-git commands).
      echo 'echo "FAIL: synthetic verdict for fixture run"'
      ;;
    *)
      echo ''
      ;;
  esac
}

run_fixture() {
  local fixture="$1" guard expected group payload mock out
  guard=$(basename "$(dirname "$fixture")")
  group=$(map_group "$guard")
  [ -z "$group" ] && { echo "  SKIP: unknown group for $guard"; return 0; }

  case "$(basename "$fixture")" in
    tp-*) expected="non-empty" ;;
    tn-*) expected="empty" ;;
    *)    echo "  SKIP: unrecognized fixture name $(basename "$fixture")"; return 0 ;;
  esac

  payload=$(sed "s|{{TMPDIR}}|$TMP_REPO|g" "$fixture")
  mock=$(mock_llm "$guard")
  # The session marker for proof-recommend lives in TMPDIR; clear it per
  # fixture so each run is independent.
  rm -f "${TMPDIR:-/tmp}"/task-proof-recommend-test-pr-* 2>/dev/null || true

  if [ -n "$mock" ]; then
    out=$(cd "$TMP_REPO" && printf '%s' "$payload" | TASK_PROOF_LLM_CMD="$mock" bash "$ROOT/core/cmd/task-proof-run.sh" "$group" 2>/dev/null)
  else
    out=$(cd "$TMP_REPO" && printf '%s' "$payload" | bash "$ROOT/core/cmd/task-proof-run.sh" "$group" 2>/dev/null)
  fi

  if [ "$expected" = "non-empty" ] && [ -n "$out" ]; then
    echo "  PASS  $(basename "$fixture")  →  ${out:0:60}..."
    return 0
  fi
  if [ "$expected" = "empty" ] && [ -z "$out" ]; then
    echo "  PASS  $(basename "$fixture")  →  (silent)"
    return 0
  fi
  echo "  FAIL  $(basename "$fixture")  expected=$expected got=[$out]"
  return 1
}

fail=0
for guard_dir in "$ROOT/tests/fixtures/"*/; do
  guard=$(basename "$guard_dir")
  echo "[$guard]"
  for fixture in "$guard_dir"*.json; do
    [ -e "$fixture" ] || continue
    run_fixture "$fixture" || fail=1
  done
done

if [ -f "$ROOT/tests/test-adapter-codex.sh" ]; then
  bash "$ROOT/tests/test-adapter-codex.sh" || fail=1
fi

if [ -f "$ROOT/tests/test-llm-client-codex.sh" ]; then
  bash "$ROOT/tests/test-llm-client-codex.sh" || fail=1
fi

if [ -f "$ROOT/tests/test-install-codex.sh" ]; then
  bash "$ROOT/tests/test-install-codex.sh" || fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "some fixtures FAILED"
fi
exit "$fail"
