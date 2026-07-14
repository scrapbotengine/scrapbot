import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: null,
    ...options,
  });

  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    const stderr = result.stderr?.toString().trim();
    throw new Error(stderr || `${command} exited with status ${result.status}`);
  }
  return result.stdout;
}

try {
  const formatDirectory = mkdtempSync(join(tmpdir(), "scrapbot-odinfmt-"));
  const formatPath = join(formatDirectory, "staged.odin");
  const configPath = resolve("odinfmt.json");
  process.on("exit", () => rmSync(formatDirectory, { force: true, recursive: true }));

  const names = run("git", [
    "diff",
    "--cached",
    "--name-only",
    "--diff-filter=ACMR",
    "-z",
    "--",
    "*.odin",
  ]);
  const paths = names
    .toString()
    .split("\0")
    .filter(Boolean);
  const unformatted = [];

  for (const path of paths) {
    const staged = run("git", ["show", `:${path}`]);
    writeFileSync(formatPath, staged);
    run("odinfmt", [formatPath, `-config:${configPath}`, "-w"]);
    const formatted = readFileSync(formatPath);
    if (!staged.equals(formatted)) {
      unformatted.push(path);
    }
  }

  if (unformatted.length > 0) {
    console.error("Staged Odin files are not formatted:");
    for (const path of unformatted) {
      console.error(`  ${path}`);
    }
    console.error("Run odinfmt <path> -w, then stage the formatted files.");
    process.exitCode = 1;
  }
} catch (error) {
  console.error(`Unable to check staged Odin formatting: ${error.message}`);
  process.exitCode = 1;
}
