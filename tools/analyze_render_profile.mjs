#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const GPU_METRICS = [
  ["gpu_frame", "frame"],
  ["gpu_scene", "scene"],
  ["gpu_instance_expansion", "instance_expansion"],
  ["gpu_clustered_lighting", "clustered_lighting"],
  ["gpu_cull", "cull"],
  ["gpu_shadow", "shadow"],
  ["gpu_shadow_cascade_0", "shadow_cascade_0"],
  ["gpu_shadow_cascade_1", "shadow_cascade_1"],
  ["gpu_shadow_cascade_2", "shadow_cascade_2"],
  ["gpu_shadow_cascade_3", "shadow_cascade_3"],
  ["gpu_depth", "depth"],
  ["gpu_world", "world"],
  ["gpu_hiz", "hiz"],
  ["gpu_temporal_aa", "temporal_aa"],
  ["gpu_ambient_occlusion", "ambient_occlusion"],
  ["gpu_screen_space_reflections", "screen_space_reflections"],
  ["gpu_volumetric_fog", "volumetric_fog"],
  ["gpu_bloom", "bloom"],
  ["gpu_automatic_exposure", "automatic_exposure"],
  ["gpu_composite", "composite"],
  ["gpu_ui", "ui"],
];

function finite(value) {
  return Number.isFinite(value) ? value : 0;
}

function percentageDelta(baseline, candidate) {
  if (baseline === 0) {
    return candidate === 0 ? 0 : null;
  }
  return ((candidate - baseline) / baseline) * 100;
}

function dimensions(report) {
  const frame = report.frames?.[0] ?? {};
  return {
    physical_width: frame.physical_width ?? 0,
    physical_height: frame.physical_height ?? 0,
    pixel_density: frame.pixel_density ?? 0,
    viewport: frame.viewport ?? {},
    shaded_pixels: frame.shaded_pixels ?? 0,
  };
}

function loadReport(file) {
  const report = JSON.parse(fs.readFileSync(file, "utf8"));
  if (report.schema_version !== 2 || !Array.isArray(report.frames) || !report.summary) {
    throw new Error(`${file} is not a Scrapbot render profile schema version 2`);
  }
  return report;
}

function counterTotals(report) {
  const totals = {};
  for (const frame of report.frames) {
    for (const [name, value] of Object.entries(frame.counter_deltas ?? {})) {
      totals[name] = (totals[name] ?? 0) + finite(value);
    }
  }
  return totals;
}

function representativeWorkload(report) {
  const result = {};
  for (const frame of report.frames ?? []) {
    for (const [pass, workload] of Object.entries(frame.workload ?? {})) {
      if (!(pass in result) || (!result[pass]?.enabled && workload?.enabled)) {
        result[pass] = workload;
      }
    }
  }
  return result;
}

function passRanking(report) {
  const frameP95 = finite(report.summary.gpu_frame?.p95_ms);
  const workload = representativeWorkload(report);
  return GPU_METRICS
    .filter(([metric]) => metric !== "gpu_frame" && metric !== "gpu_scene")
    .map(([metric, pass]) => {
      const p95Ms = finite(report.summary[metric]?.p95_ms);
      return {
        pass,
        p95_ms: p95Ms,
        percent_of_gpu_frame_p95: frameP95 > 0 ? (p95Ms / frameP95) * 100 : 0,
        workload: workload[pass] ?? null,
      };
    })
    .filter((entry) => entry.p95_ms > 0)
    .sort((left, right) => right.p95_ms - left.p95_ms);
}

export function summarizeRenderProfile(report, file = "") {
  const size = dimensions(report);
  const megapixels = size.shaded_pixels / 1_000_000;
  const gpuP95 = finite(report.summary.gpu_frame?.p95_ms);
  return {
    file,
    schema_version: report.schema_version,
    metadata: report.metadata,
    warmup_frames: report.warmup_frames,
    recorded_frames: report.recorded_frames,
    gpu_timed_frames: report.gpu_timed_frames,
    dimensions: size,
    cpu_active: report.summary.cpu_active,
    gpu_frame: report.summary.gpu_frame,
    gpu_scene: report.summary.gpu_scene,
    gpu_p95_ms_per_megapixel: megapixels > 0 ? gpuP95 / megapixels : 0,
    gpu_passes_by_p95: passRanking(report),
    workload: representativeWorkload(report),
    counter_totals: counterTotals(report),
  };
}

function comparableField(issues, label, baseline, candidate) {
  if (JSON.stringify(baseline) !== JSON.stringify(candidate)) {
    issues.push({ field: label, baseline, candidate });
  }
}

export function compareRenderProfiles(
  baseline,
  candidate,
  baselineFile = "",
  candidateFile = "",
) {
  const baselineSummary = summarizeRenderProfile(baseline, baselineFile);
  const candidateSummary = summarizeRenderProfile(candidate, candidateFile);
  const compatibility_issues = [];
  comparableField(
    compatibility_issues,
    "metadata.backend",
    baseline.metadata?.backend,
    candidate.metadata?.backend,
  );
  comparableField(
    compatibility_issues,
    "metadata.adapter_device",
    baseline.metadata?.adapter_device,
    candidate.metadata?.adapter_device,
  );
  comparableField(
    compatibility_issues,
    "metadata.adapter_backend",
    baseline.metadata?.adapter_backend,
    candidate.metadata?.adapter_backend,
  );
  comparableField(
    compatibility_issues,
    "metadata.timestamp_queries",
    baseline.metadata?.timestamp_queries,
    candidate.metadata?.timestamp_queries,
  );
  comparableField(
    compatibility_issues,
    "render.compute_culling",
    baseline.frames[0]?.render?.compute_culling,
    candidate.frames[0]?.render?.compute_culling,
  );
  comparableField(
    compatibility_issues,
    "dimensions",
    baselineSummary.dimensions,
    candidateSummary.dimensions,
  );

  const metrics = {};
  for (const [metric, label] of [["cpu_active", "cpu_active"], ...GPU_METRICS]) {
    const baselineMetric = baseline.summary[metric] ?? {};
    const candidateMetric = candidate.summary[metric] ?? {};
    metrics[label] = {};
    for (const statistic of ["median_ms", "p95_ms", "max_ms"]) {
      const before = finite(baselineMetric[statistic]);
      const after = finite(candidateMetric[statistic]);
      metrics[label][statistic] = {
        baseline: before,
        candidate: after,
        delta_ms: after - before,
        delta_percent: percentageDelta(before, after),
      };
    }
  }

  const counter_names = new Set([
    ...Object.keys(baselineSummary.counter_totals),
    ...Object.keys(candidateSummary.counter_totals),
  ]);
  const counters = {};
  for (const name of [...counter_names].sort()) {
    const before = baselineSummary.counter_totals[name] ?? 0;
    const after = candidateSummary.counter_totals[name] ?? 0;
    counters[name] = {
      baseline: before,
      candidate: after,
      delta: after - before,
      delta_percent: percentageDelta(before, after),
    };
  }

  return {
    comparable: compatibility_issues.length === 0,
    compatibility_issues,
    baseline: baselineSummary,
    candidate: candidateSummary,
    metrics,
    counters,
  };
}

function formatMs(value) {
  return `${finite(value).toFixed(3)} ms`;
}

function printSummary(summary) {
  console.log(`Profile: ${summary.file}`);
  console.log(
    `GPU p95 ${formatMs(summary.gpu_frame?.p95_ms)} at ` +
      `${summary.dimensions.physical_width}x${summary.dimensions.physical_height}; ` +
      `scene ${formatMs(summary.gpu_scene?.p95_ms)}; ` +
      `CPU active p95 ${formatMs(summary.cpu_active?.p95_ms)}`,
  );
  console.log("GPU passes by p95:");
  for (const pass of summary.gpu_passes_by_p95) {
    const workload = pass.workload;
    const workloadText =
      workload?.enabled
        ? ` ${workload.width || 0}x${workload.height || 0}, ` +
          `${workload.passes || 0} pass, ${workload.workgroups || 0} groups, ` +
          `${workload.samples_per_pixel || 0} samples/pixel`
        : "";
    console.log(
      `  ${pass.pass.padEnd(26)} ${formatMs(pass.p95_ms).padStart(10)} ` +
      `(${pass.percent_of_gpu_frame_p95.toFixed(1)}%)${workloadText}`,
    );
  }
  console.log("Pass p95 values are independent distributions and are not additive.");
  console.log("Representative pass workloads:");
  for (const [pass, workload] of Object.entries(summary.workload)) {
    if (!workload?.enabled) continue;
    console.log(
      `  ${pass.padEnd(26)} ` +
        `${workload.width || 0}x${workload.height || 0}, ` +
        `${workload.passes || 0} pass, ${workload.workgroups || 0} groups, ` +
        `${workload.invocations || 0} invocations, ${workload.draws || 0} draws, ` +
        `${workload.instances || 0} instances, ` +
        `${workload.samples_per_pixel || 0} samples/pixel`,
    );
  }
}

function printComparison(comparison) {
  console.log(`Comparable: ${comparison.comparable ? "yes" : "no"}`);
  for (const issue of comparison.compatibility_issues) {
    console.log(
      `  mismatch ${issue.field}: ${JSON.stringify(issue.baseline)} -> ` +
        `${JSON.stringify(issue.candidate)}`,
    );
  }
  console.log("p95 deltas:");
  for (const name of ["cpu_active", "frame", ...comparison.candidate.gpu_passes_by_p95.map((p) => p.pass)]) {
    const metric = comparison.metrics[name];
    if (!metric) continue;
    const delta = metric.p95_ms;
    const percent =
      delta.delta_percent === null ? "new" : `${delta.delta_percent.toFixed(1)}%`;
    console.log(
      `  ${name.padEnd(26)} ${formatMs(delta.baseline).padStart(10)} -> ` +
        `${formatMs(delta.candidate).padStart(10)} (${percent})`,
    );
  }
}

function usage() {
  console.log(
    "Usage: node tools/analyze_render_profile.mjs <profile.json> " +
      "[candidate-profile.json] [--json]",
  );
}

export function main(argv = process.argv.slice(2)) {
  const json = argv.includes("--json");
  const files = argv.filter((argument) => argument !== "--json");
  if (files.length < 1 || files.length > 2 || files.includes("--help")) {
    usage();
    return files.includes("--help") ? 0 : 1;
  }
  try {
    const baseline = loadReport(files[0]);
    const result =
      files.length === 1
        ? summarizeRenderProfile(baseline, path.resolve(files[0]))
        : compareRenderProfiles(
            baseline,
            loadReport(files[1]),
            path.resolve(files[0]),
            path.resolve(files[1]),
          );
    if (json) {
      console.log(JSON.stringify(result));
    } else if (files.length === 1) {
      printSummary(result);
    } else {
      printComparison(result);
    }
    return files.length === 2 && !result.comparable ? 2 : 0;
  } catch (error) {
    console.error(error.message);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}
