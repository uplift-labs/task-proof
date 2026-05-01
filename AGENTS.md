# task-proof - Project Rules

These rules apply when working on the task-proof repo itself. Other
products should not import from this file; they have their own.

## Architectural invariants

- `core/` is host-agnostic for hook protocols. No host-specific hook
  JSON belongs there. The only guard inputs are stdin JSON and env vars;
  the only guard outputs are `BLOCK:` / `ASK:` / `WARN:` / empty.
  `core/lib/llm-client.sh` may know backend CLIs.
- `adapters/<host>/` is the only place host-specific JSON formats live.
  Adding a new host means adding a new directory under `adapters/`, not
  editing `core/`.
- `core/cmd/task-proof-run.sh` is the single public CLI entry point.
  Anything under `core/guards/` and `core/lib/` is internal unless
  `CONTRACT.md` says otherwise.
- All guards exit `0`. task-proof is a fail-open safety net; a buggy
  guard must never block real work.

## Change rules

- Guard changes need true-positive and true-negative fixtures under
  `tests/fixtures/<guard>/`.
- Host adapter changes need focused tests, such as
  `tests/test-adapter-codex.sh`.
- LLM backend changes need deterministic tests with mocked commands.
- Installer changes must stay idempotent. Running `install.sh` twice on
  the same target must leave `.uplift/task-proof/`, host hook config,
  and host skill directories unchanged.
- Update `CONTRACT.md` when tag vocabulary, env vars, backend selection,
  or dispatch groups change.

## Dogfood

This repo installs task-proof on itself:

```bash
bash install.sh --target "$(pwd)" --with-claude-code --with-codex
```

The committed `.uplift/`, `.claude/`, `.codex/`, and `.agents/`
directories are part of that dogfood. If you change `core/`,
`adapters/`, or `install.sh`, re-run the install and commit regenerated
artifacts in the same change.

## Tests

Run:

```bash
bash tests/run.sh
```

On Windows, use Git Bash if plain `bash` is blocked by the sandbox:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/run.sh
```

## Reinforcement

`core/` stays host-agnostic. Adapters translate. Guards always exit 0.
The single public entry point is `core/cmd/task-proof-run.sh`. Surface
backend failures honestly.
