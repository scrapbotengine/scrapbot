import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  assertSafeOutputDirectory,
  benchmarkManifest,
  parseBenchmarkArguments,
  renderBenchmarkSummary,
} from "./run_gpu_benchmarks.mjs";
import {
  benchmarkComparison,
  noBaselineComparison,
  renderComparisonMarkdown,
} from "./compare_gpu_benchmarks.mjs";

function profile(gpuP95, adapter = "Test GPU") {
  return {
    schema_version: 2,
    metadata: {
      backend: "wgpu",
      adapter_device: adapter,
      adapter_backend: "Metal",
      timestamp_query_supported: true,
      compute_culling: true,
    },
    summary: {
      cpu_active: { samples: 2, median_ms: 1, p95_ms: 1.5, max_ms: 1.5 },
      gpu_frame: { samples: 2, median_ms: gpuP95, p95_ms: gpuP95, max_ms: gpuP95 },
      gpu_scene: {
        samples: 2,
        median_ms: gpuP95 * 0.75,
        p95_ms: gpuP95 * 0.75,
        max_ms: gpuP95 * 0.75,
      },
      gpu_world: {
        samples: 2,
        median_ms: gpuP95 / 2,
        p95_ms: gpuP95 / 2,
        max_ms: gpuP95 / 2,
      },
    },
    frames: [
      {
        physical_width: 960,
        physical_height: 540,
        pixel_density: 1,
        shaded_pixels: 960 * 540,
        viewport: { x: 0, y: 0, width: 960, height: 540 },
        counter_deltas: { instance_uploads: 1 },
      },
    ],
  };
}

function writeBundle(root, gitSha, inputProfile) {
  fs.mkdirSync(path.join(root, "minimal", "960x540"), { recursive: true });
  fs.writeFileSync(
    path.join(root, "manifest.json"),
    JSON.stringify({
      schema_version: 1,
      status: "passed",
      git_sha: gitSha,
      workflow_run_id: gitSha,
      projects: ["minimal"],
    }),
  );
  fs.writeFileSync(
    path.join(root, "minimal", "sweep.json"),
    JSON.stringify({
      schema_version: 1,
      points: [{ resolution: "960x540" }],
    }),
  );
  fs.writeFileSync(
    path.join(root, "minimal", "960x540", "profile.json"),
    JSON.stringify(inputProfile),
  );
}

test("benchmark defaults cover representative workloads and resolutions", () => {
  const options = parseBenchmarkArguments([]);
  assert.deepEqual(
    options.projects.map((project) => project.name),
    ["minimal", "ecs-showcase", "sponza"],
  );
  assert.equal(options.warmup, 60);
  assert.equal(options.frames, 240);
});

test("benchmark arguments support bounded local runs without external assets", () => {
  const options = parseBenchmarkArguments([
    "--out",
    "/tmp/gpu",
    "--warmup",
    "2",
    "--frames",
    "3",
    "--without-sponza",
  ]);
  assert.equal(options.out, "/tmp/gpu");
  assert.equal(options.warmup, 2);
  assert.equal(options.frames, 3);
  assert.deepEqual(
    options.projects.map((project) => project.name),
    ["minimal", "ecs-showcase"],
  );
});

test("benchmark output cannot recursively delete the repository or filesystem root", () => {
  assert.throws(
    () => assertSafeOutputDirectory("/workspace/scrapbot", "/workspace/scrapbot"),
    /dedicated directory/,
  );
  assert.throws(
    () => assertSafeOutputDirectory("/workspace/scrapbot", "/"),
    /dedicated directory/,
  );
  assert.doesNotThrow(() =>
    assertSafeOutputDirectory(
      "/workspace/scrapbot",
      "/tmp/scrapbot-gpu-benchmarks",
    ),
  );
});

test("benchmark summary exposes every resolution without inventing thresholds", () => {
  const options = parseBenchmarkArguments(["--without-sponza"]);
  const manifest = benchmarkManifest(
    options,
    "passed",
    ["minimal"],
    "",
    ["Metal: Test GPU"],
  );
  const markdown = renderBenchmarkSummary(manifest, [
    {
      name: "minimal",
      report: {
        points: [
          {
            resolution: "1280x720",
            gpu_frame_median_ms: 1,
            gpu_frame_p95_ms: 1.5,
            cpu_active_p95_ms: 0.25,
          },
        ],
      },
    },
  ]);
  assert.match(markdown, /1280x720/);
  assert.match(markdown, /1\.500 ms/);
  assert.match(markdown, /Metal: Test GPU/);
  assert.doesNotMatch(markdown, /threshold/i);
});

test("comparison Markdown reports deltas and incompatible points", () => {
  const markdown = renderComparisonMarkdown({
    status: "compared",
    baseline: { git_sha: "before" },
    candidate: { git_sha: "after" },
    comparable_entries: 1,
    incompatible_entries: 1,
    entries: [
      {
        project: "sponza",
        resolution: "1920x1080",
        comparable: true,
        metrics: {
          frame: {
            p95_ms: {
              baseline: 20,
              candidate: 15,
              delta_percent: -25,
            },
          },
          cpu_active: {
            p95_ms: {
              baseline: 2,
              candidate: 2.2,
              delta_percent: 10,
            },
          },
          world: {
            p95_ms: {
              baseline: 6,
              candidate: 5,
              delta_percent: -16.7,
            },
          },
        },
      },
      {
        project: "minimal",
        resolution: "960x540",
        comparable: false,
      },
    ],
  });
  assert.match(markdown, /-25\.0%/);
  assert.match(markdown, /world 5\.000 ms/);
  assert.match(markdown, /incompatible/);
});

test("bundle comparison derives relocatable profile paths and enforces compatibility", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "scrapbot-gpu-bundle-test-"));
  const baseline = path.join(temporary, "baseline");
  const candidate = path.join(temporary, "candidate");
  writeBundle(baseline, "before", profile(4));
  writeBundle(candidate, "after", profile(3));

  const comparison = benchmarkComparison(baseline, candidate);
  assert.equal(comparison.comparable_entries, 1);
  assert.equal(comparison.entries[0].metrics.frame.p95_ms.delta_percent, -25);

  writeBundle(candidate, "after", profile(3, "Different GPU"));
  const incompatible = benchmarkComparison(baseline, candidate);
  assert.equal(incompatible.comparable_entries, 0);
  assert.equal(incompatible.incompatible_entries, 1);
  assert.equal(
    incompatible.entries[0].compatibility_issues[0].field,
    "metadata.adapter_device",
  );
});

test("missing history is explicit instead of becoming a fake zero baseline", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "scrapbot-gpu-history-test-"));
  writeBundle(temporary, "first", profile(3));
  const comparison = noBaselineComparison(temporary);
  assert.equal(comparison.status, "no_baseline");
  assert.equal(comparison.baseline, null);
  assert.equal(comparison.entries.length, 0);
});
