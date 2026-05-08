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

### Claude Code

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh) --with-claude-code
```

That installs the core under `.uplift/task-proof/`, registers hooks in
`.claude/settings.json` (idempotently — existing hooks are kept), and
drops the `task-proof` skill into `.claude/skills/`.

Commit `.uplift/task-proof/`, `.claude/settings.json`, and
`.claude/skills/task-proof/` so the proof loop is available in worktrees
and to your collaborators.

### Codex

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh) --with-codex
```

That installs the core under `.uplift/task-proof/`, enables Codex hooks
in `.codex/config.toml`, registers lifecycle hooks in
`.codex/hooks.json`, and installs the repo-scoped skill under
`.agents/skills/task-proof/`.

Commit `.uplift/task-proof/`, `.codex/`, and
`.agents/skills/task-proof/`. Codex loads project `.codex/` config only
for trusted projects.

### OpenCode

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh) --with-opencode
```

That installs the core under `.uplift/task-proof/`, installs a
project-local OpenCode plugin under `.opencode/plugins/`, and installs
the repo-scoped skill under `.opencode/skills/task-proof/`.

Commit `.uplift/task-proof/` and `.opencode/` so the proof loop is
available in worktrees. OpenCode auto-loads project plugins from
`.opencode/plugins/` unless it is started with `--pure`.

### All supported hosts

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh) --with-claude-code --with-codex --with-opencode
```

### Core only

```bash
bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/task-proof/main/remote-install.sh)
```

Installs only the core multiplexer and guards under
`.uplift/task-proof/core/`.
Wire them into your own host (pre-commit hook, GitHub Actions, etc.)
following the [public CLI contract](CONTRACT.md).

## How it works

```
Claude Code / Codex / OpenCode hook event
        │
        ▼
.uplift/task-proof/adapter/hooks/*.sh or .opencode/plugins/task-proof.js
        │                                      ← host adapter (JSON ↔ tags)
        │
        ▼
.uplift/task-proof/core/cmd/task-proof-run.sh pre-commit  ← multiplexer
        │
        ▼
.uplift/task-proof/core/guards/fresh-verify.sh      ← guard (BLOCK/ASK/empty)
        │
        ▼
.uplift/task-proof/core/lib/llm-client.sh           ← backend abstraction
        │
        ▼
TASK_PROOF_LLM_CMD → Codex-session codex exec → claude -p → codex exec → opencode run → ANTHROPIC_API_KEY
```

Two layers, on purpose:

- **`core/`** is host-agnostic and speaks plain text tags
  (`BLOCK:` / `ASK:` / `WARN:` / empty). Runs anywhere.
- **`adapters/<host>/`** translates those tags to the host's hook
  protocol. Today: Claude Code, Codex, and OpenCode. Future: GitHub
  Actions, pre-commit, anything with a hook surface.

Runtime proof artifacts are separate from installed code and live under
`.task-proof/runs/<TASK_ID>/`.

## Configuration

Everything is environment variables — see [`CONTRACT.md`](CONTRACT.md)
for the full list. The most useful ones:

| Variable | Purpose |
|---|---|
| `TASK_PROOF_DISABLED=1` | Kill switch for the whole product |
| `TASK_PROOF_DISABLE_FRESH_VERIFY=1` | Disable just the verifier |
| `TASK_PROOF_LLM_CMD=...` | Plug in any LLM (ollama, vLLM, openai CLI, mock) |
| `TASK_PROOF_LLM_BACKEND=codex/claude/opencode/anthropic` | Force one built-in backend |
| `TASK_PROOF_CODEX_ASK_BEHAVIOR=warn` | Let Codex degrade `ASK:` to a warning instead of a block |
| `TASK_PROOF_OPENCODE_ASK_BEHAVIOR=warn` | Let OpenCode degrade `ASK:` to a warning log instead of a throw |
| `ANTHROPIC_API_KEY=...` | Fallback when `claude` CLI is not available |
| `CI=true` | Skip everything in CI environments |

## The skill

Once installed, invoke `task-proof` / `$task-proof` with a task
description. The skill walks the seven steps in the host-specific skill
file under `adapters/<host>/skills/task-proof/SKILL.md`:

1. **Spec freeze** — write acceptance criteria, get user confirmation,
   then treat the spec as immutable.
2. **Build** — implement normally with all your other guards active.
3. **Evidence pack** — record actual proof for each criterion in
   `.task-proof/runs/<TASK_ID>/evidence.json`.
4. **Fresh verify** — independent LLM checks spec vs evidence and
   writes a verdict.
5. **Fix loop** — up to 3 iterations on failures; escalate after.
6. **Complete** — report final verdict and commit only when appropriate
   for the host workflow.
7. **Self-improve** — reflect on what could have caught the issue
   sooner.

## Layout

```
task-proof/
├── core/
│   ├── cmd/task-proof-run.sh        ← public CLI entry point
│   ├── guards/{fresh-verify,proof-recommend}.sh
│   └── lib/{json-merge.py,json-field.sh,llm-client.sh,codex-config.py}
├── adapters/
│   ├── claude-code/
│   │   ├── settings-hooks.json
│   │   ├── hooks/{pre-bash,user-prompt-submit}.sh
│   │   └── skills/task-proof/SKILL.md
│   ├── codex/
│   │   ├── hooks.json
│   │   ├── hooks/{codex-pre-tool-use,codex-user-prompt-submit}.sh
│   │   └── skills/task-proof/SKILL.md
│   └── opencode/
│       ├── plugins/task-proof.js
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
`TASK_PROOF_LLM_CMD`, runs every fixture under `tests/fixtures/`, and
checks the Codex and OpenCode adapters, LLM backend selection, and
installer idempotency. True-positive fixtures (`tp-*.json`) must produce
non-empty output; true-negative fixtures (`tn-*.json`) must stay silent.

## Uninstall

```bash
python3 .uplift/task-proof/core/lib/json-merge.py .claude/settings.json /dev/null --uninstall
python3 .uplift/task-proof/core/lib/json-merge.py .codex/hooks.json /dev/null --uninstall
rm -rf .uplift/task-proof .claude/skills/task-proof .agents/skills/task-proof .opencode/plugins/task-proof.js .opencode/skills/task-proof
```

The `--uninstall` flag removes only hooks whose `command` contains the
`/task-proof/adapter/hooks/` marker. Other products' hooks are left
untouched. If no other Codex hooks use it, you can also remove
`codex_hooks = true` from `.codex/config.toml`.

OpenCode auto-loads `.opencode/plugins/*.js`; uninstalling the plugin
file is enough unless you added explicit OpenCode config yourself.

## License

[MIT](LICENSE).
