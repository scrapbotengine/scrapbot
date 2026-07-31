import assert from "node:assert/strict";
import test from "node:test";
import {
  acceptanceManifest,
  parseArguments,
  summarizeRun,
  validateRunEnvelope,
} from "./test_gpu_offscreen.mjs";

function successfulEnvelope(overrides = {}) {
  return {
    schema_version: 1,
    command: "run",
    ok: true,
    result: {
      entities: 4,
      renderables: 2,
      draw_batches: 2,
      render_stats: {
        gpu_driven: true,
        compute_culling: true,
        gpu_timestamps_supported: true,
        gpu_timestamps_valid: true,
        gpu_frame_ms: 1.25,
        gpu_scene_ms: 1.0,
        visible_instances: 2,
        ...overrides,
      },
    },
  };
}

test("argument parsing keeps artifacts outside the worktree by default", () => {
  const options = parseArguments([]);
  assert.equal(options.binary, "bin/scrapbot");
  assert.match(options.out, /scrapbot-gpu-offscreen$/);
  assert.deepEqual(
    parseArguments(["--binary", "bin/custom", "--out", "/tmp/report"]),
    {
      binary: "bin/custom",
      out: "/tmp/report",
    },
  );
});

test("run validation requires real GPU work and coherent timestamps", () => {
  const envelope = successfulEnvelope();
  const stats = validateRunEnvelope("minimal", envelope, {
    compute_culling: true,
    minimum_renderables: 2,
  });
  assert.equal(stats.gpu_frame_ms, 1.25);
  assert.equal(stats.gpu_scene_ms, 1.0);

  assert.throws(
    () =>
      validateRunEnvelope(
        "minimal",
        successfulEnvelope({ gpu_timestamps_valid: false }),
      ),
    /timestamps were not published/,
  );
  assert.throws(
    () =>
      validateRunEnvelope("minimal", successfulEnvelope(), {
        compute_culling: false,
      }),
    /expected compute_culling=false/,
  );
});

test("run validation accepts adapters without timestamp-query support", () => {
  const envelope = successfulEnvelope({
    gpu_timestamps_supported: false,
    gpu_timestamps_valid: false,
    gpu_frame_ms: 0,
    gpu_scene_ms: 0,
  });
  assert.doesNotThrow(() => validateRunEnvelope("minimal", envelope));
});

test("manifest summarizes timings and counters without setting thresholds", () => {
  const envelope = successfulEnvelope({
    gpu_world_ms: 0.5,
    gpu_hiz_ms: 0.125,
    instance_upload_bytes: 512,
  });
  const summary = summarizeRun("minimal", envelope, "/tmp/minimal.png");
  assert.equal(summary.image, "minimal.png");
  assert.equal(summary.gpu_passes_ms.world, 0.5);
  assert.equal(summary.gpu_passes_ms.hiz, 0.125);
  assert.equal(summary.counters.instance_upload_bytes, 512);

  const manifest = acceptanceManifest(
    "darwin",
    "arm64",
    [summary],
    "passed",
  );
  assert.equal(manifest.schema_version, 1);
  assert.equal(manifest.status, "passed");
  assert.deepEqual(manifest.host, {
    platform: "darwin",
    architecture: "arm64",
  });
  assert.equal(manifest.runs.length, 1);
});

test("failed manifests preserve the actionable cause", () => {
  const manifest = acceptanceManifest(
    "darwin",
    "arm64",
    [],
    "failed",
    "SCRAPBOT_RUN_FAILED: metal found no adapters",
  );
  assert.equal(manifest.status, "failed");
  assert.match(manifest.error, /metal found no adapters/);
});
