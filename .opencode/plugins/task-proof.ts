import { existsSync } from "node:fs"
import { pathToFileURL } from "node:url"
import { join } from "node:path"

const SERVICE = "task-proof.opencode"
const DEFAULT_PROMPT_TIMEOUT_MS = 5000
const DEFAULT_TOOL_TIMEOUT_MS = 140000
const lastPromptBySession = new Map<string, string>()

type LogLevel = "debug" | "info" | "warn" | "error"
type EnvMap = Record<string, string | undefined>

interface PluginContext {
  client?: { app?: { log?: (input: { body: unknown }) => Promise<void> } }
  directory?: string
  worktree?: string
  project?: { directory?: string; worktree?: string; root?: string }
}

interface HookInput {
  sessionID?: string
  callID?: string
  tool?: string
  [key: string]: unknown
}

interface HookOutput {
  args?: Record<string, unknown>
  parts?: unknown[]
  message?: { system?: string }
}

interface TaskProofModule {
  runTaskProofGroup: (group: string, input: string, options?: { cwd?: string; env?: EnvMap }) => Promise<string>
}

function contextRoot(ctx: PluginContext): string {
  if (process.env.TASK_PROOF_ROOT) return process.env.TASK_PROOF_ROOT
  const base = ctx.project?.worktree || ctx.project?.directory || ctx.project?.root || ctx.worktree || ctx.directory || process.cwd()
  return join(base, ".uplift", "task-proof")
}

function contextCwd(ctx: PluginContext): string {
  return ctx.project?.worktree || ctx.project?.directory || ctx.project?.root || ctx.worktree || ctx.directory || process.cwd()
}

function promptText(parts: unknown): string {
  if (!Array.isArray(parts)) return ""
  return parts
    .map((part) => {
      if (!part || typeof part !== "object") return ""
      const record = part as Record<string, unknown>
      if (typeof record.text === "string") return record.text
      if (typeof record.content === "string") return record.content
      return ""
    })
    .filter(Boolean)
    .join("\n")
}

function isGitWriteCommand(command: string): boolean {
  return /\bgit\s+(?:push|commit)\b/.test(command)
}

function appendSystem(output: HookOutput, message: string): void {
  output.message ??= {}
  const current = output.message.system
  output.message.system = [current, message].filter(Boolean).join("\n\n")
}

async function log(client: PluginContext["client"], level: LogLevel, message: string, extra: Record<string, unknown> = {}): Promise<void> {
  try {
    await client?.app?.log?.({ body: { service: SERVICE, level, message, extra } })
  } catch {
    // Logging must never change hook behavior.
  }
}

async function runTaskProof(root: string, group: string, payload: Record<string, unknown>, timeoutMs: number, envPatch: EnvMap = {}): Promise<string> {
  const runner = join(root, "core", "cmd", "task-proof-run.ts")
  if (!existsSync(runner)) return ""

  try {
    const mod = (await import(pathToFileURL(runner).href)) as TaskProofModule
    const run = mod.runTaskProofGroup(group, JSON.stringify(payload), {
      cwd: typeof payload.cwd === "string" ? payload.cwd : process.cwd(),
      env: { ...process.env, ...envPatch },
    })
    const timeout = new Promise<string>((resolve) => setTimeout(() => resolve(""), timeoutMs))
    return (await Promise.race([run, timeout])).trim()
  } catch {
    return ""
  }
}

function decisionBody(result: string): string {
  return result.replace(/^(BLOCK|ASK|WARN):/, "")
}

async function handlePrompt(ctx: PluginContext, input: HookInput, output: HookOutput): Promise<void> {
  const prompt = promptText(output.parts)
  if (!prompt) return

  const sessionID = String(input.sessionID ?? "")
  lastPromptBySession.set(sessionID, prompt.slice(0, 2000))

  const payload = {
    session_id: sessionID,
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

async function handleTool(ctx: PluginContext, input: HookInput, output: HookOutput): Promise<void> {
  if (input.tool !== "bash") return

  const command = String(output.args?.command ?? "")
  if (!command || !isGitWriteCommand(command)) return

  const sessionID = String(input.sessionID ?? "")
  const payload = {
    session_id: sessionID,
    cwd: contextCwd(ctx),
    hook_event_name: "PreToolUse",
    tool_name: "bash",
    command,
    task_description: lastPromptBySession.get(sessionID) || "",
    tool_input: { command },
  }

  const envPatch: EnvMap = {}
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
      await log(ctx.client, "warn", message, { sessionID, callID: input.callID, command })
      return
    }
    throw new Error(message)
  }
  if (result.startsWith("WARN:")) {
    await log(ctx.client, "warn", decisionBody(result), { sessionID, callID: input.callID, command })
  }
}

export async function createTaskProofHooks(ctx: PluginContext): Promise<Record<string, unknown>> {
  return {
    event: async ({ event }: { event?: { type?: string; properties?: { sessionID?: string } } }) => {
      if (event?.type === "session.deleted" && event.properties?.sessionID) {
        lastPromptBySession.delete(event.properties.sessionID)
      }
    },
    "chat.message": async (input: HookInput, output: HookOutput) => handlePrompt(ctx, input, output),
    "tool.execute.before": async (input: HookInput, output: HookOutput) => handleTool(ctx, input, output),
  }
}

export const __taskProof = {
  promptText,
  isGitWriteCommand,
  runTaskProof,
  lastPromptBySession,
}

export default async function taskProofPlugin(ctx: PluginContext): Promise<Record<string, unknown>> {
  return createTaskProofHooks(ctx)
}
