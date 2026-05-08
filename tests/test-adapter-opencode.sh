#!/bin/bash
# Smoke tests for the OpenCode plugin adapter.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_REPO=$(mktemp -d)
trap 'rm -rf "$TMP_REPO"' EXIT

git init -q "$TMP_REPO"
GIT_AUTHOR="-c user.email=t@t -c user.name=t"
# shellcheck disable=SC2086
git $GIT_AUTHOR -C "$TMP_REPO" commit --allow-empty -q -m init
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\n' > "$TMP_REPO/sample.txt"
git -C "$TMP_REPO" add sample.txt
# shellcheck disable=SC2086
git $GIT_AUTHOR -C "$TMP_REPO" commit -q -m baseline
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\n' > "$TMP_REPO/sample.txt"
git -C "$TMP_REPO" add sample.txt

cat > "$TMP_REPO/opencode-adapter-test.mjs" <<'JS'
import { pathToFileURL } from "node:url"

const [root, repo] = process.argv.slice(2)
process.env.TASK_PROOF_ROOT = root
process.env.TMPDIR = repo

const mod = await import(pathToFileURL(`${root}/adapters/opencode/plugins/task-proof.js`).href)
const logs = []
const ctx = {
  worktree: repo,
  directory: repo,
  client: { app: { log: async ({ body }) => logs.push(body) } },
}
const hooks = await mod.default.server(ctx)

let fail = 0
function pass(name) {
  console.log(`  PASS  ${name}`)
}
function failCase(name, detail) {
  console.log(`  FAIL  ${name}  ${detail}`)
  fail = 1
}
function expectContains(name, value, needle) {
  if (String(value).includes(needle)) pass(name)
  else failCase(name, `expected [${needle}], got [${value}]`)
}
async function expectThrow(name, fn, needle) {
  try {
    await fn()
    failCase(name, "expected throw")
  } catch (err) {
    if (String(err.message).includes(needle)) pass(name)
    else failCase(name, `wrong error [${err.message}]`)
  }
}

let promptOutput = { message: {}, parts: [{ type: "text", text: "Refactor the authentication system across services and update tests and documentation" }] }
await hooks["chat.message"]({ sessionID: "opencode-prompt-test" }, promptOutput)
expectContains("chat.message injects recommendation", promptOutput.message.system, "[task-proof] Assess this task")

process.env.TASK_PROOF_LLM_CMD = 'echo "FAIL: synthetic opencode adapter failure"'
await expectThrow(
  "tool.execute.before FAIL blocks",
  () => hooks["tool.execute.before"](
    { tool: "bash", sessionID: "opencode-tool-test", callID: "call-1" },
    { args: { command: "git commit -m test" } },
  ),
  "synthetic opencode adapter failure",
)

process.env.TASK_PROOF_LLM_CMD = 'echo "CONCERN: synthetic opencode adapter concern"'
delete process.env.TASK_PROOF_OPENCODE_ASK_BEHAVIOR
await expectThrow(
  "tool.execute.before CONCERN default blocks",
  () => hooks["tool.execute.before"](
    { tool: "bash", sessionID: "opencode-tool-test", callID: "call-2" },
    { args: { command: "git commit -m test" } },
  ),
  "synthetic opencode adapter concern",
)

process.env.TASK_PROOF_OPENCODE_ASK_BEHAVIOR = "warn"
await hooks["tool.execute.before"](
  { tool: "bash", sessionID: "opencode-tool-test", callID: "call-3" },
  { args: { command: "git commit -m test" } },
)
expectContains("tool.execute.before CONCERN warn logs", JSON.stringify(logs), "synthetic opencode adapter concern")

const logCount = logs.length
process.env.TASK_PROOF_LLM_CMD = 'echo "FAIL: should not be called"'
await hooks["tool.execute.before"](
  { tool: "bash", sessionID: "opencode-tool-test", callID: "call-4" },
  { args: { command: "npm test" } },
)
if (logs.length === logCount) pass("tool.execute.before non-git silent")
else failCase("tool.execute.before non-git silent", `logs changed from ${logCount} to ${logs.length}`)

process.exit(fail)
JS

echo "[opencode-adapter]"
node "$TMP_REPO/opencode-adapter-test.mjs" "$ROOT" "$TMP_REPO"
