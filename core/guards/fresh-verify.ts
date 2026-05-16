import { runLlm } from "../lib/llm-client.ts"
import { parsePayload, stringField } from "../lib/payload.ts"
import { type EnvMap, runProcess } from "../lib/process.ts"

export interface GuardOptions {
  cwd?: string
  env?: EnvMap
}

export async function freshVerify(input: string, options: GuardOptions = {}): Promise<string> {
  const payload = parsePayload(input)
  const command = stringField(payload, "command")
  if (!command || !isGitWriteCommand(command) || isWipCommand(command)) return ""

  const cwd = stringField(payload, "cwd") || options.cwd || process.cwd()
  const gitRoot = await gitRootFor(cwd, options.env)
  if (!gitRoot) return ""

  const diff = await diffForCommand(command, gitRoot, options.env)
  if (!diff) return ""

  const changedLines = diff.split(/\r?\n/).filter((line) => /^[+-][^+-]/.test(line)).length
  if (changedLines < 3) return ""

  const taskDescription = stringField(payload, "task_description") || "(no task description available - review the diff on its own merits)"
  const budget = Number.parseInt(options.env?.FRESH_VERIFY_BUDGET_LINES ?? "800", 10)
  const diffTruncated = truncateLines(diff, Number.isFinite(budget) && budget > 0 ? budget : 800)
  const prompt = buildPrompt(taskDescription, diffTruncated)

  const verdict = await runLlm(prompt, { cwd: gitRoot, env: options.env })
  if (verdict.status !== 0 || !verdict.stdout.trim()) return ""

  const trimmed = verdict.stdout.replace(/\s+/g, " ").trim()
  if (trimmed.startsWith("PASS")) return ""
  if (trimmed.startsWith("FAIL")) {
    const reason = trimmed.replace(/^FAIL:\s*/, "")
    return `BLOCK:[fresh-verify] independent reviewer FAILED the changes: ${reason}`
  }
  if (trimmed.startsWith("CONCERN")) {
    const note = trimmed.replace(/^CONCERN:\s*/, "")
    return `ASK:[fresh-verify] independent reviewer raised a concern: ${note}`
  }
  return ""
}

export function isGitWriteCommand(command: string): boolean {
  return /\bgit\s+(?:push|commit)\b/.test(command)
}

function isWipCommand(command: string): boolean {
  return /--wip|WIP|wip:|wip\s/.test(command)
}

async function gitRootFor(cwd: string, env?: EnvMap): Promise<string> {
  const result = await runProcess("git", ["rev-parse", "--show-toplevel"], { cwd, env })
  return result.status === 0 ? result.stdout.trim() : ""
}

async function diffForCommand(command: string, gitRoot: string, env?: EnvMap): Promise<string> {
  if (/\bgit\s+push\b/.test(command)) {
    const branch = await runProcess("git", ["-C", gitRoot, "branch", "--show-current"], { env })
    const currentBranch = branch.stdout.trim()
    if (currentBranch) {
      const originDiff = await runProcess("git", ["-C", gitRoot, "diff", `origin/${currentBranch}..HEAD`], { env })
      if (originDiff.stdout.trim()) return originDiff.stdout
    }
    const fallback = await runProcess("git", ["-C", gitRoot, "diff", "HEAD~1"], { env })
    return fallback.stdout
  }

  const cached = await runProcess("git", ["-C", gitRoot, "diff", "--cached"], { env })
  if (cached.stdout.trim()) return cached.stdout
  const unstaged = await runProcess("git", ["-C", gitRoot, "diff"], { env })
  return unstaged.stdout
}

function truncateLines(value: string, budget: number): string {
  const lines = value.split(/\r?\n/)
  if (lines.length <= budget) return value
  return `${lines.slice(0, budget).join("\n")}\n... (diff truncated, ${lines.length} total lines)`
}

function buildPrompt(taskDescription: string, diff: string): string {
  return `You are an independent code reviewer with no prior context. You see only (1) a task description and (2) a diff.

Your job is to surface real risks - NOT to rubber-stamp. Default to CONCERN or FAIL on ambiguity; PASS should be reserved for small, obviously-correct changes.

Flag as FAIL any of:
- Diff does not address the stated task (or task is vague and diff could drift).
- Obvious bugs: off-by-one, wrong condition, null/empty deref, wrong variable name.
- Swallowed errors or silent exception handlers without an explicit reason.
- Security: hardcoded secrets, unsanitized input concatenated into shell/SQL/HTML, unsafe file permissions.
- Deleted tests or assertions weakened without justification in the diff.
- Missing edge cases the diff itself implies (e.g. added an if without its else).

Flag as CONCERN any of:
- New public API with no test.
- Refactor touches unrelated files.
- Magic numbers, TODO comments, commented-out code shipped in the diff.
- Dependencies added without a comment on why.

Reply with EXACTLY one of these three formats, no other text, no preamble:
PASS
FAIL: <one-sentence reason, naming the specific file or line-type if possible>
CONCERN: <one-sentence note>

Task description: ${taskDescription}

Code diff:
${diff}`
}
