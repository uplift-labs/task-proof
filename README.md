# task-proof

> Independent verification framework for OpenCode - closes the
> self-certification gap by spawning a fresh LLM session that has never
> seen the build context.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## The Problem

The agent that wrote the code physically cannot judge it cleanly: it has
the same context, assumptions, and blind spots it had while building.
Self-certification bias is real, and on tasks with multiple acceptance
criteria it shows up as "everything looks good" reports for incomplete work.

`task-proof` closes that gap with two pieces working together:

1. **`fresh-verify` guard** - every `git push` and `git commit` is held for review by an LLM that sees only the last task description and the diff.
2. **`task-proof` skill** - a 7-step proof loop: spec freeze, build, evidence pack, fresh verify, fix loop, complete, self-improve.

A `proof-recommend` nudge fires once per session to suggest the skill when the user's request looks complex.

## Quickstart

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh)
```

That installs the core under `.uplift/task-proof/`, installs the project-local OpenCode plugin under `.opencode/plugins/`, and installs the repo-scoped skill under `.opencode/skills/task-proof/`.

Commit `.uplift/task-proof/` and `.opencode/` so the proof loop is available in worktrees. OpenCode auto-loads project plugins from `.opencode/plugins/` unless it is started with `--pure`.

## How It Works

```text
OpenCode hook event
        |
        v
.opencode/plugins/task-proof.js              <- OpenCode adapter
        |
        v
.uplift/task-proof/core/cmd/task-proof-run.sh pre-commit
        |
        v
.uplift/task-proof/core/guards/fresh-verify.sh
        |
        v
.uplift/task-proof/core/lib/llm-client.sh
        |
        v
TASK_PROOF_LLM_CMD -> opencode run --pure
```

Two layers, on purpose:

- **`core/`** is host-agnostic and speaks plain text tags: `BLOCK:`, `ASK:`, `WARN:`, or empty output.
- **`adapters/opencode/`** translates those tags to OpenCode's plugin hook surface.

Runtime proof artifacts are separate from installed code and live under `.task-proof/runs/<TASK_ID>/`.

## Configuration

Everything is environment variables. See [`CONTRACT.md`](CONTRACT.md) for the full list.

| Variable | Purpose |
|---|---|
| `TASK_PROOF_DISABLED=1` | Kill switch for the whole product |
| `TASK_PROOF_DISABLE_FRESH_VERIFY=1` | Disable just the verifier |
| `TASK_PROOF_DISABLE_PROOF_RECOMMEND=1` | Disable the prompt nudge |
| `TASK_PROOF_LLM_CMD=...` | Plug in any LLM command or mock backend |
| `TASK_PROOF_LLM_BACKEND=opencode` | Force the built-in OpenCode backend |
| `TASK_PROOF_OPENCODE_MODEL=...` | Optional model override for `opencode run` |
| `TASK_PROOF_OPENCODE_ASK_BEHAVIOR=warn` | Let OpenCode log `ASK:` and allow instead of throwing |
| `TASK_PROOF_OPENCODE_PROMPT_TIMEOUT_MS=...` | OpenCode prompt nudge timeout |
| `TASK_PROOF_OPENCODE_TOOL_TIMEOUT_MS=...` | OpenCode tool guard timeout |
| `CI=true` | Skip everything in CI environments |

## The Skill

Once installed, invoke `task-proof` with a task description. The skill walks the seven steps in `adapters/opencode/skills/task-proof/SKILL.md`:

1. **Spec freeze** - write acceptance criteria, get user confirmation, then treat the spec as immutable.
2. **Build** - implement normally with existing repo patterns.
3. **Evidence pack** - record actual proof for each criterion in `.task-proof/runs/<TASK_ID>/evidence.json`.
4. **Fresh verify** - independent LLM checks spec vs evidence and writes a verdict.
5. **Fix loop** - up to three iterations on failures, then escalate.
6. **Complete** - report final verdict and residual risks.
7. **Self-improve** - reflect on what could have caught the issue sooner.

## Layout

```text
task-proof/
|-- core/
|   |-- cmd/task-proof-run.sh
|   |-- guards/{fresh-verify,proof-recommend}.sh
|   `-- lib/{json-field.sh,llm-client.sh}
|-- adapters/
|   `-- opencode/
|       |-- plugins/task-proof.js
|       `-- skills/task-proof/SKILL.md
|-- templates/{spec.md.tmpl,gitignore.snippet}
|-- tests/{run.sh,fixtures/...}
|-- install.sh
|-- remote-install.sh
`-- CONTRACT.md
```

The committed `.uplift/` and `.opencode/` directories are dogfood output for this repo.

## Tests

```bash
bash tests/run.sh
```

The test runner sets up a throwaway git repo, mocks the LLM backend with `TASK_PROOF_LLM_CMD`, runs every fixture under `tests/fixtures/`, and checks the OpenCode adapter, OpenCode LLM backend selection, and installer idempotency.

True-positive fixtures (`tp-*.json`) must produce non-empty output; true-negative fixtures (`tn-*.json`) must stay silent.

## Uninstall

```bash
rm -rf .uplift/task-proof .opencode/plugins/task-proof.js .opencode/skills/task-proof
```

OpenCode auto-loads `.opencode/plugins/*.js`; uninstalling the plugin file is enough unless you added explicit OpenCode config yourself.

## License

[MIT](LICENSE).
