import assert from "node:assert/strict";
import test from "node:test";

import {
  compareRenderProfiles,
  summarizeRenderProfile,
} from "./analyze_render_profile.mjs";

function report(gpuP95, width = 100, uploads = 2) {
  return {
    schema_version: 2,
    warmup_frames: 1,
    recorded_frames: 2,
    gpu_timed_frames: 2,
    metadata: {
      backend: "wgpu",
      adapter_device: "Test GPU",
      adapter_backend: "Test",
    },
    summary: {
      cpu_active: { samples: 2, median_ms: 1, p95_ms: 1.5, max_ms: 1.5 },
      gpu_frame: { samples: 2, median_ms: gpuP95, p95_ms: gpuP95, max_ms: gpuP95 },
      gpu_scene: { samples: 2, median_ms: gpuP95 * 0.75, p95_ms: gpuP95 * 0.75, max_ms: gpuP95 * 0.75 },
      gpu_world: { samples: 2, median_ms: gpuP95 / 2, p95_ms: gpuP95 / 2, max_ms: gpuP95 / 2 },
    },
    frames: [
      {
        physical_width: width,
        physical_height: 50,
        pixel_density: 1,
        shaded_pixels: width * 50,
        viewport: { x: 0, y: 0, width, height: 50 },
        counter_deltas: { instance_uploads: uploads },
        workload: {
          world: {
            enabled: true,
            width,
            height: 50,
            passes: 1,
            draws: 4,
          },
        },
      },
      {
        physical_width: width,
        physical_height: 50,
        pixel_density: 1,
        shaded_pixels: width * 50,
        viewport: { x: 0, y: 0, width, height: 50 },
        counter_deltas: { instance_uploads: 1 },
      },
    ],
  };
}

test("summarizes pass cost and frame-local counters", () => {
  const summary = summarizeRenderProfile(report(4));
  assert.equal(summary.counter_totals.instance_uploads, 3);
  assert.equal(summary.gpu_passes_by_p95[0].pass, "world");
  assert.equal(summary.gpu_passes_by_p95[0].percent_of_gpu_frame_p95, 50);
  assert.equal(summary.gpu_passes_by_p95[0].workload.draws, 4);
  assert.equal(summary.workload.world.width, 100);
  assert.equal(summary.gpu_p95_ms_per_megapixel, 800);
  assert.equal(summary.gpu_scene.p95_ms, 3);
});

test("uses an enabled workload when a change-driven pass skips the first frame", () => {
  const input = report(4);
  input.frames[0].workload.instance_expansion = { enabled: false };
  input.frames[1].workload = {
    instance_expansion: {
      enabled: true,
      passes: 1,
      workgroups: 2,
      invocations: 128,
      instances: 65,
    },
  };
  const summary = summarizeRenderProfile(input);
  assert.equal(summary.workload.instance_expansion.enabled, true);
  assert.equal(summary.workload.instance_expansion.instances, 65);
});

test("compares compatible reports with absolute and relative deltas", () => {
  const comparison = compareRenderProfiles(report(4), report(5, 100, 4));
  assert.equal(comparison.comparable, true);
  assert.equal(comparison.metrics.frame.p95_ms.delta_ms, 1);
  assert.equal(comparison.metrics.frame.p95_ms.delta_percent, 25);
  assert.equal(comparison.metrics.scene.p95_ms.delta_ms, 0.75);
  assert.equal(comparison.counters.instance_uploads.delta, 2);
});

test("rejects dimensions that make timings incomparable", () => {
  const comparison = compareRenderProfiles(report(4), report(4, 200));
  assert.equal(comparison.comparable, false);
  assert.equal(comparison.compatibility_issues[0].field, "dimensions");
});
