import { spawnSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const project = join(repositoryRoot, "examples/sponza");
const modelSource = join(project, "assets/Sponza/Sponza.gltf");
const environmentSource = join(project, "assets/studio_small_09_1k.hdr");
const importedDirectory = join(project, ".scrapbot/imported");
const framegrabArgument = process.argv.indexOf("--framegrab");
const framegrab =
  framegrabArgument >= 0 ? process.argv[framegrabArgument + 1] : undefined;
if (framegrabArgument >= 0 && !framegrab) {
  throw new Error("--framegrab requires an output path");
}

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
  if (!existsSync(modelSource) || !existsSync(environmentSource)) {
    throw new Error(
      "Khronos Sponza or Studio Small 09 is not installed; run `mise setup-assets`",
    );
  }

  rmSync(join(project, ".scrapbot"), { force: true, recursive: true });
  const imported = runScrapbot(["import", project, "--json"]);
  if (
    imported.result?.imported !== 2 ||
    imported.result?.products !== 2
  ) {
    throw new Error("expected a fresh Sponza model and environment import");
  }
  runScrapbot(["check", project, "--json"]);

  const metadataName = readdirSync(importedDirectory).find((name) =>
    name.endsWith(".model.json"),
  );
  if (!metadataName) {
    throw new Error("Sponza model import metadata was not produced");
  }
  const metadata = JSON.parse(
    readFileSync(join(importedDirectory, metadataName), "utf8"),
  );
  if (
    metadata.schema !== "scrapbot.model.v6.semantic-scene" ||
    metadata.node_count !== 1 ||
    metadata.mesh_count !== 1 ||
    metadata.primitive_count !== 103 ||
    metadata.material_count !== 25 ||
    metadata.texture_count !== 73 ||
    metadata.ignored_texture_count !== 0 ||
    metadata.vertex_count !== 192496 ||
    metadata.index_count !== 786801
  ) {
    throw new Error(
      "Sponza metadata does not match the pinned real-world model shape",
    );
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
      "2",
      "--framegrab",
      framegrab,
      "--json",
    ]);
    if (
      rendered.result?.renderables !== 103 ||
      rendered.result?.draw_batches !== 103 ||
      rendered.result?.render_stats?.clustered_point_lights !== 11 ||
      rendered.result?.render_stats?.shadow_visible_instances <= 0
    ) {
      throw new Error(
        "Sponza did not produce the expected clustered, shadowed render workload",
      );
    }
  }

  console.log(
    `[external-sponza] imported ${metadata.primitive_count} primitives, ` +
      `${metadata.index_count / 3} triangles, ${metadata.material_count} materials, ` +
      `and ${metadata.texture_count} PBR textures`,
  );
}

try {
  main();
} catch (error) {
  console.error(`[external-sponza] ${error.message}`);
  process.exitCode = 1;
}
