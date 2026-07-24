#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

import { summarizeRenderProfile } from "./analyze_render_profile.mjs";

const DEFAULT_RESOLUTIONS = ["960x540", "1280x720", "1920x1080"];

function parsePositiveInteger(value, flag) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`${flag} expects a positive integer`);
  }
  return parsed;
}

function parseResolution(value) {
  const match = /^([1-9]\d*)x([1-9]\d*)$/.exec(value);
  if (!match) {
    throw new Error(`invalid resolution ${value}; expected WIDTHxHEIGHT`);
  }
  return {
    text: value,
    width: Number.parseInt(match[1], 10),
    height: Number.parseInt(match[2], 10),
  };
}

export function parseSweepArguments(argv) {
  const options = {
    project: "",
    binary: "bin/scrapbot",
    out: "profile-sweep",
    warmup: 60,
    frames: 240,
    resolutions: [],
    editor: false,
    cpu_culling: false,
    ui_script: "",
    json: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`${argument} requires a value`);
      }
      return argv[index];
    };
    switch (argument) {
      case "--binary":
        options.binary = value();
        break;
      case "--out":
        options.out = value();
        break;
      case "--warmup":
        options.warmup = parsePositiveInteger(value(), argument);
        break;
      case "--frames":
        options.frames = parsePositiveInteger(value(), argument);
        break;
      case "--resolution":
        options.resolutions.push(parseResolution(value()));
        break;
      case "--ui-script":
        options.ui_script = value();
        break;
      case "--editor":
        options.editor = true;
        break;
      case "--cpu-culling":
        options.cpu_culling = true;
        break;
      case "--json":
        options.json = true;
        break;
      case "--help":
        options.help = true;
        break;
      default:
        if (argument.startsWith("-")) {
          throw new Error(`unknown option ${argument}`);
        }
        if (options.project !== "") {
          throw new Error("expected exactly one project path");
        }
        options.project = argument;
    }
  }
  if (options.resolutions.length === 0) {
    options.resolutions = DEFAULT_RESOLUTIONS.map(parseResolution);
  }
  return options;
}

function usage() {
  console.log(`Usage:
  node tools/profile_resolution_sweep.mjs <project> [options]

Options:
  --binary <path>             Scrapbot executable (default: bin/scrapbot)
  --out <directory>           Sweep artifact directory
  --warmup <frames>           Warmup frames per resolution
  --frames <frames>           Measured frames per resolution
  --resolution <WIDTHxHEIGHT> Repeat to replace the default 540p/720p/1080 sweep
  --editor                    Include editor rendering
  --cpu-culling               Use the CPU culling reference path
  --ui-script <path>          Replay semantic UI actions
  --json                      Emit the sweep report to stdout`);
}

function runProfile(options, resolution) {
  const directory = path.join(options.out, resolution.text);
  const args = [
    "profile",
    options.project,
    "--warmup",
    String(options.warmup),
    "--frames",
    String(options.frames),
    "--resolution",
    resolution.text,
    "--out",
    directory,
    "--json",
  ];
  if (options.editor) args.push("--editor");
  if (options.cpu_culling) args.push("--cpu-culling");
  if (options.ui_script) args.push("--ui-script", options.ui_script);

  const command = spawnSync(options.binary, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (command.error) throw command.error;
  if (command.status !== 0) {
    throw new Error(
      `${options.binary} ${args.join(" ")} failed:\n${command.stderr || command.stdout}`,
    );
  }
  const envelope = JSON.parse(command.stdout);
  if (!envelope.ok) {
    throw new Error(`profile failed: ${JSON.stringify(envelope.diagnostics)}`);
  }
  const reportPath = path.resolve(envelope.result.report);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const summary = summarizeRenderProfile(report, reportPath);
  return {
    resolution: resolution.text,
    width: resolution.width,
    height: resolution.height,
    megapixels: (resolution.width * resolution.height) / 1_000_000,
    report: reportPath,
    overview: path.resolve(envelope.result.overview),
    cpu_active_p95_ms: summary.cpu_active.p95_ms,
    gpu_frame_median_ms: summary.gpu_frame.median_ms,
    gpu_frame_p95_ms: summary.gpu_frame.p95_ms,
    gpu_frame_max_ms: summary.gpu_frame.max_ms,
    gpu_p95_ms_per_megapixel: summary.gpu_p95_ms_per_megapixel,
    gpu_passes_by_p95: summary.gpu_passes_by_p95,
    counter_totals: summary.counter_totals,
  };
}

export function main(argv = process.argv.slice(2)) {
  try {
    const options = parseSweepArguments(argv);
    if (options.help) {
      usage();
      return 0;
    }
    if (options.project === "") {
      usage();
      return 1;
    }
    fs.mkdirSync(options.out, { recursive: true });
    const points = [];
    for (const resolution of options.resolutions) {
      if (!options.json) {
        console.error(`Profiling ${resolution.text}...`);
      }
      points.push(runProfile(options, resolution));
    }
    const report = {
      schema_version: 1,
      project: path.resolve(options.project),
      binary: path.resolve(options.binary),
      warmup_frames: options.warmup,
      measured_frames: options.frames,
      editor: options.editor,
      cpu_culling: options.cpu_culling,
      ui_script: options.ui_script ? path.resolve(options.ui_script) : "",
      points,
    };
    const reportPath = path.join(options.out, "sweep.json");
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    if (options.json) {
      console.log(JSON.stringify({ ...report, report: path.resolve(reportPath) }));
    } else {
      console.log("Resolution      GPU p95     ms/MP      CPU p95");
      for (const point of points) {
        console.log(
          `${point.resolution.padEnd(15)} ` +
            `${point.gpu_frame_p95_ms.toFixed(3).padStart(7)} ms  ` +
            `${point.gpu_p95_ms_per_megapixel.toFixed(3).padStart(7)}  ` +
            `${point.cpu_active_p95_ms.toFixed(3).padStart(7)} ms`,
        );
      }
      console.log(`Report: ${path.resolve(reportPath)}`);
    }
    return 0;
  } catch (error) {
    console.error(error.message);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}
