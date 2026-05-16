import { spawn } from "node:child_process"

export type EnvMap = Record<string, string | undefined>

export interface RunProcessOptions {
  cwd?: string
  env?: EnvMap
  input?: string
  shell?: boolean
  timeoutMs?: number
}

export interface RunProcessResult {
  status: number
  stdout: string
  stderr: string
  error?: NodeJS.ErrnoException
  timedOut: boolean
}

export function mergedEnv(env?: EnvMap): NodeJS.ProcessEnv {
  return { ...process.env, ...env }
}

export function runProcess(
  command: string,
  args: readonly string[] = [],
  options: RunProcessOptions = {},
): Promise<RunProcessResult> {
  return new Promise((resolve) => {
    let stdout = ""
    let stderr = ""
    let settled = false
    let timedOut = false

    const child = spawn(command, [...args], {
      cwd: options.cwd,
      env: mergedEnv(options.env),
      shell: options.shell,
      windowsHide: true,
    })

    const finish = (result: RunProcessResult) => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      resolve(result)
    }

    const timer = options.timeoutMs
      ? setTimeout(() => {
          timedOut = true
          child.kill()
          finish({ status: 124, stdout, stderr, timedOut })
        }, options.timeoutMs)
      : undefined

    child.stdout?.on("data", (chunk: Buffer | string) => {
      stdout += String(chunk)
    })
    child.stderr?.on("data", (chunk: Buffer | string) => {
      stderr += String(chunk)
    })
    child.on("error", (error: NodeJS.ErrnoException) => {
      finish({ status: 127, stdout, stderr: stderr || error.message, error, timedOut })
    })
    child.on("close", (code) => {
      finish({ status: code ?? (timedOut ? 124 : 1), stdout, stderr, timedOut })
    })

    if (options.input !== undefined) child.stdin?.end(options.input)
    else child.stdin?.end()
  })
}

export async function commandAvailable(command: string, env?: EnvMap): Promise<boolean> {
  const result = process.platform === "win32"
    ? await runProcess(`${command} --version`, [], { env, shell: true, timeoutMs: 5000 })
    : await runProcess(command, ["--version"], { env, timeoutMs: 5000 })
  return result.error?.code !== "ENOENT"
}
