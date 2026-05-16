# Public CLI Contract

`core/cmd/task-proof-run.ts` is the single stable public CLI entry point.
Run it with `tsx`:

```bash
npx tsx core/cmd/task-proof-run.ts <group>
```

TypeScript modules under `core/guards/` and `core/lib/` are internal unless
this contract says otherwise. Pin to a `task-proof` release tag if you script
against internal modules directly.

## Conventions

- **Runtime:** Node.js plus `tsx` for direct TypeScript execution.
- **Input:** JSON on stdin from the OpenCode adapter.
- **Output:** tagged plain text on stdout.
- **Exit codes:** `task-proof-run.ts` always exits `0`. task-proof is a fail-open safety net; errors in guards are swallowed, never propagated, so a buggy guard can never block real work.
- **No state files** except `${TMPDIR:-/tmp}/task-proof-recommend-<session_id>` for the proof-recommend session marker.
- **Skill artifacts** live under `.task-proof/runs/<TASK_ID>/` and are managed by the skill, not by the CLI multiplexer.

The OpenCode adapter passes a normalized envelope:

| Field | Meaning |
|-------|---------|
| `session_id` | Stable session id used for once-per-session nudges |
| `cwd` | Repository/worktree directory for the tool call |
| `command` | Shell command to classify for `pre-commit` |
| `task_description` | Last user task prompt for fresh verification context |
| `prompt` | User prompt text for `prompt-recommend` |

## Output Tags

| Tag | Meaning | OpenCode action |
|-----|---------|-----------------|
| `BLOCK:<reason>` | Hard deny; the action must not proceed | Throw from the plugin hook |
| `ASK:<reason>` | Concerning but possibly intentional | Throw by default, or log and allow when configured |
| `WARN:<context>` | Informational warning | Inject or log advisory context |
| *(empty)* | All guards passed | Proceed normally |

Priority: `BLOCK` > `ASK` > `WARN` > pass. On `BLOCK`, remaining guards in the group are short-circuited.

OpenCode server `tool.execute.before` hooks can block by throwing, but do not expose a direct native permission prompt. The OpenCode adapter maps `ASK:` to block by default. Set `TASK_PROOF_OPENCODE_ASK_BEHAVIOR=warn` to log and allow instead.

## Command

### `task-proof-run`

Run a group of guards against a single adapter invocation.

```bash
npx tsx core/cmd/task-proof-run.ts <group>
```

| Group | Guards | Hook event |
|-------|--------|------------|
| `pre-commit` | fresh-verify | `tool.execute.before` for `git push` / `git commit` |
| `prompt-recommend` | proof-recommend | `chat.message` |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TASK_PROOF_DISABLED` | unset | Set to `1` to disable all guards |
| `TASK_PROOF_DISABLE_FRESH_VERIFY` | unset | Disable the fresh-verify guard |
| `TASK_PROOF_DISABLE_PROOF_RECOMMEND` | unset | Disable the proof-recommend nudge |
| `TASK_PROOF_LLM_CMD` | unset | Override the LLM backend command; prompt is piped to stdin and the command string is executed through the platform shell |
| `TASK_PROOF_LLM_BACKEND` | unset | Force the `opencode` built-in backend |
| `TASK_PROOF_OPENCODE_MODEL` | unset | Optional model override for `opencode run` |
| `TASK_PROOF_OPENCODE_ASK_BEHAVIOR` | `block` | OpenCode adapter behavior for `ASK:`; set `warn` to log and allow |
| `TASK_PROOF_OPENCODE_PROMPT_TIMEOUT_MS` | `5000` | OpenCode prompt nudge adapter timeout |
| `TASK_PROOF_OPENCODE_TOOL_TIMEOUT_MS` | `140000` | OpenCode tool guard adapter timeout |
| `CI` | unset | Set to `true` to skip all guards in CI environments |

## LLM Client Contract

`core/lib/llm-client.ts` is the programmatic helper used by `fresh-verify` and the skill. `core/lib/llm-client.cli.ts` is the CLI wrapper.

```bash
npx tsx core/lib/llm-client.cli.ts "<prompt>"
printf '%s' "<prompt>" | npx tsx core/lib/llm-client.cli.ts
```

**Input:** A single prompt string.

**Output:** The model's raw text reply on stdout.

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Success; non-empty model reply on stdout |
| `1` | No backend available, unknown backend, or empty prompt |
| `2` | Built-in backend invoked but errored; message on stderr |

`TASK_PROOF_LLM_CMD` preserves the override contract by returning the custom command's exit code.

**Backend selection** (first match wins):

1. `TASK_PROOF_LLM_CMD` env override. The value is executed through the platform shell with the prompt piped to stdin, which supports custom LLM commands and deterministic test mocks.
2. `TASK_PROOF_LLM_BACKEND=opencode` when set.
3. `opencode run --pure` in `$PATH`, using `--pure` to avoid plugin recursion.

## Guards

### fresh-verify

Spawns a fresh LLM session through `llm-client.ts` to independently review staged changes before `git push` or `git commit`. The reviewer sees only the user's last task description and the diff.

- **BLOCK:** reviewer returned `FAIL: <reason>`
- **ASK:** reviewer returned `CONCERN: <note>`
- **empty:** reviewer returned `PASS`, or LLM call failed fail-open
- Skips: non-git commands, WIP commits, diffs under three changed lines, empty diffs, and any backend failure

### proof-recommend

Once-per-session prompt nudge that suggests the task-proof skill for prompts with five or more words. The marker file lives in `${TMPDIR:-/tmp}` and is keyed by `session_id`.

- **WARN:** the message recommending the task-proof skill
- **empty:** short message, marker already set, or unrecognized payload

## Skill Protocol

The `task-proof` skill runs a 7-step proof loop. Full instructions live under `adapters/opencode/skills/task-proof/SKILL.md`.

1. **Spec freeze** - write `.task-proof/runs/<TASK_ID>/spec.md` with numbered acceptance criteria, get user confirmation, treat as immutable thereafter.
2. **Build** - implement normally with existing repo patterns.
3. **Evidence pack** - write `.task-proof/runs/<TASK_ID>/evidence.json` recording PASS/FAIL/UNKNOWN plus actual proof for each criterion.
4. **Fresh verify** - call `llm-client.cli.ts` with spec and evidence, save the verdict to `.task-proof/runs/<TASK_ID>/verdict.json`.
5. **Fix loop** - up to three iterations of re-evidence, re-verify, targeted fix.
6. **Complete** - report verdict and residual risk.
7. **Self-improve** - reflect on spec quality, evidence quality, iteration count, and ceremony overhead.

## Stability Promise

Within a major version (`v0.x`):

- The output tag vocabulary (`BLOCK:`, `ASK:`, `WARN:`, empty) will not change shape.
- The `task-proof-run.ts <group>` group names will not be removed, though new groups may be added.
- `llm-client.cli.ts` argument and exit-code conventions will not change.
- Skill artifact paths (`.task-proof/runs/<TASK_ID>/{spec.md,evidence.json,verdict.json,problems.md}`) will not change without a migration note.
