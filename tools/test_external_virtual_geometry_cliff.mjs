import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const project = join(repositoryRoot, "examples/virtual-geometry-cliff");
const modelSource = join(
  project,
  "assets/coastal_cliff_04/coastal_cliff_04_1k.gltf",
);
const importedDirectory = join(project, ".scrapbot/imported");
const modelMetadata = join(
  importedDirectory,
  "7b000000-0000-4000-8000-000000000003.model.json",
);

function runScrapbot(args) {
  const result = spawnSync(join(repositoryRoot, "bin/scrapbot"), args, {
    cwd: repositoryRoot,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error) {
    throw result.error;
  }
  let document;
  try {
    document = JSON.parse(result.stdout.trim());
  } catch {
    throw new Error(
      `Scrapbot did not produce structured JSON: ${result.stdout.trim()}`,
    );
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
  if (!existsSync(modelSource)) {
    throw new Error(
      "Poly Haven Coastal Cliff 04 is not installed; run `mise setup-assets`",
    );
  }

  rmSync(importedDirectory, { force: true, recursive: true });
  const imported = runScrapbot(["import", project, "--json"]);
  if (imported.result?.imported !== 1 || imported.result?.products !== 1) {
    throw new Error("expected one freshly imported cliff model product");
  }

  runScrapbot(["check", project, "--json"]);

  const metadata = JSON.parse(readFileSync(modelMetadata, "utf8"));
  const expected = {
    source: "assets/coastal_cliff_04/coastal_cliff_04_1k.gltf",
    node_count: 1,
    mesh_count: 1,
    primitive_count: 1,
    material_count: 1,
    texture_count: 3,
    vertex_count: 789032,
    index_count: 4613778,
    lod_count: 3,
    cluster_count: 64935,
    cluster_group_count: 3996,
    cluster_page_count: 3996,
  };
  for (const [field, value] of Object.entries(expected)) {
    if (metadata[field] !== value) {
      throw new Error(
        `unexpected cliff metadata ${field}: ${metadata[field]} (expected ${value})`,
      );
    }
  }

  console.log(
    "[external-virtual-geometry-cliff] imported one 1,537,926-triangle CC0 cliff " +
      "into 3,996 streamable cluster pages",
  );
}

try {
  main();
} catch (error) {
  console.error(`[external-virtual-geometry-cliff] ${error.message}`);
  process.exitCode = 1;
}
