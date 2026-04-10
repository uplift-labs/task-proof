---
name: task-proof
description: Full proof loop for complex tasks — spec freeze, build, evidence pack, fresh verify, fix cycle
---

# Task Proof Loop

Structured proof loop for complex, multi-file tasks: freeze spec → build → evidence pack → fresh verify → fix cycle. Closes the self-certification gap by spawning a fresh LLM session that has never seen the build context.

**Trigger:** User invokes the task-proof skill explicitly. The `proof-recommend` guard nudges once per session for tasks with 3+ acceptance criteria, multi-file refactors, or other obviously-complex work.

**Scope boundary:** This skill manages the proof lifecycle. Any other guards installed in the host environment (safeguard, dev-discipline, …) keep running during the build phase — task-proof does not replace them.

## Agentic Protocol

- Before starting, create a Task for each Step using your host's task-tracking tool. Mark each task in_progress/completed as you go.
- Complete the full proof loop — partial runs leave unverified deliverables.
- The spec becomes immutable after user confirmation. Do NOT modify `spec.md` after Step 1.
- Max 3 fix iterations in Step 5. If still failing, escalate to user.

## Instructions

All artifacts go to `.task-proof/runs/<TASK_ID>/` (gitignored, transient).

Generate `<TASK_ID>` as `YYYY-MM-DD-<short-slug>` (e.g., `2026-04-10-auth-refactor`).

### Step 1 — Spec Freeze

1. Parse the user's task description.
2. Write `.task-proof/runs/<TASK_ID>/spec.md` with numbered acceptance criteria:
   ```markdown
   # Task: <title>
   ## Acceptance Criteria
   - AC1: <criterion>
   - AC2: <criterion>
   ...
   ```
3. Present spec to user. Wait for explicit confirmation before proceeding.
4. After confirmation, treat `spec.md` as immutable — any scope change requires a new task-proof invocation.

### Step 2 — Build

Implement the task normally. Any other host guards remain active. No additional overhead.

Commit after every meaningful milestone.

### Step 3 — Evidence Pack

Create `.task-proof/runs/<TASK_ID>/evidence.json`:
```json
{
  "task_id": "<TASK_ID>",
  "timestamp": "<ISO-8601>",
  "criteria": [
    {
      "id": "AC1",
      "status": "PASS|FAIL|UNKNOWN",
      "proof": "<command output, file path, test result>"
    }
  ]
}
```

For each criterion: run the relevant check (test, lint, manual inspection) and record actual output as proof. Never mark PASS without evidence.

### Step 4 — Fresh Verify

Spawn an independent verifier with no shared context using the LLM client shipped with task-proof:

```bash
bash .task-proof/core/lib/llm-client.sh "$(cat <<EOF
You are an independent verifier. You receive acceptance criteria and evidence.
For each criterion, run actual commands to verify independently. Do NOT trust the evidence at face value.

Reply as JSON: {"criteria": [{"id": "AC1", "verdict": "PASS|FAIL|UNKNOWN", "reason": "..."}]}

Spec:
$(cat .task-proof/runs/<TASK_ID>/spec.md)

Evidence:
$(cat .task-proof/runs/<TASK_ID>/evidence.json)
EOF
)" > .task-proof/runs/<TASK_ID>/verdict.json
```

`llm-client.sh` picks a backend automatically (`TASK_PROOF_LLM_CMD` override → `claude -p` → `ANTHROPIC_API_KEY` curl), so the proof loop is portable across hosts.

If any criterion is FAIL or UNKNOWN, write `.task-proof/runs/<TASK_ID>/problems.md` summarizing issues.

### Step 5 — Fix (if needed)

If verdict has failures:

1. Read ONLY `spec.md` + `verdict.json` + `problems.md` — avoid re-reading the full build context to stay focused.
2. Apply minimal, targeted fixes.
3. Re-run Step 3 (evidence pack) and Step 4 (fresh verify).
4. **Max 3 iterations.** If still failing after 3 cycles, stop and escalate to user with a summary of what remains broken and why.

### Step 6 — Complete

When all criteria PASS:
1. Report final verdict to user.
2. Commit any remaining changes.

### Step 7 — Self-Improvement

> **Core principle — do not remove.** Self-improvement while context is hot is a task-proof design invariant.

> **Size invariant.** ~30 core instructions max; the skill gets sharper, not longer.
> **Source of truth:** Edit `adapters/claude-code/skills/task-proof/SKILL.md` in the [task-proof repo](https://github.com/uplift-labs/task-proof) — the installed copy in `.claude/skills/task-proof/` is overwritten by the installer.

Reflect on the proof loop execution:
1. **Spec quality?** Were acceptance criteria clear enough for the verifier?
2. **Evidence quality?** Did the verifier find gaps the builder missed?
3. **Iteration count?** If >1 fix cycle, what could have caught the issue earlier?
4. **Ceremony overhead?** Was the proof loop justified for this task's complexity?

**Action:** Small tweaks — apply directly via PR to the task-proof repo. Structural changes — propose first.

## Reinforcement

Freeze spec first. Build with guards. Pack evidence with proof. Verify independently. Fix up to 3 times, then escalate. Never skip the fresh verify.
