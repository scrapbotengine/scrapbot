import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isVirtualGeometryErrorTier } from "./test_render_sequence.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const project = join(repositoryRoot, "examples/virtual-wilds");
const importedDirectory = join(project, ".scrapbot/imported");
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
    source: "assets/pine_sapling_small/pine_sapling_small_1k.gltf",
    nodes: 3,
    meshes: 3,
    primitives: 6,
    materials: 2,
    textures: 6,
    vertices: 406356,
    indices: 1194432,
    lods: 0,
    clusters: 9560,
    groups: 642,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000e",
    source: "assets/kenney-nature/tree_pineDefaultA.glb",
    nodes: 2,
    primitives: 2,
    materials: 2,
    textures: 0,
    vertices: 784,
    indices: 690,
    lods: 0,
    clusters: 7,
    groups: 2,
    virtual: false,
  },
  {
    id: "7b000000-0000-4000-8000-00000000000f",
    source: "assets/kenney-nature/tree_pineDefaultB.glb",
    nodes: 2,
    primitives: 2,
    materials: 2,
    textures: 0,
    vertices: 832,
    indices: 738,
    lods: 0,
    clusters: 7,
    groups: 2,
    virtual: false,
  },
  {
    id: "7b000000-0000-4000-8000-000000000010",
    source: "assets/kenney-nature/tree_pineTallA_detailed.glb",
    nodes: 2,
    primitives: 2,
    materials: 2,
    textures: 0,
    vertices: 448,
    indices: 402,
    lods: 0,
    clusters: 4,
    groups: 2,
    virtual: false,
  },
  {
    id: "7b000000-0000-4000-8000-000000000011",
    source: "assets/kenney-nature/tree_pineTallB_detailed.glb",
    nodes: 2,
    primitives: 2,
    materials: 2,
    textures: 0,
    vertices: 544,
    indices: 498,
    lods: 0,
    clusters: 5,
    groups: 2,
    virtual: false,
  },
  {
    id: "7b000000-0000-4000-8000-000000000012",
    source: "assets/kenney-nature/tree_pineTallC_detailed.glb",
    nodes: 2,
    primitives: 2,
    materials: 2,
    textures: 0,
    vertices: 488,
    indices: 462,
    lods: 0,
    clusters: 5,
    groups: 2,
    virtual: false,
  },
  {
    id: "7b000000-0000-4000-8000-000000000013",
    source: "assets/kenney-nature/tree_pineTallD_detailed.glb",
    nodes: 2,
    primitives: 2,
    materials: 2,
    textures: 0,
    vertices: 536,
    indices: 510,
    lods: 0,
    clusters: 6,
    groups: 2,
    virtual: false,
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
    simulated.result?.renderables !== 1425 ||
    simulated.result?.draw_batches !== 26
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
      metadata.schema !== "scrapbot.model.v18.distance-fields" ||
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
      rendered.result?.renderables !== 1425 ||
      rendered.result?.draw_batches !== 26 ||
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
            frame.render?.draw_batches !== 26 ||
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
