# task-proof - Project Rules

These rules apply when working on the task-proof repo itself. Other
products should not import from this file; they have their own.

## Architectural invariants

- `core/` is host-agnostic for hook protocols. No host-specific hook
  JSON belongs there. The only guard inputs are stdin JSON and env vars;
  the only guard outputs are `BLOCK:` / `ASK:` / `WARN:` / empty.
  `core/lib/llm-client.ts` may know backend CLIs.
- `adapters/opencode/` is the only supported host integration. Keep
  host-specific OpenCode plugin behavior there, not in `core/`.
- `core/cmd/task-proof-run.ts` is the single public CLI entry point.
  Anything under `core/guards/` and `core/lib/` is internal unless
  `CONTRACT.md` says otherwise.
- The public CLI always exits `0`. task-proof is a fail-open safety net;
  a buggy guard must never block real work.

## Change rules

- Guard changes need true-positive and true-negative fixtures under
  `tests/fixtures/<guard>/`.
- OpenCode adapter changes need focused coverage in `tests/run.ts`.
- LLM backend changes need deterministic tests with mocked commands.
- Installer changes must stay idempotent. Running `npx tsx install.ts` twice on
  the same target must leave `.uplift/task-proof/` and `.opencode/`
  unchanged.
- Update `CONTRACT.md` when tag vocabulary, env vars, backend selection,
  or dispatch groups change.

## Dogfood

This repo installs task-proof on itself:

```bash
npm run install:local
```

The committed `.uplift/` and `.opencode/` directories are part of that
dogfood. If you change `core/`, `adapters/`, or `install.ts`, re-run the
install and commit regenerated artifacts in the same change.

## Tests

Run:

```bash
npm test
```

Run `npm run check` for TypeScript type checking.

## Reinforcement

`core/` stays host-agnostic. Adapters translate. The CLI always exits 0.
The single public entry point is `core/cmd/task-proof-run.ts`. Surface
backend failures honestly.
