---
name: task-proof
description: Run a proof loop for complex coding tasks in Codex: freeze acceptance criteria, build, capture evidence, run an independent verifier, and iterate on failures.
---

# Task Proof Loop

Use this skill for complex, multi-file Codex work where a normal final summary is not enough proof: freeze spec, build, gather evidence, fresh-verify, fix, and report.

**Trigger:** The user invokes `$task-proof` explicitly, or task-proof's prompt nudge recommends it for a complex request.

**Scope boundary:** This skill manages verification artifacts and the proof lifecycle. It does not replace Codex's sandboxing, approvals, project rules, or other installed hooks.

## Agentic Protocol

- Track the seven steps with Codex's task plan and keep statuses current.
- Complete the full proof loop; do not stop after implementation unless the user explicitly redirects.
- After the user confirms the spec, treat `spec.md` as immutable. A scope change requires a new task-proof run.
- Use at most three fix iterations. If verification still fails, stop and summarize what remains broken.

## Paths

Runtime artifacts go under `.task-proof/runs/<TASK_ID>/`.

The installed task-proof code normally lives under `.uplift/task-proof`. Resolve it this way:

```bash
TASK_PROOF_ROOT="${TASK_PROOF_ROOT:-$(git rev-parse --show-toplevel)/.uplift/task-proof}"
```

Generate `<TASK_ID>` as `YYYY-MM-DD-<short-slug>`, for example `2026-04-10-auth-refactor`.

## Step 1 - Spec Freeze

1. Parse the user's task description.
2. Write `.task-proof/runs/<TASK_ID>/spec.md` with numbered acceptance criteria:

   ```markdown
   # Task: <title>
   ## Acceptance Criteria
   - AC1: <criterion>
   - AC2: <criterion>
   ```

3. Present the spec to the user and wait for explicit confirmation.
4. After confirmation, do not edit `spec.md`.

## Step 2 - Build

Implement normally, using the repo's existing patterns. Keep unrelated refactors out. Do not commit unless the user asked for commits or the repository workflow requires it.

## Step 3 - Evidence Pack

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

For every criterion, run the relevant command or inspect the relevant file and record actual proof. Never mark `PASS` without evidence.

## Step 4 - Fresh Verify

Run an independent verifier through task-proof's LLM client:

```bash
TASK_PROOF_ROOT="${TASK_PROOF_ROOT:-$(git rev-parse --show-toplevel)/.uplift/task-proof}"
bash "$TASK_PROOF_ROOT/core/lib/llm-client.sh" "$(cat <<EOF
You are an independent verifier. You receive acceptance criteria and evidence.
For each criterion, verify independently. Do NOT trust the evidence at face value.

Reply as JSON: {"criteria": [{"id": "AC1", "verdict": "PASS|FAIL|UNKNOWN", "reason": "..."}]}

Spec:
$(cat .task-proof/runs/<TASK_ID>/spec.md)

Evidence:
$(cat .task-proof/runs/<TASK_ID>/evidence.json)
EOF
)" > .task-proof/runs/<TASK_ID>/verdict.json
```

`llm-client.sh` selects `TASK_PROOF_LLM_CMD`, then Codex/Claude/API backends as available. Codex nested runs disable task-proof hooks to avoid recursion.

If any criterion is `FAIL` or `UNKNOWN`, write `.task-proof/runs/<TASK_ID>/problems.md`.

## Step 5 - Fix Loop

If verification fails:

1. Read `spec.md`, `verdict.json`, and `problems.md`.
2. Apply minimal targeted fixes.
3. Re-run Step 3 and Step 4.
4. Stop after three failed cycles and escalate with a clear summary.

## Step 6 - Complete

When all criteria pass, report the final verdict, evidence path, and any residual risk. Commit only if the user asked for a commit.

## Step 7 - Self-Improve

Reflect briefly while context is fresh:

- Were the acceptance criteria verifier-friendly?
- Did evidence prove each criterion directly?
- Did the verifier catch something the builder missed?
- Was the overhead justified?

Small skill improvements belong in `adapters/codex/skills/task-proof/SKILL.md` in the task-proof repo. Structural changes should be proposed first.

## Reinforcement

Freeze spec first. Build with existing repo patterns. Capture real evidence. Verify independently. Fix up to three times. Never call unverified work complete.
