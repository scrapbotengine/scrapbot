#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

import { summarizeRenderProfile } from "./analyze_render_profile.mjs";

export const DEFAULT_FEATURES = [
  "automatic-exposure",
  "temporal-antialiasing",
  "fast-antialiasing",
  "ambient-occlusion",
  "screen-space-reflections",
  "bloom",
  "volumetric-fog",
];

function parsePositiveInteger(value, flag) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`${flag} expects a positive integer`);
  }
  return parsed;
}

function parseResolution(value) {
  if (!/^([1-9]\d*)x([1-9]\d*)$/.test(value)) {
    throw new Error(`invalid resolution ${value}; expected WIDTHxHEIGHT`);
  }
  return value;
}

export function parseFeatureSweepArguments(argv) {
  const options = {
    project: "",
    binary: "bin/scrapbot",
    out: "profile-features",
    warmup: 60,
    frames: 240,
    resolution: "1920x1080",
    features: [],
    editor: false,
    cpu_culling: false,
    ui_script: "",
    json: false,
    help: false,
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
        options.resolution = parseResolution(value());
        break;
      case "--feature": {
        const feature = value();
        if (!DEFAULT_FEATURES.includes(feature)) {
          throw new Error(`unknown render feature ${feature}`);
        }
        if (!options.features.includes(feature)) {
          options.features.push(feature);
        }
        break;
      }
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
  if (options.features.length === 0) {
    options.features = [...DEFAULT_FEATURES];
  }
  return options;
}

function usage() {
  console.log(`Usage:
  node tools/profile_feature_sweep.mjs <project> [options]

Options:
  --binary <path>             Scrapbot executable (default: bin/scrapbot)
  --out <directory>           Feature-sweep artifact directory
  --warmup <frames>           Warmup frames per variant
  --frames <frames>           Measured frames per variant
  --resolution <WIDTHxHEIGHT> Physical render resolution (default: 1920x1080)
  --feature <name>            Repeat to test selected features only
  --editor                    Include editor rendering
  --cpu-culling               Use the CPU culling reference path
  --ui-script <path>          Replay semantic UI actions
  --json                      Emit the sweep report to stdout`);
}

export function profileArguments(options, disabledFeatures, directory) {
  const args = [
    "profile",
    options.project,
    "--warmup",
    String(options.warmup),
    "--frames",
    String(options.frames),
    "--resolution",
    options.resolution,
    "--out",
    directory,
    "--json",
  ];
  if (disabledFeatures.length > 0) {
    args.push("--disabled-features", disabledFeatures.join(","));
  }
  if (options.editor) args.push("--editor");
  if (options.cpu_culling) args.push("--cpu-culling");
  if (options.ui_script) args.push("--ui-script", options.ui_script);
  return args;
}

function runVariant(options, name, disabledFeatures) {
  const directory = path.join(options.out, name);
  const args = profileArguments(options, disabledFeatures, directory);
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
    name,
    disabled_features: disabledFeatures,
    report: reportPath,
    overview: path.resolve(envelope.result.overview),
    gpu_frame_median_ms: summary.gpu_frame.median_ms,
    gpu_frame_p95_ms: summary.gpu_frame.p95_ms,
    gpu_frame_max_ms: summary.gpu_frame.max_ms,
    cpu_active_p95_ms: summary.cpu_active.p95_ms,
    gpu_passes_by_p95: summary.gpu_passes_by_p95,
  };
}

function featureCost(baseline, variant) {
  const cost = baseline.gpu_frame_p95_ms - variant.gpu_frame_p95_ms;
  return {
    ...variant,
    estimated_gpu_p95_cost_ms: cost,
    estimated_gpu_p95_cost_percent:
      baseline.gpu_frame_p95_ms > 0 ? (cost / baseline.gpu_frame_p95_ms) * 100 : 0,
  };
}

export function main(argv = process.argv.slice(2)) {
  try {
    const options = parseFeatureSweepArguments(argv);
    if (options.help) {
      usage();
      return 0;
    }
    if (options.project === "") {
      usage();
      return 1;
    }
    if (
      fs.existsSync(options.out) &&
      fs.readdirSync(options.out, { withFileTypes: true }).length > 0
    ) {
      throw new Error(`output directory must be empty: ${options.out}`);
    }
    fs.mkdirSync(options.out, { recursive: true });
    let baseline = null;
    const variants = [];
    for (const [index, feature] of options.features.entries()) {
      if (!options.json) console.error(`Profiling reference for ${feature}...`);
      const reference = runVariant(
        options,
        `reference-${String(index + 1).padStart(2, "0")}-${feature}`,
        [],
      );
      baseline ??= reference;
      if (!options.json) console.error(`Profiling without ${feature}...`);
      const variant = featureCost(
        reference,
        runVariant(options, `without-${feature}`, [feature]),
      );
      variants.push({
        ...variant,
        reference_report: reference.report,
        reference_gpu_frame_p95_ms: reference.gpu_frame_p95_ms,
      });
    }
    variants.sort(
      (left, right) =>
        right.estimated_gpu_p95_cost_ms - left.estimated_gpu_p95_cost_ms,
    );
    const report = {
      schema_version: 1,
      project: path.resolve(options.project),
      binary: path.resolve(options.binary),
      warmup_frames: options.warmup,
      measured_frames: options.frames,
      resolution: options.resolution,
      editor: options.editor,
      cpu_culling: options.cpu_culling,
      ui_script: options.ui_script ? path.resolve(options.ui_script) : "",
      baseline,
      variants,
    };
    const reportPath = path.join(options.out, "feature-sweep.json");
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    if (options.json) {
      console.log(JSON.stringify({ ...report, report: path.resolve(reportPath) }));
    } else {
      console.log(
        "Disabled feature             Variant p95  Reference p95  Estimated cost",
      );
      for (const variant of variants) {
        console.log(
          `${variant.disabled_features[0].padEnd(28)} ` +
            `${variant.gpu_frame_p95_ms.toFixed(3).padStart(7)} ms  ` +
            `${variant.reference_gpu_frame_p95_ms.toFixed(3).padStart(7)} ms ref  ` +
            `${variant.estimated_gpu_p95_cost_ms.toFixed(3).padStart(7)} ms ` +
            `(${variant.estimated_gpu_p95_cost_percent.toFixed(1)}%)`,
        );
      }
      console.log(
        "Each estimated cost uses the immediately preceding per-feature reference.",
      );
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
