import { runLlm } from "./llm-client.ts"

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = []
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk))
  return Buffer.concat(chunks).toString("utf8")
}

async function main(): Promise<void> {
  const prompt = process.argv.length >= 3 ? (process.argv[2] ?? "") : await readStdin()
  const result = await runLlm(prompt)

  if (result.stdout) process.stdout.write(result.stdout)
  if (result.stderr) process.stderr.write(result.stderr)

  process.exit(result.status)
}

void main()
