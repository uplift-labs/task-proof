import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { join } from "node:path"

const SERVICE = "task-proof.opencode"
const DEFAULT_PROMPT_TIMEOUT_MS = 5000
const DEFAULT_TOOL_TIMEOUT_MS = 140000
const lastPromptBySession = new Map()

function contextRoot(ctx) {
  if (process.env.TASK_PROOF_ROOT) return process.env.TASK_PROOF_ROOT
  const base = ctx?.worktree || ctx?.directory || process.cwd()
  return join(base, ".uplift", "task-proof")
}

function contextCwd(ctx) {
  return ctx?.worktree || ctx?.directory || process.cwd()
}

function promptText(parts) {
  if (!Array.isArray(parts)) return ""
  return parts
    .map((part) => {
      if (typeof part?.text === "string") return part.text
      if (typeof part?.content === "string") return part.content
      return ""
    })
    .filter(Boolean)
    .join("\n")
}

function appendSystem(output, message) {
  if (!output.message) output.message = {}
  const current = output.message.system
  output.message.system = [current, message].filter(Boolean).join("\n\n")
}

async function log(client, level, message, extra = {}) {
  try {
    await client?.app?.log?.({
      body: { service: SERVICE, level, message, extra },
    })
  } catch {
    // Logging must never change hook behavior.
  }
}

function runTaskProof(root, group, payload, timeoutMs, envPatch = {}) {
  const runner = join(root, "core", "cmd", "task-proof-run.sh")
  if (!existsSync(runner)) return Promise.resolve("")

  return new Promise((resolve) => {
    let settled = false
    let stdout = ""
    const done = (value) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve(value)
    }

    const child = spawn(process.env.TASK_PROOF_BASH || "bash", [runner, group], {
      cwd: payload.cwd || process.cwd(),
      env: { ...process.env, ...envPatch },
      windowsHide: true,
    })

    const timer = setTimeout(() => {
      child.kill()
      done("")
    }, timeoutMs)

    child.stdout.on("data", (chunk) => {
      stdout += String(chunk)
    })
    child.on("error", () => done(""))
    child.on("close", () => done(stdout.trim()))

    child.stdin.end(JSON.stringify(payload))
  })
}

function isGitWriteCommand(command) {
  return /\bgit\s+(?:push|commit)\b/.test(command)
}

function decisionBody(result) {
  return result.replace(/^(BLOCK|ASK|WARN):/, "")
}

async function handlePrompt(ctx, input, output) {
  const prompt = promptText(output.parts)
  if (!prompt) return

  lastPromptBySession.set(input.sessionID, prompt.slice(0, 2000))

  const payload = {
    session_id: input.sessionID,
    cwd: contextCwd(ctx),
    hook_event_name: "UserPromptSubmit",
    prompt,
  }
  const result = await runTaskProof(
    contextRoot(ctx),
    "prompt-recommend",
    payload,
    Number(process.env.TASK_PROOF_OPENCODE_PROMPT_TIMEOUT_MS || DEFAULT_PROMPT_TIMEOUT_MS),
  )

  if (result.startsWith("WARN:")) appendSystem(output, decisionBody(result))
}

async function handleTool(ctx, input, output) {
  if (input.tool !== "bash") return

  const command = String(output.args?.command ?? "")
  if (!command || !isGitWriteCommand(command)) return

  const payload = {
    session_id: input.sessionID,
    cwd: contextCwd(ctx),
    hook_event_name: "PreToolUse",
    tool_name: "bash",
    command,
    task_description: lastPromptBySession.get(input.sessionID) || "",
    tool_input: { command },
  }

  const envPatch = {}
  if (!process.env.TASK_PROOF_LLM_BACKEND && !process.env.TASK_PROOF_LLM_CMD) {
    envPatch.TASK_PROOF_LLM_BACKEND = "opencode"
  }

  const result = await runTaskProof(
    contextRoot(ctx),
    "pre-commit",
    payload,
    Number(process.env.TASK_PROOF_OPENCODE_TOOL_TIMEOUT_MS || DEFAULT_TOOL_TIMEOUT_MS),
    envPatch,
  )

  if (result.startsWith("BLOCK:")) throw new Error(decisionBody(result))
  if (result.startsWith("ASK:")) {
    const message = decisionBody(result)
    if (process.env.TASK_PROOF_OPENCODE_ASK_BEHAVIOR === "warn") {
      await log(ctx.client, "warn", message, { sessionID: input.sessionID, callID: input.callID, command })
      return
    }
    throw new Error(message)
  }
  if (result.startsWith("WARN:")) {
    await log(ctx.client, "warn", decisionBody(result), { sessionID: input.sessionID, callID: input.callID, command })
  }
}

export const __taskProof = {
  promptText,
  isGitWriteCommand,
  runTaskProof,
  lastPromptBySession,
}

export default {
  id: SERVICE,
  server: async (ctx) => ({
    event: async ({ event }) => {
      if (event?.type === "session.deleted" && event.properties?.sessionID) {
        lastPromptBySession.delete(event.properties.sessionID)
      }
    },
    "chat.message": async (input, output) => handlePrompt(ctx, input, output),
    "tool.execute.before": async (input, output) => handleTool(ctx, input, output),
  }),
}
