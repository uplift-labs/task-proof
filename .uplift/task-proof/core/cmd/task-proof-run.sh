#!/bin/bash
# task-proof-run.sh — task-proof multiplexer.
# Runs a group of guards, returns the highest-priority result.
#
# Usage: task-proof-run.sh <group>
# Groups: pre-commit | prompt-recommend
#
# Input:  JSON on stdin (raw hook payload from the host tool)
# Output: BLOCK:<reason> | ASK:<reason> | WARN:<context> | empty (allow)
# Exit:   always 0 (fail-open safety net)

set -u

GROUP="${1:-}"
[ -z "$GROUP" ] && { printf 'usage: task-proof-run.sh <group>\n' >&2; exit 0; }

# Global kill switch
[ "${CI:-}" = "true" ] && exit 0
[ "${TASK_PROOF_DISABLED:-}" = "1" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_DIR="$SCRIPT_DIR/../guards"

# Map group to guard list
case "$GROUP" in
  pre-commit)       GUARDS="fresh-verify" ;;
  prompt-recommend) GUARDS="proof-recommend" ;;
  *) exit 0 ;;
esac

# Read stdin once
INPUT=$(cat)

# Priority tracking: BLOCK > ASK > WARN > pass
BEST_ASK=""
BEST_WARN=""

for guard in $GUARDS; do
  # Per-guard disable: TASK_PROOF_DISABLE_FRESH_VERIFY=1, etc.
  env_name="TASK_PROOF_DISABLE_$(printf '%s' "$guard" | tr 'a-z-' 'A-Z_')"
  eval "[ \"\${${env_name}:-}\" = \"1\" ]" 2>/dev/null && continue

  [ -f "$GUARD_DIR/$guard.sh" ] || continue

  RESULT=$(printf '%s' "$INPUT" | bash "$GUARD_DIR/$guard.sh" 2>/dev/null) || true

  case "$RESULT" in
    BLOCK:*)
      # Highest priority — short-circuit immediately
      printf '%s' "$RESULT"
      exit 0
      ;;
    ASK:*)
      [ -z "$BEST_ASK" ] && BEST_ASK="$RESULT"
      ;;
    WARN:*)
      if [ -z "$BEST_WARN" ]; then
        BEST_WARN="$RESULT"
      else
        BEST_WARN="$BEST_WARN | ${RESULT#WARN:}"
      fi
      ;;
  esac
done

# Output highest-priority non-block result
if [ -n "$BEST_ASK" ]; then
  printf '%s' "$BEST_ASK"
elif [ -n "$BEST_WARN" ]; then
  printf '%s' "$BEST_WARN"
fi

exit 0
