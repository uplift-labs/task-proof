#!/bin/bash
# Smoke test for llm-client.sh Codex backend selection.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/codex" <<'SH'
#!/bin/bash
printf '%s\n' "$*" > "$TASK_PROOF_FAKE_CODEX_ARGS"
prompt=$(cat)
printf 'codex saw: %s' "$prompt"
SH
chmod +x "$TMP_DIR/bin/codex"

fail=0
echo "[llm-client-codex]"

out=$(printf 'hello codex' | PATH="$TMP_DIR/bin:$PATH" TASK_PROOF_FAKE_CODEX_ARGS="$TMP_DIR/args" TASK_PROOF_LLM_BACKEND=codex bash "$ROOT/core/lib/llm-client.sh")
if [ "$out" = "codex saw: hello codex" ]; then
  echo "  PASS  codex backend prompt"
else
  echo "  FAIL  codex backend prompt  got [$out]"
  fail=1
fi

args=$(cat "$TMP_DIR/args" 2>/dev/null || true)
for needle in "exec" "--ephemeral" "--skip-git-repo-check" "--sandbox read-only" "--ask-for-approval never" "-c features.codex_hooks=false -"; do
  if printf '%s' "$args" | grep -Fq -- "$needle"; then
    echo "  PASS  codex args contain $needle"
  else
    echo "  FAIL  codex args missing [$needle], got [$args]"
    fail=1
  fi
done

exit "$fail"
