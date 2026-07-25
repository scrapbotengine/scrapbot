#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const PROJECTS = [
  { name: "minimal", path: "examples/minimal" },
  { name: "ecs-showcase", path: "examples/ecs-showcase" },
  { name: "sponza", path: "examples/sponza" },
];

function positiveInteger(text, flag) {
  const value = Number.parseInt(text, 10);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error(`${flag} expects a positive integer`);
  }
  return value;
}

export function parseBenchmarkArguments(arguments_) {
  const options = {
    binary: "bin/scrapbot",
    out: path.join(os.tmpdir(), "scrapbot-gpu-benchmarks"),
    warmup: 60,
    frames: 240,
    projects: PROJECTS,
  };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    const value = () => {
      index += 1;
      if (index >= arguments_.length) throw new Error(`${argument} requires a value`);
      return arguments_[index];
    };
    switch (argument) {
      case "--binary":
        options.binary = value();
        break;
      case "--out":
        options.out = value();
        break;
      case "--warmup":
        options.warmup = positiveInteger(value(), argument);
        break;
      case "--frames":
        options.frames = positiveInteger(value(), argument);
        break;
      case "--without-sponza":
        options.projects = PROJECTS.filter((project) => project.name !== "sponza");
        break;
      default:
        throw new Error(`unknown argument: ${argument}`);
    }
  }
  return options;
}

export function assertSafeOutputDirectory(root, output) {
  const resolvedRoot = path.resolve(root);
  const resolvedOutput = path.resolve(output);
  if (resolvedOutput === resolvedRoot || resolvedOutput === path.parse(resolvedOutput).root) {
    throw new Error("benchmark output must be a dedicated directory");
  }
}

export function renderBenchmarkSummary(manifest, sweeps) {
  const lines = [
    "# Scrapbot GPU benchmark",
    "",
    `- Status: **${manifest.status}**`,
    `- Host: \`${manifest.host.platform}/${manifest.host.architecture}\``,
    ...(manifest.adapters?.length > 0
      ? [`- Adapter: ${manifest.adapters.map((adapter) => `\`${adapter}\``).join(", ")}`]
      : []),
    `- Commit: \`${manifest.git_sha || "unknown"}\``,
    `- Samples: ${manifest.warmup_frames} warmup + ${manifest.measured_frames} measured frames`,
    "",
  ];
  for (const sweep of sweeps) {
    lines.push(`## ${sweep.name}`, "", "| Resolution | GPU median | GPU p95 | CPU p95 |", "| --- | ---: | ---: | ---: |");
    for (const point of sweep.report.points) {
      lines.push(
        `| ${point.resolution} | ${point.gpu_frame_median_ms.toFixed(3)} ms | ` +
          `${point.gpu_frame_p95_ms.toFixed(3)} ms | ${point.cpu_active_p95_ms.toFixed(3)} ms |`,
      );
    }
    lines.push("");
  }
  if (manifest.error) lines.push("## Failure", "", `\`${manifest.error}\``, "");
  return `${lines.join("\n")}\n`;
}

function runSweep(root, options, project) {
  const output = path.join(options.out, project.name);
  const command = spawnSync(
    process.execPath,
    [
      path.join(root, "tools/profile_resolution_sweep.mjs"),
      project.path,
      "--binary",
      path.resolve(root, options.binary),
      "--out",
      output,
      "--warmup",
      String(options.warmup),
      "--frames",
      String(options.frames),
      "--json",
    ],
    {
      cwd: root,
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
    },
  );
  fs.writeFileSync(path.join(options.out, `${project.name}.stdout.log`), command.stdout ?? "");
  fs.writeFileSync(path.join(options.out, `${project.name}.stderr.log`), command.stderr ?? "");
  if (command.error) throw command.error;
  if (command.status !== 0) {
    throw new Error(`${project.name} resolution sweep exited with ${command.status}`);
  }
  const report = JSON.parse(fs.readFileSync(path.join(output, "sweep.json"), "utf8"));
  const firstProfile = JSON.parse(fs.readFileSync(report.points[0].report, "utf8"));
  const backend = firstProfile.metadata?.adapter_backend ?? "unknown backend";
  const device = firstProfile.metadata?.adapter_device ?? "unknown device";
  return {
    report,
    adapter: `${backend}: ${device}`,
  };
}

export function benchmarkManifest(options, status, projects, error = "", adapters = []) {
  return {
    schema_version: 1,
    status,
    host: {
      platform: process.platform,
      architecture: process.arch,
    },
    git_sha: process.env.GITHUB_SHA ?? "",
    workflow_run_id: process.env.GITHUB_RUN_ID ?? "",
    warmup_frames: options.warmup,
    measured_frames: options.frames,
    projects,
    adapters,
    ...(error ? { error } : {}),
  };
}

export function main(arguments_ = process.argv.slice(2)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  let options;
  try {
    options = parseBenchmarkArguments(arguments_);
  } catch (error) {
    console.error(error.message);
    return 1;
  }
  options.out = path.resolve(root, options.out);
  try {
    assertSafeOutputDirectory(root, options.out);
  } catch (error) {
    console.error(error.message);
    return 1;
  }
  fs.rmSync(options.out, { recursive: true, force: true });
  fs.mkdirSync(options.out, { recursive: true });

  const sweeps = [];
  try {
    for (const project of options.projects) {
      console.error(`Benchmarking ${project.name}...`);
      sweeps.push({
        name: project.name,
        ...runSweep(root, options, project),
      });
    }
    const adapters = [...new Set(sweeps.map((sweep) => sweep.adapter))];
    const manifest = benchmarkManifest(
      options,
      "passed",
      sweeps.map((sweep) => sweep.name),
      "",
      adapters,
    );
    fs.writeFileSync(
      path.join(options.out, "manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    fs.writeFileSync(
      path.join(options.out, "summary.md"),
      renderBenchmarkSummary(manifest, sweeps),
    );
    console.log(`GPU benchmark bundle: ${options.out}`);
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const manifest = benchmarkManifest(
      options,
      "failed",
      sweeps.map((sweep) => sweep.name),
      message,
      [...new Set(sweeps.map((sweep) => sweep.adapter))],
    );
    fs.writeFileSync(
      path.join(options.out, "manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    fs.writeFileSync(
      path.join(options.out, "summary.md"),
      renderBenchmarkSummary(manifest, sweeps),
    );
    console.error(`GPU benchmark failed: ${message}`);
    console.error(`partial bundle preserved at ${options.out}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  process.exitCode = main();
}
