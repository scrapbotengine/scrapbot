import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const SCHEMA_VERSION = 1;

export function parseArguments(arguments_) {
  const options = {
    binary: "bin/scrapbot",
    out: path.join(os.tmpdir(), "scrapbot-gpu-offscreen"),
  };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--binary" || argument === "--out") {
      const value = arguments_[index + 1];
      if (!value) {
        throw new Error(`${argument} requires a value`);
      }
      options[argument.slice(2)] = value;
      index += 1;
      continue;
    }
    throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

export function validateRunEnvelope(label, envelope, expected = {}) {
  if (
    envelope?.schema_version !== 1 ||
    envelope.command !== "run" ||
    envelope.ok !== true
  ) {
    throw new Error(`${label}: Scrapbot run did not succeed`);
  }

  const stats = envelope.result?.render_stats;
  if (!stats?.gpu_driven || envelope.result.draw_batches < 1) {
    throw new Error(`${label}: run did not exercise the GPU-driven renderer`);
  }
  if (
    expected.compute_culling !== undefined &&
    stats.compute_culling !== expected.compute_culling
  ) {
    throw new Error(
      `${label}: expected compute_culling=${expected.compute_culling}`,
    );
  }
  if (
    expected.minimum_renderables !== undefined &&
    envelope.result.renderables < expected.minimum_renderables
  ) {
    throw new Error(
      `${label}: expected at least ${expected.minimum_renderables} renderables`,
    );
  }
  if (
    stats.gpu_timestamps_supported &&
    (!stats.gpu_timestamps_valid ||
      stats.gpu_frame_ms <= 0 ||
      stats.gpu_scene_ms <= 0 ||
      stats.gpu_scene_ms > stats.gpu_frame_ms)
  ) {
    throw new Error(`${label}: supported GPU timestamps were not published`);
  }
  if (!stats.gpu_timestamps_supported && stats.gpu_timestamps_valid) {
    throw new Error(`${label}: unsupported GPU timestamps cannot be valid`);
  }
  return stats;
}

export function summarizeRun(label, envelope, imagePath) {
  const stats = envelope.result.render_stats;
  return {
    label,
    image: path.basename(imagePath),
    entities: envelope.result.entities,
    renderables: envelope.result.renderables,
    draw_batches: envelope.result.draw_batches,
    gpu_timestamps_supported: stats.gpu_timestamps_supported,
    gpu_timestamps_valid: stats.gpu_timestamps_valid,
    gpu_frame_ms: stats.gpu_frame_ms,
    gpu_scene_ms: stats.gpu_scene_ms,
    gpu_passes_ms: {
      instance_expansion: stats.gpu_instance_expansion_ms,
      clustered_lighting: stats.gpu_clustered_lighting_ms,
      cull: stats.gpu_cull_ms,
      shadow: stats.gpu_shadow_ms,
      world: stats.gpu_world_ms,
      post: stats.gpu_post_ms,
      temporal_aa: stats.gpu_temporal_aa_ms,
      ambient_occlusion: stats.gpu_ambient_occlusion_ms,
      screen_space_reflections: stats.gpu_screen_space_reflections_ms,
      volumetric_fog: stats.gpu_volumetric_fog_ms,
      bloom: stats.gpu_bloom_ms,
      composite: stats.gpu_composite_ms,
      automatic_exposure: stats.gpu_automatic_exposure_ms,
      ui: stats.gpu_ui_ms,
      depth: stats.gpu_depth_ms,
      hiz: stats.gpu_hiz_ms,
    },
    counters: {
      draw_database_rebuilds: stats.draw_database_rebuilds,
      visible_instances: stats.visible_instances,
      shadow_visible_instances: stats.shadow_visible_instances,
      frustum_candidates: stats.frustum_candidates,
      frustum_culled_instances: stats.frustum_culled_instances,
      occlusion_culled_instances: stats.occlusion_culled_instances,
      instance_uploads: stats.instance_uploads,
      instance_upload_bytes: stats.instance_upload_bytes,
      instance_expand_dispatches: stats.instance_expand_dispatches,
      cluster_dispatches: stats.cluster_dispatches,
      ui_vertex_rebuilds: stats.ui_vertex_rebuilds,
      ui_vertex_upload_bytes: stats.ui_vertex_upload_bytes,
    },
  };
}

function runCommand(command, arguments_, options = {}) {
  const result = spawnSync(command, arguments_, {
    cwd: options.cwd,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 32 * 1024 * 1024,
  });
  if (options.stdoutPath) {
    fs.writeFileSync(options.stdoutPath, result.stdout ?? "");
  }
  if (options.stderrPath) {
    fs.writeFileSync(options.stderrPath, result.stderr ?? "");
  }
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    let diagnostic = "";
    try {
      const envelope = JSON.parse(result.stdout);
      diagnostic = (envelope.diagnostics ?? [])
        .map((entry) => `${entry.code}: ${entry.message}`)
        .join("; ");
    } catch {
      diagnostic = "";
    }
    throw new Error(
      `${command} ${arguments_.join(" ")} exited with ${result.status}` +
        (diagnostic ? `: ${diagnostic}` : ""),
    );
  }
  return result.stdout;
}

function runScrapbotCase(root, options, testCase) {
  const imagePath = path.join(options.out, `${testCase.label}.png`);
  const jsonPath = path.join(options.out, `${testCase.label}.json`);
  const stderrPath = path.join(options.out, `${testCase.label}.stderr.log`);
  const raw = runCommand(
    path.resolve(root, options.binary),
    [
      "run",
      testCase.project,
      "--backend",
      "wgpu",
      "--headless",
      "--no-hot-reload",
      "--frames",
      String(testCase.frames),
      "--framegrab",
      imagePath,
      "--json",
      ...(testCase.extraArguments ?? []),
    ],
    {
      cwd: root,
      stdoutPath: jsonPath,
      stderrPath,
    },
  );
  const envelope = JSON.parse(raw);
  validateRunEnvelope(testCase.label, envelope, testCase.expected);
  return { envelope, imagePath };
}

function runImageAssertion(root, tool, arguments_) {
  runCommand(process.execPath, [path.join(root, "tools", tool), ...arguments_], {
    cwd: root,
  });
}

export function acceptanceManifest(platform, architecture, runs, status, error) {
  return {
    schema_version: SCHEMA_VERSION,
    status,
    host: {
      platform,
      architecture,
    },
    runs,
    ...(error ? { error } : {}),
  };
}

export function main(arguments_ = process.argv.slice(2)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const options = parseArguments(arguments_);
  options.out = path.resolve(root, options.out);
  fs.rmSync(options.out, { recursive: true, force: true });
  fs.mkdirSync(options.out, { recursive: true });

  const manifestPath = path.join(options.out, "manifest.json");
  const runs = [];
  const cases = [
    {
      label: "minimal",
      project: "examples/minimal",
      frames: 20,
      expected: { compute_culling: true, minimum_renderables: 2 },
    },
    {
      label: "visibility-compute",
      project: "tests/fixtures/gpu-driven",
      frames: 20,
      expected: { compute_culling: true, minimum_renderables: 65 },
    },
    {
      label: "visibility-cpu",
      project: "tests/fixtures/gpu-driven",
      frames: 20,
      extraArguments: ["--cpu-culling"],
      expected: { compute_culling: false, minimum_renderables: 65 },
    },
    {
      label: "pbr-materials",
      project: "examples/pbr-materials",
      frames: 8,
      expected: { compute_culling: true, minimum_renderables: 10 },
    },
  ];

  try {
    const results = new Map();
    for (const testCase of cases) {
      const result = runScrapbotCase(root, options, testCase);
      results.set(testCase.label, result);
      runs.push(summarizeRun(testCase.label, result.envelope, result.imagePath));
      runImageAssertion(root, "assert_png_variance.mjs", [result.imagePath]);
    }
    runImageAssertion(root, "assert_png_close.mjs", [
      results.get("visibility-compute").imagePath,
      results.get("visibility-cpu").imagePath,
      "1",
      "128",
    ]);
    runImageAssertion(root, "assert_png_contract.mjs", [
      results.get("pbr-materials").imagePath,
      path.join(root, "tests/fixtures/visual/pbr-materials.json"),
    ]);

    const manifest = acceptanceManifest(
      process.platform,
      process.arch,
      runs,
      "passed",
    );
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    console.log(`offscreen WGPU acceptance passed: ${manifestPath}`);
    return manifest;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const manifest = acceptanceManifest(
      process.platform,
      process.arch,
      runs,
      "failed",
      message,
    );
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    console.error(`offscreen WGPU acceptance failed: ${message}`);
    console.error(`artifacts preserved at ${options.out}`);
    process.exitCode = 1;
    return manifest;
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  main();
}
