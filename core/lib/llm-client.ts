import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { commandAvailable, type EnvMap, runProcess } from "./process.ts"

export interface LlmOptions {
  cwd?: string
  env?: EnvMap
}

export interface LlmResult {
  status: number
  stdout: string
  stderr: string
}

export async function runLlm(prompt: string, options: LlmOptions = {}): Promise<LlmResult> {
  if (!prompt) return { status: 1, stdout: "", stderr: "llm-client: empty prompt\n" }

  const env = options.env ?? process.env
  const override = env.TASK_PROOF_LLM_CMD
  if (override) {
    const result = await runProcess(override, [], {
      cwd: options.cwd,
      env,
      input: prompt,
      shell: true,
    })
    return { status: result.status, stdout: result.stdout, stderr: result.stderr }
  }

  const backend = env.TASK_PROOF_LLM_BACKEND ?? ""
  if (backend === "opencode") return runOpencodeBackend(prompt, { ...options, requested: true })
  if (backend) {
    return {
      status: 1,
      stdout: "",
      stderr: `llm-client: unknown TASK_PROOF_LLM_BACKEND=${backend}\n`,
    }
  }

  if (await commandAvailable("opencode", env)) return runOpencodeBackend(prompt, options)

  return {
    status: 1,
    stdout: "",
    stderr: "llm-client: no LLM backend available - set TASK_PROOF_LLM_CMD or install opencode CLI\n",
  }
}

async function runOpencodeBackend(
  prompt: string,
  options: LlmOptions & { requested?: boolean },
): Promise<LlmResult> {
  if (!(await commandAvailable("opencode", options.env))) {
    const prefix = options.requested ? "opencode backend requested but " : ""
    return {
      status: 1,
      stdout: "",
      stderr: `llm-client: ${prefix}opencode CLI is not available\n`,
    }
  }

  const dir = await mkdtemp(join(tmpdir(), "task-proof-"))
  const promptFile = join(dir, "prompt.txt")
  try {
    await writeFile(promptFile, prompt, "utf8")
    const args = ["run", "--pure", "--file", promptFile]
    const model = options.env?.TASK_PROOF_OPENCODE_MODEL
    if (model) args.push("--model", model)
    args.push("Read the attached prompt file and answer exactly as requested.")

    const result = process.platform === "win32"
      ? await runProcess(formatWindowsCommand("opencode", args), [], {
          cwd: options.cwd,
          env: { ...options.env, TASK_PROOF_DISABLED: "1" },
          shell: true,
        })
      : await runProcess("opencode", args, {
          cwd: options.cwd,
          env: { ...options.env, TASK_PROOF_DISABLED: "1" },
        })
    return {
      status: result.status === 0 ? 0 : 2,
      stdout: result.stdout,
      stderr: result.stderr,
    }
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
}

function formatWindowsCommand(command: string, args: readonly string[]): string {
  return [command, ...args].map(quoteWindowsArg).join(" ")
}

function quoteWindowsArg(value: string): string {
  if (/^[A-Za-z0-9_./:=+-]+$/.test(value)) return value
  return `"${value.replaceAll('"', '""')}"`
}
