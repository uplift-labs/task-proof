# task-proof — Project Rules

These rules apply when working on the task-proof repo itself. Other
products should not import from this file — they have their own.

## Architectural invariants

- `core/` is host-agnostic. No reference to Claude Code, OpenCode, or
  any other host. The only inputs are `stdin` JSON and env vars; the
  only outputs are `BLOCK:` / `ASK:` / `WARN:` / empty on stdout.
- `adapters/<host>/` is the ONLY place host-specific JSON formats live.
  Adding a new host means adding a new directory under `adapters/`,
  never editing `core/`.
- `core/cmd/task-proof-run.sh` is the **single public CLI entry point**.
  Anything under `core/guards/` and `core/lib/` is internal — callers
  must not script against those paths directly. The stability promise
  in `CONTRACT.md` applies only to the entry point.
- All guards exit `0` always. task-proof is a fail-open safety net; a
  buggy guard must never block real work.

## When you change a guard

- Update the relevant fixture under `tests/fixtures/<guard>/` so both
  the true-positive and true-negative paths are still covered.
- Run `bash tests/run.sh` and confirm the exit code is `0` before
  committing.
- Update `CONTRACT.md` if the guard's tag vocabulary, env vars, or
  dispatch group changes.

## When you add a new guard

1. Drop the script in `core/guards/<guard-name>.sh`. It must exit `0`,
   read input from stdin, and write a tag (or nothing) to stdout.
2. Register it in `core/cmd/task-proof-run.sh` under the right group.
3. Add at least one `tp-*.json` and one `tn-*.json` fixture under
   `tests/fixtures/<guard-name>/`.
4. Document it in `CONTRACT.md` with its tag semantics and env vars.
5. If the host needs to wire it up differently, add an adapter hook
   under `adapters/<host>/hooks/` and register it in
   `adapters/<host>/settings-hooks.json`.

## When you change the LLM client

- The argument and exit-code conventions in `CONTRACT.md` are part of
  the public surface. Bump major version on a breaking change.
- Add tests with `TASK_PROOF_LLM_CMD` mocks for new branches.
- Never make an `llm-client.sh` change that silently swallows backend
  errors with `exit 0` — that is the exact bug the fresh-verify dogfood
  caught during bootstrap.

## When you change the installer

- `install.sh` must remain idempotent: running it twice on the same
  target produces the same `.task-proof/`, `.claude/settings.json`,
  and `.claude/skills/task-proof/` state.
- `core/lib/json-merge.py`'s `MARKER` constant identifies our hooks
  for both update and uninstall — leave it pointing at
  `.task-proof/adapter/hooks/` and never touch entries that lack the
  marker.
- Verify `bash install.sh --target /tmp/<fresh-repo> --with-claude-code`
  in a throwaway repo before committing installer changes.

## Dogfood

This repo installs task-proof on itself (`bash install.sh --target $(pwd)
--with-claude-code`). The committed `.task-proof/` and `.claude/`
directories are part of that dogfood. If you change anything under
`core/`, `adapters/`, or `install.sh`, re-run the install and commit
the regenerated artifacts in the same change.

## Commits and tests

- Conventional commits: `type(scope): description`. Allowed types:
  `feat`, `fix`, `chore`, `docs`, `test`, `refactor`.
- Run `bash tests/run.sh` before every commit that touches `core/`,
  `adapters/`, or fixtures.
- Don't push directly to `main`. Use a short feature branch and merge
  via PR once `tests/run.sh` is green.

## Reinforcement

`core/` stays host-agnostic. Adapters translate. Guards always exit 0.
The single public entry point is `core/cmd/task-proof-run.sh`. Surface
backend failures honestly — fresh-verify caught a swallowed error in
the LLM client on the very first dogfood run, and that is exactly the
shape of bug the product is designed to catch.
