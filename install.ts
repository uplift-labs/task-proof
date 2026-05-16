import { cp, mkdir, readdir, rm, stat, writeFile } from "node:fs/promises"
import { existsSync } from "node:fs"
import { dirname, join, relative } from "node:path"
import { fileURLToPath } from "node:url"

export interface InstallOptions {
  log?: (message: string) => void
}

interface ParsedArgs {
  target: string
  prefix: string
}

const scriptDir = dirname(fileURLToPath(import.meta.url))

export async function runInstall(argv: readonly string[] = process.argv.slice(2), options: InstallOptions = {}): Promise<void> {
  const log = options.log ?? ((message: string) => process.stdout.write(`${message}\n`))
  const parsed = parseArgs(argv)
  const target = parsed.target || process.cwd()

  if (!isGitRepo(target)) throw new Error(`not a git repo: ${target}`)

  const installRoot = join(target, parsed.prefix, "task-proof")
  await mkdir(join(installRoot, "core", "lib"), { recursive: true })
  await mkdir(join(installRoot, "core", "cmd"), { recursive: true })
  await mkdir(join(installRoot, "core", "guards"), { recursive: true })
  await rm(join(installRoot, "adapter"), { recursive: true, force: true })
  await removeMatching(join(installRoot, "core"), [".sh", ".js", ".py"])

  log(`[install] copying TypeScript core to ${join(installRoot, "core")}`)
  await syncFiles(join(scriptDir, "core", "lib"), join(installRoot, "core", "lib"), ".ts")
  await syncFiles(join(scriptDir, "core", "cmd"), join(installRoot, "core", "cmd"), ".ts")
  await syncFiles(join(scriptDir, "core", "guards"), join(installRoot, "core", "guards"), ".ts")

  const opencodeDir = join(target, ".opencode")
  const opencodePluginDir = join(opencodeDir, "plugins")
  await mkdir(opencodePluginDir, { recursive: true })
  const opencodeGitignore = join(opencodeDir, ".gitignore")
  if (!existsSync(opencodeGitignore)) {
    await writeFile(opencodeGitignore, "node_modules/\npackage.json\npackage-lock.json\nbun.lock\n", "utf8")
  }

  log(`[install] copying OpenCode TypeScript plugin to ${opencodePluginDir}`)
  await rm(join(opencodePluginDir, "task-proof.js"), { force: true })
  await copyFiles(join(scriptDir, "adapters", "opencode", "plugins"), opencodePluginDir, ".ts")

  const skillSrc = join(scriptDir, "adapters", "opencode", "skills", "task-proof")
  const skillDest = join(opencodeDir, "skills", "task-proof")
  if (existsSync(skillSrc)) {
    await mkdir(skillDest, { recursive: true })
    await copyFiles(skillSrc, skillDest, ".md")
    log(`[install] OpenCode skill installed at ${skillDest}`)
  }

  log("[install] done.")
  log(`  core installed at: ${join(installRoot, "core")}`)
  log(`  opencode plugin: ${opencodePluginDir}`)
  log("")
  log(`  Commit ${installRoot}/ and any host config/skill directories created`)
  log("  (.opencode/) so that the proof loop is available in worktrees.")
}

function parseArgs(argv: readonly string[]): ParsedArgs {
  const parsed: ParsedArgs = { target: "", prefix: ".uplift" }
  for (let index = 0; index < argv.length; ) {
    const arg = argv[index]
    if (arg === "--target") {
      const value = argv[index + 1]
      if (!value) throw new Error("missing value for --target")
      parsed.target = value
      index += 2
      continue
    }
    if (arg === "--prefix") {
      const value = argv[index + 1]
      if (!value) throw new Error("missing value for --prefix")
      parsed.prefix = value
      index += 2
      continue
    }
    if (arg === "-h" || arg === "--help") {
      process.stdout.write("Usage: npx tsx install.ts [--target <repo-dir>] [--prefix <dir>]\n")
      process.exit(0)
    }
    throw new Error(`unknown arg: ${arg}`)
  }
  return parsed
}

function isGitRepo(target: string): boolean {
  return existsSync(join(target, ".git"))
}

async function syncFiles(srcDir: string, destDir: string, extension: string): Promise<void> {
  await mkdir(destDir, { recursive: true })
  await removeMatching(destDir, [extension])
  await copyFiles(srcDir, destDir, extension)
}

async function copyFiles(srcDir: string, destDir: string, extension: string): Promise<void> {
  const entries = await readdir(srcDir)
  const files = entries.filter((entry) => entry.endsWith(extension))
  if (files.length === 0) throw new Error(`install: no ${extension} files in ${srcDir}`)
  await mkdir(destDir, { recursive: true })
  await Promise.all(files.map((file) => cp(join(srcDir, file), join(destDir, file))))
}

async function removeMatching(root: string, extensions: readonly string[]): Promise<void> {
  if (!existsSync(root)) return
  const info = await stat(root)
  if (!info.isDirectory()) return
  const entries = await readdir(root, { withFileTypes: true })
  await Promise.all(entries.map(async (entry) => {
    const fullPath = join(root, entry.name)
    if (entry.isDirectory()) {
      await removeMatching(fullPath, extensions)
      return
    }
    if (extensions.some((extension) => entry.name.endsWith(extension))) {
      await rm(fullPath, { force: true })
    }
  }))
}

async function main(): Promise<void> {
  try {
    await runInstall()
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`)
    process.exit(1)
  }
}

if (process.argv[1] && relative(fileURLToPath(import.meta.url), process.argv[1]) === "") {
  void main()
}
