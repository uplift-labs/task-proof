export interface NormalizedPayload {
  session_id?: string
  cwd?: string
  command?: string
  task_description?: string
  prompt?: string
  [key: string]: unknown
}

export function parsePayload(input: string): NormalizedPayload | null {
  try {
    const parsed: unknown = JSON.parse(input)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
    return parsed as NormalizedPayload
  } catch {
    return null
  }
}

export function stringField(payload: NormalizedPayload | null, key: keyof NormalizedPayload): string {
  const value = payload?.[key]
  return typeof value === "string" ? value : ""
}
