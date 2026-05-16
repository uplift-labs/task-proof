import { existsSync } from "node:fs"
import { mkdir, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { parsePayload, stringField } from "../lib/payload.ts"
import type { EnvMap } from "../lib/process.ts"

export interface GuardOptions {
  cwd?: string
  env?: EnvMap
}

export async function proofRecommend(input: string, options: GuardOptions = {}): Promise<string> {
  const payload = parsePayload(input)
  const userMessage = stringField(payload, "prompt")
  if (!userMessage) return ""

  const wordCount = userMessage.trim() ? userMessage.trim().split(/\s+/).length : 0
  if (wordCount < 5) return ""

  const sessionId = stringField(payload, "session_id") || "unknown"
  const tmpRoot = options.env?.TMPDIR || "/tmp"
  const marker = join(tmpRoot, `task-proof-recommend-${sessionId}`)
  if (existsSync(marker)) return ""

  try {
    await mkdir(dirname(marker), { recursive: true })
    await writeFile(marker, "", { flag: "wx" })
  } catch {
    // Recommendation fatigue control is best-effort; never suppress the guard on filesystem errors.
  }

  const message = "[task-proof] Assess this task: does it have 3+ acceptance criteria, touch 3+ files, or involve a multi-step refactor? If yes, run the task-proof skill (structured spec freeze, build, evidence pack, independent verification, fix loop). If the task is simple, proceed normally."
  return `WARN:${message}`
}
