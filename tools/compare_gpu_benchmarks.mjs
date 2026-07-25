#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { compareRenderProfiles } from "./analyze_render_profile.mjs";

function loadJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function profilePath(bundle, project, resolution) {
  return path.join(bundle, project, resolution, "profile.json");
}

function percentage(value) {
  return value === null ? "new" : `${value >= 0 ? "+" : ""}${value.toFixed(1)}%`;
}

export function benchmarkComparison(baselineBundle, candidateBundle) {
  const baselineManifest = loadJson(path.join(baselineBundle, "manifest.json"));
  const candidateManifest = loadJson(path.join(candidateBundle, "manifest.json"));
  const entries = [];
  for (const project of candidateManifest.projects ?? []) {
    const sweep = loadJson(path.join(candidateBundle, project, "sweep.json"));
    for (const point of sweep.points) {
      const baselineFile = profilePath(baselineBundle, project, point.resolution);
      const candidateFile = profilePath(candidateBundle, project, point.resolution);
      if (!fs.existsSync(baselineFile)) {
        entries.push({
          project,
          resolution: point.resolution,
          comparable: false,
          compatibility_issues: [{ field: "baseline", baseline: "missing", candidate: candidateFile }],
        });
        continue;
      }
      const comparison = compareRenderProfiles(
        loadJson(baselineFile),
        loadJson(candidateFile),
        baselineFile,
        candidateFile,
      );
      entries.push({
        project,
        resolution: point.resolution,
        comparable: comparison.comparable,
        compatibility_issues: comparison.compatibility_issues,
        metrics: comparison.metrics,
        counters: comparison.counters,
      });
    }
  }
  return {
    schema_version: 1,
    status: "compared",
    baseline: {
      git_sha: baselineManifest.git_sha ?? "",
      workflow_run_id: baselineManifest.workflow_run_id ?? "",
    },
    candidate: {
      git_sha: candidateManifest.git_sha ?? "",
      workflow_run_id: candidateManifest.workflow_run_id ?? "",
    },
    comparable_entries: entries.filter((entry) => entry.comparable).length,
    incompatible_entries: entries.filter((entry) => !entry.comparable).length,
    entries,
  };
}

export function noBaselineComparison(candidateBundle) {
  const candidateManifest = loadJson(path.join(candidateBundle, "manifest.json"));
  return {
    schema_version: 1,
    status: "no_baseline",
    baseline: null,
    candidate: {
      git_sha: candidateManifest.git_sha ?? "",
      workflow_run_id: candidateManifest.workflow_run_id ?? "",
    },
    comparable_entries: 0,
    incompatible_entries: 0,
    entries: [],
  };
}

export function renderComparisonMarkdown(comparison) {
  const lines = ["# Scrapbot GPU benchmark comparison", ""];
  if (comparison.status === "no_baseline") {
    lines.push("No compatible previous benchmark artifact was available.", "");
    return `${lines.join("\n")}\n`;
  }
  lines.push(
    `- Baseline: \`${comparison.baseline.git_sha || "unknown"}\``,
    `- Candidate: \`${comparison.candidate.git_sha || "unknown"}\``,
    `- Comparable points: ${comparison.comparable_entries}`,
    `- Incompatible points: ${comparison.incompatible_entries}`,
    "",
    "| Workload | Resolution | GPU p95 | CPU p95 | Hottest candidate pass |",
    "| --- | --- | ---: | ---: | --- |",
  );
  for (const entry of comparison.entries) {
    if (!entry.comparable) {
      lines.push(`| ${entry.project} | ${entry.resolution} | incompatible | incompatible | — |`);
      continue;
    }
    const frame = entry.metrics.frame.p95_ms;
    const cpu = entry.metrics.cpu_active.p95_ms;
    const passes = Object.entries(entry.metrics)
      .filter(([name]) => name !== "frame" && name !== "cpu_active")
      .sort((left, right) => right[1].p95_ms.candidate - left[1].p95_ms.candidate);
    const hottest = passes[0];
    lines.push(
      `| ${entry.project} | ${entry.resolution} | ` +
        `${frame.baseline.toFixed(3)} → ${frame.candidate.toFixed(3)} ms (${percentage(frame.delta_percent)}) | ` +
        `${cpu.baseline.toFixed(3)} → ${cpu.candidate.toFixed(3)} ms (${percentage(cpu.delta_percent)}) | ` +
        `${hottest ? `${hottest[0]} ${hottest[1].p95_ms.candidate.toFixed(3)} ms` : "—"} |`,
    );
  }
  lines.push(
    "",
    "Timings are same-runner evidence. Pass p95 distributions are independent and do not add up to frame p95.",
    "",
  );
  return `${lines.join("\n")}\n`;
}

export function main(arguments_ = process.argv.slice(2)) {
  const [baselineBundle, candidateBundle, outputDirectory] = arguments_;
  if (!candidateBundle || !outputDirectory) {
    console.error(
      "usage: node tools/compare_gpu_benchmarks.mjs <baseline-or-dash> <candidate> <output>",
    );
    return 1;
  }
  try {
    fs.mkdirSync(outputDirectory, { recursive: true });
    const comparison =
      baselineBundle === "-" || !fs.existsSync(path.join(baselineBundle, "manifest.json"))
        ? noBaselineComparison(candidateBundle)
        : benchmarkComparison(baselineBundle, candidateBundle);
    fs.writeFileSync(
      path.join(outputDirectory, "comparison.json"),
      `${JSON.stringify(comparison, null, 2)}\n`,
    );
    fs.writeFileSync(
      path.join(outputDirectory, "comparison.md"),
      renderComparisonMarkdown(comparison),
    );
    console.log(path.resolve(outputDirectory, "comparison.json"));
    return 0;
  } catch (error) {
    console.error(error.message);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  process.exitCode = main();
}
