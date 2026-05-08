#!/bin/bash
# Smoke test for llm-client.sh OpenCode backend selection.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/opencode" <<'SH'
#!/bin/bash
printf '%s\n' "$*" > "$TASK_PROOF_FAKE_OPENCODE_ARGS"
file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--file" ]; then
    file="$arg"
    break
  fi
  prev="$arg"
done
printf 'opencode saw: '
cat "$file"
SH
chmod +x "$TMP_DIR/bin/opencode"

fail=0
echo "[llm-client-opencode]"

out=$(printf 'hello opencode' | PATH="$TMP_DIR/bin:$PATH" TASK_PROOF_FAKE_OPENCODE_ARGS="$TMP_DIR/args" TASK_PROOF_LLM_BACKEND=opencode bash "$ROOT/core/lib/llm-client.sh")
if [ "$out" = "opencode saw: hello opencode" ]; then
  echo "  PASS  opencode backend prompt"
else
  echo "  FAIL  opencode backend prompt  got [$out]"
  fail=1
fi

args=$(cat "$TMP_DIR/args" 2>/dev/null || true)
for needle in "run" "--pure" "--file" "Read the attached prompt file"; do
  if printf '%s' "$args" | grep -Fq -- "$needle"; then
    echo "  PASS  opencode args contain $needle"
  else
    echo "  FAIL  opencode args missing [$needle], got [$args]"
    fail=1
  fi
done

exit "$fail"
