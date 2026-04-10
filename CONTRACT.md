# Public CLI Contract

`core/cmd/task-proof-run.sh` is the single stable public entry point.
Scripts under `core/guards/` and `core/lib/` are internal and may change
without notice — pin to a `task-proof` release tag if you script against
them directly.

## Conventions

- **Input:** JSON on stdin (the raw hook payload from the host tool).
- **Output:** tagged plain text on stdout (see Output Tags below).
- **Exit codes:** always `0`. task-proof is a fail-open safety net —
  errors in guards are swallowed, never propagated, so a buggy guard
  can never block real work.
- **No state files** except `${TMPDIR:-/tmp}/task-proof-recommend-<session_id>`
  for the proof-recommend session marker (auto-cleaned by the OS).
- **Skill artifacts** live under `.task-proof/runs/<TASK_ID>/` and are
  managed by the skill, not by the CLI multiplexer.

## Output Tags

| Tag | Meaning | Host action |
|-----|---------|-------------|
| `BLOCK:<reason>` | Hard deny — the action must not proceed | Block / deny |
| `ASK:<reason>` | Concerning but possibly intentional — ask the user | Show confirmation dialog |
| `WARN:<context>` | Informational warning — does not block | Inject as advisory context |
| *(empty)* | All guards passed — allow | Proceed normally |

Priority: `BLOCK` > `ASK` > `WARN` > pass. On `BLOCK`, remaining guards
in the group are short-circuited.

## Command

### `task-proof-run`

Run a group of guards against a single tool invocation.

```
task-proof-run.sh <group>
```

| Group | Guards | Hook event |
|-------|--------|------------|
| `pre-commit` | fresh-verify | PreToolUse Bash (git push / git commit) |
| `prompt-recommend` | proof-recommend | UserPromptSubmit |

## Configuration (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `TASK_PROOF_DISABLED` | unset | Set to `1` to disable all guards |
| `TASK_PROOF_DISABLE_FRESH_VERIFY` | unset | Disable the fresh-verify guard |
| `TASK_PROOF_DISABLE_PROOF_RECOMMEND` | unset | Disable the proof-recommend nudge |
| `TASK_PROOF_LLM_CMD` | unset | Override the LLM backend (see below) |
| `TASK_PROOF_MODEL` | `claude-haiku-4-5` | Model passed to backend when applicable |
| `TASK_PROOF_MAX_TOKENS` | `1024` | Max tokens for the API backend |
| `ANTHROPIC_API_KEY` | unset | Fallback backend (curl to api.anthropic.com) |
| `CI` | unset | Set to `true` to skip all guards (CI environments) |

## LLM Client Contract

`core/lib/llm-client.sh` is a stable helper used by `fresh-verify` and
the skill. Both `fresh-verify` and any user code that wants the same
backend selection can call it the same way.

```
bash core/lib/llm-client.sh "<prompt>"          # prompt as $1
printf '%s' "<prompt>" | bash core/lib/llm-client.sh  # prompt on stdin
```

**Input:** A single prompt string.

**Output:** The model's raw text reply on stdout.

**Exit codes:**
| Code | Meaning |
|------|---------|
| `0` | Success — non-empty model reply on stdout |
| `1` | No backend available, or empty prompt |
| `2` | Backend invoked but errored (HTTP error, empty content, etc.) — message on stderr |

**Backend selection** (first match wins):

1. `TASK_PROOF_LLM_CMD` env override — the value is `eval`'d with the
   prompt piped to its stdin. Use this to plug in any LLM (ollama,
   vLLM, openai CLI, etc.) or to mock the backend in tests.
2. `claude` CLI in `$PATH` — Claude Code Max subscription, no API key.
3. `ANTHROPIC_API_KEY` env — direct `curl` call to api.anthropic.com.
   Requires `curl` and `jq`.

## Guards

### fresh-verify

Spawns a fresh LLM session through `llm-client.sh` to independently
review staged changes before `git push` or `git commit`. The reviewer
sees only (1) the user's last task description and (2) the diff — no
build context — so it cannot inherit the builder's blind spots.

- **BLOCK:** reviewer returned `FAIL: <reason>`
- **ASK:** reviewer returned `CONCERN: <note>`
- *empty:* reviewer returned `PASS`, or LLM call failed (fail-open)
- Skips: non-git commands, WIP commits, diffs under 3 changed lines,
  empty diffs, and any backend failure (degrades gracefully)

### proof-recommend

Once-per-session UserPromptSubmit nudge that suggests the task-proof
skill for prompts with 5+ words. Marker file lives in `${TMPDIR:-/tmp}`
keyed by `session_id` so the same session never sees the nudge twice.

- **WARN:** the message recommending the task-proof skill
- *empty:* short message, marker already set, or unrecognized payload

## Skill Protocol (high level)

The `task-proof` skill runs a 7-step proof loop. Full instructions live
in [`adapters/claude-code/skills/task-proof/SKILL.md`](adapters/claude-code/skills/task-proof/SKILL.md).

1. **Spec freeze** — write `.task-proof/runs/<TASK_ID>/spec.md` with
   numbered acceptance criteria, get user confirmation, treat as
   immutable thereafter.
2. **Build** — implement normally, all host guards active.
3. **Evidence pack** — write `.task-proof/runs/<TASK_ID>/evidence.json`
   recording PASS/FAIL/UNKNOWN plus actual proof for each criterion.
4. **Fresh verify** — call `llm-client.sh` with spec + evidence, save
   the verdict to `.task-proof/runs/<TASK_ID>/verdict.json`.
5. **Fix loop** — up to 3 iterations of (re-evidence → re-verify →
   targeted fix). Escalate to user after the third failure.
6. **Complete** — report verdict, commit remaining work.
7. **Self-improve** — reflect on spec quality, evidence quality,
   iteration count, ceremony overhead; tweak the skill if useful.

## Stability promise

Within a major version (`v0.x`):
- The output tag vocabulary (`BLOCK:`, `ASK:`, `WARN:`, empty) will not
  change shape.
- The `task-proof-run.sh <group>` group names will not be removed,
  though new groups may be added.
- `llm-client.sh` argument and exit-code conventions will not change.
- The skill artifact directory layout
  (`.task-proof/runs/<TASK_ID>/{spec.md,evidence.json,verdict.json,problems.md}`)
  will not change shape.

A breaking change to any of the above bumps the major version.
