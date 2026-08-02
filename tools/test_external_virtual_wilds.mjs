import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

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
    clusters: 64678,
    groups: 3972,
  },
  {
    id: "7b000000-0000-4000-8000-000000000004",
    source: "assets/coast_rocks_01/coast_rocks_01_1k.gltf",
    vertices: 348785,
    indices: 2039808,
    clusters: 28536,
    groups: 1755,
  },
  {
    id: "7b000000-0000-4000-8000-000000000006",
    source: "assets/dead_tree_trunk_02/dead_tree_trunk_02_1k.gltf",
    vertices: 46112,
    indices: 249384,
    clusters: 3840,
    groups: 243,
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
    throw new Error("expected a fresh three-model Virtual Wilds import");
  }
  runScrapbot(["check", project, "--json"]);

  let sourceTriangles = 0;
  let clusterPages = 0;
  for (const expected of models) {
    const metadata = JSON.parse(
      readFileSync(
        join(importedDirectory, `${expected.id}.model.json`),
        "utf8",
      ),
    );
    if (
      metadata.schema !== "scrapbot.model.v16.attribute-hierarchy" ||
      metadata.source !== expected.source ||
      metadata.node_count !== 1 ||
      metadata.mesh_count !== 1 ||
      metadata.primitive_count !== 1 ||
      metadata.material_count !== 1 ||
      metadata.texture_count !== 3 ||
      metadata.ignored_texture_count !== 0 ||
      metadata.vertex_count !== expected.vertices ||
      metadata.index_count !== expected.indices ||
      metadata.lod_count !== 3 ||
      metadata.lod_vertex_count <= 0 ||
      metadata.lod_index_count <= 0 ||
      metadata.lod_index_count >= metadata.index_count ||
      metadata.cluster_count !== expected.clusters ||
      metadata.cluster_group_count !== expected.groups ||
      metadata.cluster_page_count !== expected.groups
    ) {
      throw new Error(
        `${expected.source} metadata does not match the pinned scan shape`,
      );
    }
    sourceTriangles += metadata.index_count / 3;
    clusterPages += metadata.cluster_page_count;
  }

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
      rendered.result?.renderables !== 9 ||
      rendered.result?.draw_batches !== 13 ||
      stats?.virtual_geometry !== true ||
      stats?.virtual_geometry_compacted !== true ||
      stats?.virtual_geometry_pages !== clusterPages ||
      stats?.virtual_geometry_resident_pages <= 0 ||
      stats?.virtual_geometry_resident_pages >= stats?.virtual_geometry_pages ||
      stats?.virtual_geometry_page_resident_bytes <= 0 ||
      stats?.virtual_geometry_page_resident_bytes >
        stats?.virtual_geometry_page_budget_bytes + 8 * 1024 * 1024 ||
      stats?.virtual_geometry_page_reads <= 0 ||
      stats?.virtual_geometry_page_read_failures !== 0 ||
      stats?.visible_virtual_clusters <= 0 ||
      stats?.gpu_timestamps_valid !== true
    ) {
      throw new Error(
        "Virtual Wilds did not produce the expected bounded streaming workload",
      );
    }
  }

  if (sequenceOut) {
    const sequence = spawnSync(
      process.execPath,
      [
        join(repositoryRoot, "tools/test_render_sequence.mjs"),
        "--binary",
        "bin/scrapbot",
        "--project",
        "examples/virtual-wilds",
        "--warmup",
        "120",
        "--frames",
        "120",
        "--capture-range",
        "108:115",
        "--resolution",
        "1280x720",
        "--stable-frontier",
        "--out",
        sequenceOut,
      ],
      { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 },
    );
    if (sequence.error) {
      throw sequence.error;
    }
    if (sequence.status !== 0) {
      throw new Error(sequence.stderr.trim() || "Virtual Wilds render sequence failed");
    }
    process.stdout.write(sequence.stdout);
  }

  console.log(
    `[external-virtual-wilds] imported ${sourceTriangles} source triangles across ` +
      `${models.length} CC0 scans and ${clusterPages} streamable cluster pages`,
  );
}

try {
  main();
} catch (error) {
  console.error(`[external-virtual-wilds] ${error.message}`);
  process.exitCode = 1;
}
