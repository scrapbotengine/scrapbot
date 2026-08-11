import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isVirtualGeometryErrorTier } from "./test_render_sequence.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const project = join(repositoryRoot, "examples/virtual-wilds");
const importedDirectory = join(project, ".scrapbot/imported");
// The null backend reports the 20 authored material batches. The WGPU backend
// may split those into a few additional resident primitive batches while pages
// stream in, especially for the six-primitive fir asset. Keep that expansion
// bounded without pretending the two counters describe the same thing.
const maxResidentGpuBatches = 32;
const framegrabArgument = process.argv.indexOf("--framegrab");
const framegrab =
  framegrabArgument >= 0 ? process.argv[framegrabArgument + 1] : undefined;
if (framegrabArgument >= 0 && !framegrab) {
  throw new Error("--framegrab requires an output path");
}
const sequenceArgument = process.argv.indexOf("--sequence-out");
const sequenceOut =
  sequenceArgument >= 0 ? process.argv[sequenceArgument + 1] : undefined;
if (sequenceArgument >= 0 && !sequenceOut) {
  throw new Error("--sequence-out requires an output directory");
}

const models = [
  {
    id: "7b000000-0000-4000-8000-000000000003",
    source: "assets/coastal_cliff_04/coastal_cliff_04_1k.gltf",
    vertices: 789032,
    indices: 4613778,
    clusters: 64935,
    groups: 3996,
  },
  {
    id: "7b000000-0000-4000-8000-000000000004",
    source: "assets/coast_rocks_01/coast_rocks_01_1k.gltf",
    vertices: 348785,
    indices: 2039808,
    clusters: 28607,
    groups: 1758,
  },
  {
    id: "7b000000-0000-4000-8000-000000000006",
    source: "assets/dead_tree_trunk_02/dead_tree_trunk_02_1k.gltf",
    vertices: 46112,
    indices: 249384,
    clusters: 3840,
    groups: 243,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000b",
    source: "assets/coast_rocks_05/coast_rocks_05_1k.gltf",
    vertices: 401298,
    indices: 2315172,
    clusters: 33098,
    groups: 2027,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000c",
    source: "assets/boulder_01/boulder_01_1k.gltf",
    vertices: 67042,
    indices: 198366,
    lods: 2,
    clusters: 7299,
    groups: 446,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000d",
    source: "assets/fir_sapling/fir_sapling_1k.gltf",
    nodes: 3,
    meshes: 3,
    primitives: 6,
    materials: 2,
    textures: 6,
    vertices: 515299,
    indices: 1299063,
    lods: 18,
    clusters: 21896,
    groups: 1528,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000e",
    source: "assets/coastal_cliff_01/coastal_cliff_01_1k.gltf",
    vertices: 238686,
    indices: 1385472,
    clusters: 19600,
    groups: 1203,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000f",
    source: "assets/coastal_cliff_02/coastal_cliff_02_1k.gltf",
    vertices: 482925,
    indices: 2829852,
    clusters: 39811,
    groups: 2436,
  },
  {
    id: "7b000000-0000-4000-8000-000000000010",
    source: "assets/coast_line_01/coast_line_01_1k.gltf",
    vertices: 272608,
    indices: 1618473,
    clusters: 22364,
    groups: 1374,
  },
  {
    id: "7b000000-0000-4000-8000-000000000011",
    source: "assets/coast_line_02/coast_line_02_1k.gltf",
    vertices: 383936,
    indices: 2270820,
    clusters: 31506,
    groups: 1917,
  },
  {
    id: "7b000000-0000-4000-8000-000000000012",
    source: "assets/coast_rocks_02/coast_rocks_02_1k.gltf",
    vertices: 648187,
    indices: 3781269,
    clusters: 53401,
    groups: 3247,
  },
  {
    id: "7b000000-0000-4000-8000-000000000013",
    source: "assets/coast_rocks_03/coast_rocks_03_1k.gltf",
    vertices: 415339,
    indices: 2440392,
    clusters: 34130,
    groups: 2091,
  },
];

function runScrapbot(args) {
  const result = spawnSync(join(repositoryRoot, "bin/scrapbot"), args, {
    cwd: repositoryRoot,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error) {
    throw result.error;
  }
  const output = result.stdout.trim();
  let document;
  try {
    document = JSON.parse(output);
  } catch {
    throw new Error(`Scrapbot did not produce structured JSON: ${output}`);
  }
  if (
    result.status !== 0 ||
    document.schema_version !== 1 ||
    document.ok !== true
  ) {
    throw new Error(
      document.diagnostics?.[0]?.message ||
        result.stderr.trim() ||
        `Scrapbot exited with status ${result.status}`,
    );
  }
  return document;
}

function main() {
  const generatedScene = spawnSync(
    process.execPath,
    [join(repositoryRoot, "tools/generate_virtual_wilds_instances.mjs"), "--check"],
    { cwd: repositoryRoot, encoding: "utf8" },
  );
  if (generatedScene.error) {
    throw generatedScene.error;
  }
  if (generatedScene.status !== 0) {
    throw new Error(
      generatedScene.stderr.trim() || "Virtual Wilds generated scene is stale",
    );
  }

  const missing = models.find(
    (model) => !existsSync(join(project, model.source)),
  );
  if (missing) {
    throw new Error(
      `Virtual Wilds source ${missing.source} is not installed; run \`mise setup-assets\``,
    );
  }

  rmSync(join(project, ".scrapbot"), { force: true, recursive: true });
  const imported = runScrapbot(["import", project, "--json"]);
  if (
    imported.result?.imported !== models.length ||
    imported.result?.products !== models.length
  ) {
    throw new Error("expected a fresh twelve-model Virtual Wilds import");
  }
  runScrapbot(["check", project, "--json"]);
  const simulated = runScrapbot([
    "run",
    project,
    "--backend",
    "null",
    "--headless",
    "--no-hot-reload",
    "--frames",
    "3",
    "--json",
  ]);
  if (
    simulated.result?.renderables !== 356 ||
    simulated.result?.draw_batches !== 20
  ) {
    throw new Error(
      "Virtual Wilds did not preserve its high-instance shared-batch workload",
    );
  }

  let sourceTriangles = 0;
  let clusterPages = 0;
  for (const expected of models) {
    const metadata = JSON.parse(
      readFileSync(
        join(importedDirectory, `${expected.id}.model.json`),
        "utf8",
      ),
    );
    const expectedLods = expected.lods ?? 3;
    if (
      metadata.schema !== "scrapbot.model.v21.bootstrap-resident-tail" ||
      metadata.source !== expected.source ||
      metadata.node_count !== (expected.nodes ?? 1) ||
      metadata.mesh_count !== (expected.meshes ?? 1) ||
      metadata.primitive_count !== (expected.primitives ?? 1) ||
      metadata.material_count !== (expected.materials ?? 1) ||
      metadata.texture_count !== (expected.textures ?? 3) ||
      metadata.ignored_texture_count !== 0 ||
      metadata.vertex_count !== expected.vertices ||
      metadata.index_count !== expected.indices ||
      metadata.lod_count !== expectedLods ||
      (expectedLods > 0 && metadata.lod_vertex_count <= 0) ||
      (expectedLods > 0 && metadata.lod_index_count <= 0) ||
      (expectedLods === 0 && metadata.lod_vertex_count !== 0) ||
      (expectedLods === 0 && metadata.lod_index_count !== 0) ||
      metadata.cluster_count !== expected.clusters ||
      metadata.cluster_group_count !== expected.groups ||
      metadata.cluster_page_count !== expected.groups ||
      metadata.distance_field_count !== metadata.primitive_count ||
      metadata.signed_distance_field_count < 0 ||
      metadata.signed_distance_field_count > metadata.distance_field_count ||
      metadata.distance_field_sample_count <= 0 ||
      metadata.distance_field_byte_count !== metadata.distance_field_sample_count * 2
    ) {
      throw new Error(
        `${expected.source} metadata does not match the pinned scan shape`,
      );
    }
    sourceTriangles += metadata.index_count / 3;
    if (expected.virtual !== false) {
      clusterPages += metadata.cluster_page_count;
    }
  }
  // The water plane and shared procedural rock mesh contribute their own
  // compact hierarchies in addition to the imported products.
  const sceneVirtualPages = clusterPages + 17;

  if (framegrab) {
    const rendered = runScrapbot([
      "run",
      project,
      "--backend",
      "wgpu",
      "--headless",
      "--no-hot-reload",
      "--frames",
      "120",
      "--framegrab",
      framegrab,
      "--json",
    ]);
    const stats = rendered.result?.render_stats;
    if (
      rendered.result?.renderables !== 356 ||
      rendered.result?.draw_batches !== 20 ||
      stats?.virtual_geometry !== true ||
      stats?.virtual_geometry_compacted !== true ||
      stats?.meshlet_visible_capacity > 1048576 ||
      stats?.virtual_geometry_pages !== sceneVirtualPages ||
      stats?.virtual_geometry_resident_pages <= 0 ||
      stats?.virtual_geometry_resident_pages >= stats?.virtual_geometry_pages ||
      stats?.virtual_geometry_page_resident_bytes <= 0 ||
      stats?.virtual_geometry_page_resident_bytes >
        stats?.virtual_geometry_page_budget_bytes + 8 * 1024 * 1024 ||
      stats?.virtual_geometry_page_reads <= 0 ||
      stats?.virtual_geometry_page_read_failures !== 0 ||
      stats?.visible_virtual_clusters <= 0 ||
      stats?.frustum_culled_instances <= 0 ||
      stats?.gpu_timestamps_valid !== true
    ) {
      throw new Error(
        "Virtual Wilds did not produce the expected bounded streaming workload",
      );
    }
  }

  if (sequenceOut) {
    const sequences = [
      {
        name: "coverage",
        arguments: [
          "--warmup",
          "180",
          "--frames",
          "120",
          "--capture-range",
          "44:50",
        ],
      },
      {
        name: "volumetric-fog",
        captureStart: 52,
        captureEnd: 59,
        visualContract: "tests/fixtures/visual/virtual-wilds-volumetric-fog.json",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "64",
          "--capture-range",
          "52:59",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-volumetric-fog.json",
        ],
      },
      {
        name: "grounded-firs",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "90",
          "--capture-range",
          "80:84",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-grounded-firs.json",
        ],
      },
      {
        name: "water-caustics",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "110",
          "--capture-range",
          "100:107",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-water-caustics.json",
        ],
      },
      {
        name: "water-whitecaps",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "330",
          "--capture-range",
          "312:319",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-water-whitecaps.json",
        ],
      },
      {
        name: "water-foam-close",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "220",
          "--capture-range",
          "202:209",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-water-foam-close.json",
        ],
      },
      {
        name: "water-underwater",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "150",
          "--capture-range",
          "132:139",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-water-underwater-shore.json",
        ],
      },
      {
        name: "water-surface-crossing",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "130",
          "--capture-range",
          "56:67",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-water-surface-crossing.json",
        ],
      },
      {
        name: "volumetric-fog-motion",
        captureStart: 30,
        captureEnd: 76,
        visualContract: "tests/fixtures/visual/virtual-wilds-volumetric-fog.json",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "88",
          "--capture-range",
          "30:76",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-volumetric-fog-motion.json",
        ],
      },
      {
        name: "transition",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "300",
          "--capture-range",
          "200:224",
          "--require-transition-activity",
        ],
      },
      {
        name: "editor-camera-history",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "902",
          "--capture-range",
          "850:857",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-editor-camera-history.json",
        ],
      },
      {
        name: "residency-churn",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "1230",
          "--capture-range",
          "700:707",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-residency-tour.json",
          "--require-residency-pressure",
        ],
      },
      {
        name: "compact-address-window",
        arguments: [
          "--warmup",
          "0",
          "--frames",
          "7000",
          "--capture-range",
          "6950:6957",
          "--editor",
          "--ui-script",
          "tests/fixtures/ui/virtual-wilds-address-window.json",
          "--require-residency-pressure",
        ],
      },
    ];
    for (const sequenceConfig of sequences) {
      const sequence = spawnSync(
        process.execPath,
        [
          join(repositoryRoot, "tools/test_render_sequence.mjs"),
          "--binary",
          "bin/scrapbot",
          "--project",
          "examples/virtual-wilds",
          ...sequenceConfig.arguments,
          "--resolution",
          "1280x720",
          "--out",
          join(sequenceOut, sequenceConfig.name),
        ],
        { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 },
      );
      if (sequence.error) {
        throw sequence.error;
      }
      if (sequence.status !== 0) {
        throw new Error(
          sequence.stderr.trim() ||
            `Virtual Wilds ${sequenceConfig.name} render sequence failed`,
        );
      }
      process.stdout.write(sequence.stdout);
      if (sequenceConfig.visualContract) {
        for (
          let frame = sequenceConfig.captureStart;
          frame <= sequenceConfig.captureEnd;
          frame += 1
        ) {
          const visualCheck = spawnSync(
            process.execPath,
            [
              join(repositoryRoot, "tools/assert_png_contract.mjs"),
              join(
                sequenceOut,
                sequenceConfig.name,
                "frames",
                `frame-${String(frame).padStart(6, "0")}.png`,
              ),
              join(repositoryRoot, sequenceConfig.visualContract),
            ],
            {cwd: repositoryRoot, encoding: "utf8"},
          );
          if (visualCheck.error) {
            throw visualCheck.error;
          }
          if (visualCheck.status !== 0) {
            throw new Error(
              visualCheck.stderr.trim() ||
                `Virtual Wilds ${sequenceConfig.name} visual contract failed`,
            );
          }
        }
      }
      const profile = JSON.parse(
        readFileSync(join(sequenceOut, sequenceConfig.name, "profile.json"), "utf8"),
      );
      if (
        profile.frames?.some(
          (frame) =>
            frame.render?.draw_batches <= 0 ||
            frame.render?.draw_batches > maxResidentGpuBatches ||
            frame.render?.virtual_geometry_compacted !== true ||
            !isVirtualGeometryErrorTier(
              frame.render?.virtual_geometry_error_pixels,
            ) ||
            frame.render?.meshlet_visible_capacity > 1048576 ||
            frame.render?.virtual_geometry_page_resident_bytes >
              frame.render?.virtual_geometry_page_budget_bytes ||
            frame.render?.virtual_geometry_page_request_overflow !== 0,
        ) ||
        !profile.frames?.some(
          (frame) => frame.render?.frustum_culled_instances > 0,
        )
      ) {
        throw new Error(
          `Virtual Wilds ${sequenceConfig.name} escaped its bounded GPU workload`,
        );
      }
    }
  }

  console.log(
    `[external-virtual-wilds] imported ${sourceTriangles} source triangles across ` +
      `${models.length} CC0 models and ${clusterPages} streamable cluster pages`,
  );
}

try {
  main();
} catch (error) {
  console.error(`[external-virtual-wilds] ${error.message}`);
  process.exitCode = 1;
}
