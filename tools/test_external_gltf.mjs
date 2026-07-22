import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const modelSource = join(
  repositoryRoot,
  "tests/fixtures/external/downloads/gltf/DamagedHelmet.glb",
);
const environmentSource = join(
  repositoryRoot,
  "tests/fixtures/external/downloads/hdr/studio_small_09_1k.hdr",
);
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
  if (result.status !== 0 || document.schema_version !== 1 || document.ok !== true) {
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
    throw new Error("Damaged Helmet or Studio Small 09 is not installed; run `mise setup-assets`");
  }

  const project = mkdtempSync(join(tmpdir(), "scrapbot-gltf-integration-"));
  try {
    mkdirSync(join(project, "assets"));
    mkdirSync(join(project, "resources"));
    mkdirSync(join(project, "scenes"));
    copyFileSync(modelSource, join(project, "assets/DamagedHelmet.glb"));
    copyFileSync(environmentSource, join(project, "assets/studio.hdr"));
    writeFileSync(
      join(project, "project.toml"),
      `name = "External glTF Integration"
default_scene = "scenes/main.scene.toml"

[render]
environment = "d4000000-0000-4000-8000-000000000002"
environment_intensity = 1
environment_rotation = 0
exposure = 1
background_visible = true
background_intensity = 1
background_rotation = 0
background_exposure = 1
background_blur = 0
`,
    );
    writeFileSync(
      join(project, "resources/environment.resource.toml"),
      `id = "d4000000-0000-4000-8000-000000000002"
type = "scrapbot.environment"
name = "Studio Small 09"

[environment]
source = "assets/studio.hdr"
`,
    );
    writeFileSync(
      join(project, "resources/helmet.resource.toml"),
      `id = "d4000000-0000-4000-8000-000000000001"
type = "scrapbot.model"
name = "Damaged Helmet"

[model]
source = "assets/DamagedHelmet.glb"
`,
    );
    writeFileSync(
      join(project, "scenes/main.scene.toml"),
      `[[entities]]
id = "d4100000-0000-4000-8000-000000000004"
name = "Camera"

[entities.transform]
position = [0, 0, 4]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.camera]
fov = 45
near = 0.1
far = 100

[[entities]]
id = "d4100000-0000-4000-8000-000000000002"
name = "Ambient Light"

[entities.ambient_light]
color = [1, 1, 1]
intensity = 0.35

[[entities]]
id = "d4100000-0000-4000-8000-000000000003"
name = "Key Light"

[entities.directional_light]
direction = [-0.5, -1.0, -0.5]
color = [1, 0.95, 0.9]
intensity = 1.75

[[entities]]
id = "d4100000-0000-4000-8000-000000000001"
name = "Damaged Helmet"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.model]
resource = "d4000000-0000-4000-8000-000000000001"
`,
    );

    const imported = runScrapbot(["import", project, "--json"]);
    if (imported.result?.products !== 2) {
      throw new Error("expected one model and one environment import product");
    }
    runScrapbot(["check", project, "--json"]);
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
      if (rendered.result?.renderables !== 1 || rendered.result?.draw_batches !== 1) {
        throw new Error("Damaged Helmet did not produce one renderable draw batch");
      }
    }

    const importedDirectory = join(project, ".scrapbot/imported");
    const metadataName = readdirSync(importedDirectory).find((name) =>
      name.endsWith(".model.json"),
    );
    if (!metadataName) {
      throw new Error("model import metadata was not produced");
    }
    const environmentMetadataName = readdirSync(importedDirectory).find((name) =>
      name.endsWith(".environment.json"),
    );
    if (!environmentMetadataName) {
      throw new Error("environment import metadata was not produced");
    }
    const environmentMetadata = JSON.parse(
      readFileSync(join(importedDirectory, environmentMetadataName), "utf8"),
    );
    let specularTexels = 0;
    for (let mip = 0; mip < 8; mip += 1) {
      const size = Math.max(128 >> mip, 1);
      specularTexels += size * size * 6;
    }
    const expectedEnvironmentBytes =
      (1024 * 512 + 32 * 32 * 6 + specularTexels) * 4 * 2;
    if (
      environmentMetadata.schema !== "scrapbot.environment.v3.rgba16f-sky-ibl" ||
      environmentMetadata.width !== 1024 ||
      environmentMetadata.height !== 512 ||
      environmentMetadata.irradiance_size !== 32 ||
      environmentMetadata.specular_size !== 128 ||
      environmentMetadata.specular_mip_count !== 8 ||
      environmentMetadata.byte_count !== expectedEnvironmentBytes
    ) {
      throw new Error("Studio HDRI metadata does not match the expected IBL product shape");
    }
    const metadata = JSON.parse(
      readFileSync(join(importedDirectory, metadataName), "utf8"),
    );
    if (
      metadata.schema !== "scrapbot.model.v5.alpha-materials" ||
      metadata.node_count !== 1 ||
      metadata.mesh_count !== 1 ||
      metadata.primitive_count !== 1 ||
      metadata.material_count !== 1 ||
      metadata.texture_count !== 5 ||
      metadata.ignored_texture_count !== 0 ||
      metadata.vertex_count < 10000 ||
      metadata.index_count < 10000
    ) {
      throw new Error("Damaged Helmet metadata does not match the expected real-world model shape");
    }
    console.log(
      `[external-gltf] imported Damaged Helmet: ${metadata.vertex_count} vertices, ${metadata.index_count} indices, ${metadata.texture_count} rendered PBR textures`,
    );
  } finally {
    rmSync(project, { force: true, recursive: true });
  }
}

try {
  main();
} catch (error) {
  console.error(`[external-gltf] ${error.message}`);
  process.exitCode = 1;
}
