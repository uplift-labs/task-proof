export type DecisionTag = "BLOCK" | "ASK" | "WARN"

export interface TaggedDecision {
  tag: DecisionTag
  body: string
}

const priorities: Record<DecisionTag, number> = {
  BLOCK: 3,
  ASK: 2,
  WARN: 1,
}

export function parseDecision(output: string): TaggedDecision | null {
  const trimmed = output.trim()
  const match = /^(BLOCK|ASK|WARN):(.*)$/s.exec(trimmed)
  if (!match) return null
  return { tag: match[1] as DecisionTag, body: match[2] ?? "" }
}

export function serializeDecision(decision: TaggedDecision | null): string {
  if (!decision) return ""
  return `${decision.tag}:${decision.body}`
}

export function disabledEnvName(guardName: string): string {
  return `TASK_PROOF_DISABLE_${guardName.replaceAll("-", "_").toUpperCase()}`
}

export function selectHigherPriority(current: TaggedDecision | null, candidate: TaggedDecision): TaggedDecision {
  if (!current) return candidate
  if (priorities[candidate.tag] > priorities[current.tag]) return candidate
  if (current.tag === "WARN" && candidate.tag === "WARN") {
    return { tag: "WARN", body: `${current.body} | ${candidate.body}` }
  }
  return current
}
