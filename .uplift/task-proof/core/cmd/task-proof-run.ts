import { freshVerify } from "../guards/fresh-verify.ts"
import { proofRecommend } from "../guards/proof-recommend.ts"
import { disabledEnvName, parseDecision, selectHigherPriority, serializeDecision, type TaggedDecision } from "../lib/decision.ts"
import type { EnvMap } from "../lib/process.ts"
import { resolve } from "node:path"
import { fileURLToPath } from "node:url"

export interface RunnerOptions {
  cwd?: string
  env?: EnvMap
}

type GuardName = "fresh-verify" | "proof-recommend"
type GuardFn = (input: string, options: RunnerOptions) => Promise<string>

const guards: Record<GuardName, GuardFn> = {
  "fresh-verify": freshVerify,
  "proof-recommend": proofRecommend,
}

const groups: Record<string, GuardName[]> = {
  "pre-commit": ["fresh-verify"],
  "prompt-recommend": ["proof-recommend"],
}

export async function runTaskProofGroup(group: string, input: string, options: RunnerOptions = {}): Promise<string> {
  const env = options.env ?? process.env
  if (env.CI === "true" || env.TASK_PROOF_DISABLED === "1") return ""

  const guardNames = groups[group]
  if (!guardNames) return ""

  let best: TaggedDecision | null = null
  for (const guardName of guardNames) {
    if (env[disabledEnvName(guardName)] === "1") continue

    try {
      const output = await guards[guardName](input, { ...options, env })
      const decision = parseDecision(output)
      if (!decision) continue
      if (decision.tag === "BLOCK") return serializeDecision(decision)
      best = selectHigherPriority(best, decision)
    } catch {
      // task-proof is fail-open: a broken guard must never block real work.
    }
  }

  return serializeDecision(best)
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = []
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk))
  return Buffer.concat(chunks).toString("utf8")
}

async function main(): Promise<void> {
  const group = process.argv[2] ?? ""
  if (!group) {
    process.stderr.write("usage: tsx core/cmd/task-proof-run.ts <group>\n")
    process.exit(0)
  }
  const input = await readStdin()
  const result = await runTaskProofGroup(group, input)
  if (result) process.stdout.write(result)
  process.exit(0)
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  void main()
}
