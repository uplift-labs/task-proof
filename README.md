# task-proof

> Independent verification framework for AI coding agents — closes the
> self-certification gap by spawning a fresh LLM session that has never
> seen the build context.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## The problem

The agent that wrote the code physically cannot judge it cleanly: it
has the same context, the same assumptions, and the same blind spots
it had while building. Self-certification bias is real, and on tasks
with three or more acceptance criteria it shows up reliably as
"everything looks good" reports for work that quietly missed AC3.

`task-proof` closes that gap with two pieces working together:

1. **`fresh-verify` guard** — every `git push` and `git commit` is held
   for review by an LLM that sees only your last task description and
   the diff. No build context, no anchoring, no rubber-stamping.
2. **`task-proof` skill** — a 7-step proof loop (spec freeze → build →
   evidence pack → fresh verify → fix loop) so non-trivial tasks have
   a structured verification trail, not just a builder's word for it.

A `proof-recommend` nudge fires once per session to suggest the skill
when the user's request smells complex (5+ words, multi-step language).

## Quickstart

In any git repo using Claude Code:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh) --with-claude-code
```

That installs `.task-proof/` into your repo root, registers the hooks
in `.claude/settings.json` (idempotently — existing hooks are kept),
and drops the `task-proof` skill into `.claude/skills/`.

Commit `.task-proof/`, `.claude/settings.json`, and
`.claude/skills/task-proof/` so the proof loop is available in
worktrees and to your collaborators.

### Without Claude Code

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh)
```

Installs only the core multiplexer and guards under `.task-proof/core/`.
Wire them into your own host (pre-commit hook, GitHub Actions, etc.)
following the [public CLI contract](CONTRACT.md).

## How it works

```
Claude Code Bash event
        │
        ▼
.task-proof/adapter/hooks/pre-bash.sh           ← host adapter (JSON ↔ tags)
        │
        ▼
.task-proof/core/cmd/task-proof-run.sh pre-commit  ← multiplexer (group dispatch)
        │
        ▼
.task-proof/core/guards/fresh-verify.sh         ← guard (BLOCK/ASK/empty)
        │
        ▼
.task-proof/core/lib/llm-client.sh              ← backend abstraction
        │
        ▼
TASK_PROOF_LLM_CMD  →  claude -p  →  ANTHROPIC_API_KEY
```

Two layers, on purpose:

- **`core/`** is host-agnostic and speaks plain text tags
  (`BLOCK:` / `ASK:` / `WARN:` / empty). Runs anywhere.
- **`adapters/<host>/`** translates those tags to the host's hook
  protocol. Today: Claude Code. Future: OpenCode, GitHub Actions,
  pre-commit, anything with a hook surface.

## Configuration

Everything is environment variables — see [`CONTRACT.md`](CONTRACT.md)
for the full list. The most useful ones:

| Variable | Purpose |
|---|---|
| `TASK_PROOF_DISABLED=1` | Kill switch for the whole product |
| `TASK_PROOF_DISABLE_FRESH_VERIFY=1` | Disable just the verifier |
| `TASK_PROOF_LLM_CMD=...` | Plug in any LLM (ollama, vLLM, openai CLI, mock) |
| `ANTHROPIC_API_KEY=...` | Fallback when `claude` CLI is not available |
| `CI=true` | Skip everything in CI environments |

## The skill

Once installed, ask Claude Code to run `task-proof` with a task
description. The skill walks the seven steps in
[`adapters/claude-code/skills/task-proof/SKILL.md`](adapters/claude-code/skills/task-proof/SKILL.md):

1. **Spec freeze** — write acceptance criteria, get user confirmation,
   then treat the spec as immutable.
2. **Build** — implement normally with all your other guards active.
3. **Evidence pack** — record actual proof for each criterion in
   `.task-proof/runs/<TASK_ID>/evidence.json`.
4. **Fresh verify** — independent LLM checks spec vs evidence and
   writes a verdict.
5. **Fix loop** — up to 3 iterations on failures; escalate after.
6. **Complete** — report final verdict and commit.
7. **Self-improve** — reflect on what could have caught the issue
   sooner.

## Layout

```
task-proof/
├── core/
│   ├── cmd/task-proof-run.sh        ← public CLI entry point
│   ├── guards/{fresh-verify,proof-recommend}.sh
│   └── lib/{json-merge.py,json-field.sh,llm-client.sh}
├── adapters/
│   └── claude-code/
│       ├── settings-hooks.json
│       ├── hooks/{pre-bash,user-prompt-submit}.sh
│       └── skills/task-proof/SKILL.md
├── templates/{spec.md.tmpl,gitignore.snippet}
├── tests/{run.sh,fixtures/...}
├── install.sh
├── remote-install.sh
└── CONTRACT.md
```

## Tests

```bash
bash tests/run.sh
```

Sets up a throwaway git repo, mocks the LLM backend with
`TASK_PROOF_LLM_CMD`, and runs every fixture under `tests/fixtures/`.
True-positive fixtures (`tp-*.json`) must produce non-empty output;
true-negative fixtures (`tn-*.json`) must stay silent.

## Uninstall

```bash
python3 .task-proof/core/lib/json-merge.py .claude/settings.json /dev/null --uninstall
rm -rf .task-proof .claude/skills/task-proof
```

The `--uninstall` flag removes only hooks whose `command` contains the
`.task-proof/adapter/hooks/` marker. Other products' hooks are left
untouched.

## Related products

- [`uplift-labs/safeguard`](https://github.com/uplift-labs/safeguard)
  — destructive-shell guards (rm -rf protection, force-push asks, etc.)
- [`uplift-labs/dev-discipline`](https://github.com/uplift-labs/dev-discipline)
  — commit hygiene, regression gates, dead-branch detection
- [`uplift-labs/reinforce`](https://github.com/uplift-labs/reinforce)
  — session reflection and lesson-capture pipeline

`task-proof` is the verification piece — it does not replace any of
the above and runs alongside them happily.

## License

[MIT](LICENSE).
