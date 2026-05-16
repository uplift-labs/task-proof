import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { pathToFileURL } from "node:url"
import { runProcess } from "./core/lib/process.ts"

interface InstallModule {
  runInstall: (argv: readonly string[], options?: { log?: (message: string) => void }) => Promise<void>
}

async function main(): Promise<void> {
  const repoUrl = "https://github.com/uplift-labs/task-proof.git"
  const version = process.env.TASK_PROOF_VERSION || "main"
  const target = process.cwd()
  const passthroughArgs = ["--target", target, ...process.argv.slice(2)]
  const tempDir = await mkdtemp(join(tmpdir(), "task-proof-remote-"))

  try {
    process.stdout.write(`[remote-install] cloning task-proof@${version}...\n`)
    const cloneTarget = join(tempDir, "task-proof")
    const clone = await runProcess("git", ["clone", "--depth", "1", "--branch", version, repoUrl, cloneTarget])
    if (clone.status !== 0) {
      process.stderr.write(`failed to clone ${repoUrl}\n${clone.stderr}`)
      process.exit(1)
    }

    const installer = (await import(pathToFileURL(join(cloneTarget, "install.ts")).href)) as InstallModule
    await installer.runInstall(passthroughArgs)
  } finally {
    await rm(tempDir, { recursive: true, force: true })
  }
}

void main()
