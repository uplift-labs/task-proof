import { strict as assert } from "node:assert"
import { chmod, mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises"
import { existsSync } from "node:fs"
import { dirname, delimiter, join, resolve } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { runTaskProofGroup } from "../core/cmd/task-proof-run.ts"
import { runLlm } from "../core/lib/llm-client.ts"
import { runProcess, type EnvMap } from "../core/lib/process.ts"
import { runInstall } from "../install.ts"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
let failures = 0

async function check(name: string, fn: () => Promise<void> | void): Promise<void> {
  try {
    await fn()
    process.stdout.write(`  PASS  ${name}\n`)
  } catch (error) {
    failures += 1
    const message = error instanceof Error ? error.message : String(error)
    process.stdout.write(`  FAIL  ${name}  ${message}\n`)
  }
}

async function section(name: string, fn: () => Promise<void>): Promise<void> {
  process.stdout.write(`[${name}]\n`)
  await fn()
}

function llmCommand(reply: string): string {
  const script = `process.stdin.resume();process.stdin.on("end",()=>console.log(${JSON.stringify(reply)}))`
  return `${JSON.stringify(process.execPath)} -e ${JSON.stringify(script)}`
}

async function createGitRepo(): Promise<string> {
  const repo = await mkdtemp(join(process.env.TMPDIR || process.env.TEMP || "/tmp", "task-proof-test-"))
  await runProcess("git", ["init", "-q", repo])
  await runProcess("git", ["-c", "user.email=t@t", "-c", "user.name=t", "-C", repo, "commit", "--allow-empty", "-q", "-m", "init"])
  await writeFile(join(repo, "sample.txt"), "alpha\nbeta\ngamma\ndelta\nepsilon\n", "utf8")
  await runProcess("git", ["-C", repo, "add", "sample.txt"])
  await runProcess("git", ["-c", "user.email=t@t", "-c", "user.name=t", "-C", repo, "commit", "-q", "-m", "baseline"])
  await writeFile(join(repo, "sample.txt"), "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\n", "utf8")
  await runProcess("git", ["-C", repo, "add", "sample.txt"])
  return repo
}

function mapGroup(guard: string): string {
  if (guard === "fresh-verify") return "pre-commit"
  if (guard === "proof-recommend") return "prompt-recommend"
  return ""
}

async function fixtureTests(): Promise<void> {
  const repo = await createGitRepo()
  try {
    const fixturesRoot = join(root, "tests", "fixtures")
    const guardDirs = await readdir(fixturesRoot, { withFileTypes: true })
    for (const guardDir of guardDirs.filter((entry) => entry.isDirectory())) {
      const guard = guardDir.name
      const group = mapGroup(guard)
      if (!group) continue
      process.stdout.write(`[${guard}]\n`)

      const files = await readdir(join(fixturesRoot, guard))
      for (const fixture of files.filter((file) => file.endsWith(".json")).sort()) {
        await check(fixture, async () => {
          const expected = fixture.startsWith("tp-") ? "non-empty" : "empty"
          const raw = await readFile(join(fixturesRoot, guard, fixture), "utf8")
          const payload = raw.replaceAll("{{TMPDIR}}", repo.replaceAll("\\", "\\\\"))
          const env: EnvMap = { ...process.env, TMPDIR: repo }
          delete env.CI
          delete env.TASK_PROOF_DISABLED
          delete env.TASK_PROOF_DISABLE_FRESH_VERIFY
          delete env.TASK_PROOF_DISABLE_PROOF_RECOMMEND
          delete env.TASK_PROOF_LLM_BACKEND
          delete env.TASK_PROOF_LLM_CMD
          if (guard === "fresh-verify") env.TASK_PROOF_LLM_CMD = llmCommand("FAIL: synthetic verdict for fixture run")

          await rm(join(repo, "task-proof-recommend-test-pr-1"), { force: true })
          const output = await runTaskProofGroup(group, payload, { cwd: repo, env })
          if (expected === "non-empty") assert.notEqual(output, "")
          else assert.equal(output, "")
        })
      }
    }
  } finally {
    await rm(repo, { recursive: true, force: true })
  }
}

async function adapterTests(): Promise<void> {
  const repo = await createGitRepo()
  const previousRoot = process.env.TASK_PROOF_ROOT
  const previousTmp = process.env.TMPDIR
  const previousLlm = process.env.TASK_PROOF_LLM_CMD
  const previousAsk = process.env.TASK_PROOF_OPENCODE_ASK_BEHAVIOR
  try {
    process.env.TASK_PROOF_ROOT = root
    process.env.TMPDIR = repo
    const mod = await import("../adapters/opencode/plugins/task-proof.ts")
    const logs: unknown[] = []
    const hooks = await mod.default({
      worktree: repo,
      directory: repo,
      client: { app: { log: async ({ body }: { body: unknown }) => { logs.push(body) } } },
    })
    const chatMessage = hooks["chat.message"] as (input: unknown, output: { message?: { system?: string }; parts?: unknown[] }) => Promise<void>
    const toolBefore = hooks["tool.execute.before"] as (input: unknown, output: { args?: Record<string, unknown> }) => Promise<void>

    await check("chat.message injects recommendation", async () => {
      const output: { message: { system?: string }; parts: unknown[] } = { message: {}, parts: [{ type: "text", text: "Refactor the authentication system across services and update tests and documentation" }] }
      await chatMessage({ sessionID: "opencode-prompt-test" }, output)
      assert.match(output.message.system ?? "", /\[task-proof\] Assess this task/)
    })

    await check("tool.execute.before FAIL blocks", async () => {
      process.env.TASK_PROOF_LLM_CMD = llmCommand("FAIL: synthetic opencode adapter failure")
      await assert.rejects(
        () => toolBefore({ tool: "bash", sessionID: "opencode-tool-test", callID: "call-1" }, { args: { command: "git commit -m test" } }),
        /synthetic opencode adapter failure/,
      )
    })

    await check("tool.execute.before CONCERN default blocks", async () => {
      process.env.TASK_PROOF_LLM_CMD = llmCommand("CONCERN: synthetic opencode adapter concern")
      delete process.env.TASK_PROOF_OPENCODE_ASK_BEHAVIOR
      await assert.rejects(
        () => toolBefore({ tool: "bash", sessionID: "opencode-tool-test", callID: "call-2" }, { args: { command: "git commit -m test" } }),
        /synthetic opencode adapter concern/,
      )
    })

    await check("tool.execute.before CONCERN warn logs", async () => {
      process.env.TASK_PROOF_OPENCODE_ASK_BEHAVIOR = "warn"
      await toolBefore({ tool: "bash", sessionID: "opencode-tool-test", callID: "call-3" }, { args: { command: "git commit -m test" } })
      assert.match(JSON.stringify(logs), /synthetic opencode adapter concern/)
    })

    await check("tool.execute.before non-git silent", async () => {
      const logCount = logs.length
      process.env.TASK_PROOF_LLM_CMD = llmCommand("FAIL: should not be called")
      await toolBefore({ tool: "bash", sessionID: "opencode-tool-test", callID: "call-4" }, { args: { command: "npm test" } })
      assert.equal(logs.length, logCount)
    })

    await check("installed plugin loads from dogfood root", async () => {
      process.env.TASK_PROOF_ROOT = join(root, ".uplift", "task-proof")
      const installed = await import(pathToFileURL(join(root, ".opencode", "plugins", "task-proof.ts")).href) as unknown as { default: (ctx: unknown) => Promise<Record<string, unknown>> }
      const installedHooks = await installed.default({ worktree: repo, directory: repo })
      const installedChat = installedHooks["chat.message"] as (input: unknown, output: { message?: { system?: string }; parts?: unknown[] }) => Promise<void>
      const output: { message: { system?: string }; parts: unknown[] } = { message: {}, parts: [{ text: "Refactor billing, invoices, payments, reports, tests, and documentation" }] }
      await installedChat({ sessionID: "opencode-installed-plugin-test" }, output)
      assert.match(output.message.system ?? "", /\[task-proof\] Assess this task/)
    })
  } finally {
    await rm(repo, { recursive: true, force: true })
    restoreEnv("TASK_PROOF_ROOT", previousRoot)
    restoreEnv("TMPDIR", previousTmp)
    restoreEnv("TASK_PROOF_LLM_CMD", previousLlm)
    restoreEnv("TASK_PROOF_OPENCODE_ASK_BEHAVIOR", previousAsk)
  }
}

async function llmClientTests(): Promise<void> {
  const temp = await mkdtemp(join(process.env.TMPDIR || process.env.TEMP || "/tmp", "task-proof-llm-"))
  try {
    const bin = join(temp, "bin")
    await mkdir(bin, { recursive: true })
    const fakeScript = join(bin, "fake-opencode.cjs")
    await writeFile(fakeScript, `
const fs = require("node:fs")
const args = process.argv.slice(2)
if (process.env.TASK_PROOF_FAKE_OPENCODE_ARGS) fs.writeFileSync(process.env.TASK_PROOF_FAKE_OPENCODE_ARGS, args.join(" "))
let file = ""
for (let index = 0; index < args.length; index += 1) {
  if (args[index] === "--file") file = args[index + 1] || ""
}
if (!file) process.exit(0)
process.stdout.write("opencode saw: " + fs.readFileSync(file, "utf8"))
`, "utf8")

    if (process.platform === "win32") {
      await writeFile(join(bin, "opencode.cmd"), `@echo off\r\nnode "%~dp0fake-opencode.cjs" %*\r\n`, "utf8")
    } else {
      const executable = join(bin, "opencode")
      await writeFile(executable, `#!/usr/bin/env node\nrequire("./fake-opencode.cjs")\n`, "utf8")
      await chmod(executable, 0o755)
    }

    await check("opencode backend prompt", async () => {
      const argsFile = join(temp, "args")
      const result = await runLlm("hello opencode", {
        env: {
          ...process.env,
          PATH: `${bin}${delimiter}${process.env.PATH ?? ""}`,
          TASK_PROOF_FAKE_OPENCODE_ARGS: argsFile,
          TASK_PROOF_LLM_BACKEND: "opencode",
        },
      })
      assert.equal(result.status, 0)
      assert.equal(result.stdout, "opencode saw: hello opencode")
      const args = await readFile(argsFile, "utf8")
      for (const needle of ["run", "--pure", "--file", "Read the attached prompt file"]) {
        assert.match(args, new RegExp(escapeRegExp(needle)))
      }
    })
  } finally {
    await rm(temp, { recursive: true, force: true })
  }
}

async function installTests(): Promise<void> {
  const repo = await mkdtemp(join(process.env.TMPDIR || process.env.TEMP || "/tmp", "task-proof-install-"))
  try {
    await runProcess("git", ["init", "-q", repo])
    await mkdir(join(repo, ".opencode", "plugins"), { recursive: true })
    await mkdir(join(repo, ".uplift", "task-proof", "adapter", "hooks"), { recursive: true })
    await mkdir(join(repo, ".uplift", "task-proof", "core", "lib"), { recursive: true })
    await writeFile(join(repo, ".opencode", "plugins", "other.ts"), "export default async () => ({})\n", "utf8")
    await writeFile(join(repo, ".opencode", "plugins", "task-proof.js"), "old js plugin\n", "utf8")
    await writeFile(join(repo, "opencode.json"), "{\"permission\":{\"bash\":\"ask\"}}\n", "utf8")
    await writeFile(join(repo, ".uplift", "task-proof", "adapter", "hooks", "old.sh"), "old hook\n", "utf8")
    await writeFile(join(repo, ".uplift", "task-proof", "core", "lib", "old.py"), "old helper\n", "utf8")

    await check("install", async () => {
      await runInstall(["--target", repo], { log: () => undefined })
    })

    for (const installedPath of [
      ".uplift/task-proof/core/cmd/task-proof-run.ts",
      ".opencode/.gitignore",
      ".opencode/plugins/task-proof.ts",
      ".opencode/skills/task-proof/SKILL.md",
    ]) {
      await check(`installed ${installedPath}`, () => {
        assert.equal(existsSync(join(repo, installedPath)), true)
      })
    }

    await check("existing OpenCode files preserved", async () => {
      assert.equal(existsSync(join(repo, ".opencode", "plugins", "other.ts")), true)
      assert.match(await readFile(join(repo, "opencode.json"), "utf8"), /permission/)
    })

    await check("stale legacy install files removed", () => {
      assert.equal(existsSync(join(repo, ".opencode", "plugins", "task-proof.js")), false)
      assert.equal(existsSync(join(repo, ".uplift", "task-proof", "adapter")), false)
      assert.equal(existsSync(join(repo, ".uplift", "task-proof", "core", "lib", "old.py")), false)
    })

    await check("install is idempotent", async () => {
      const firstPlugin = await readFile(join(repo, ".opencode", "plugins", "task-proof.ts"), "utf8")
      const firstSkill = await readFile(join(repo, ".opencode", "skills", "task-proof", "SKILL.md"), "utf8")
      await runInstall(["--target", repo], { log: () => undefined })
      const secondPlugin = await readFile(join(repo, ".opencode", "plugins", "task-proof.ts"), "utf8")
      const secondSkill = await readFile(join(repo, ".opencode", "skills", "task-proof", "SKILL.md"), "utf8")
      assert.equal(firstPlugin, secondPlugin)
      assert.equal(firstSkill, secondSkill)
    })
  } finally {
    await rm(repo, { recursive: true, force: true })
  }
}

async function noLegacyCodeTests(): Promise<void> {
  const ignored = new Set([".git", "node_modules", "package-lock.json"])
  const legacy = await collectLegacyCodeFiles(root, ignored)
  await check("no Bash or JavaScript source remains", () => {
    assert.deepEqual(legacy, [])
  })
}

async function collectLegacyCodeFiles(dir: string, ignored: Set<string>): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true })
  const results: string[] = []
  for (const entry of entries) {
    if (ignored.has(entry.name)) continue
    const fullPath = join(dir, entry.name)
    if (entry.isDirectory()) {
      results.push(...await collectLegacyCodeFiles(fullPath, ignored))
      continue
    }
    if (entry.name.endsWith(".sh") || entry.name.endsWith(".js") || entry.name.endsWith(".cjs") || entry.name.endsWith(".mjs")) {
      results.push(fullPath.slice(root.length + 1).replaceAll("\\", "/"))
    }
  }
  return results.sort()
}

function restoreEnv(key: string, value: string | undefined): void {
  if (value === undefined) delete process.env[key]
  else process.env[key] = value
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

await fixtureTests()
await section("opencode-adapter", adapterTests)
await section("llm-client-opencode", llmClientTests)
await section("install-opencode", installTests)
await section("legacy-code", noLegacyCodeTests)

if (failures === 0) {
  process.stdout.write("all tests passed\n")
} else {
  process.stdout.write("some tests FAILED\n")
}
process.exit(failures === 0 ? 0 : 1)
