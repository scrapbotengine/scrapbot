import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scenePath = resolve(
  repositoryRoot,
  "examples/virtual-wilds/scenes/main.scene.toml",
);
const beginMarker = "# BEGIN GENERATED LANDSCAPE INSTANCES";
const endMarker = "# END GENERATED LANDSCAPE INSTANCES";

const resources = {
  rocks: "7b000000-0000-4000-8000-00000000000b",
  boulder: "7b000000-0000-4000-8000-00000000000c",
};

function configuredCount(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined) {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${name} must be a non-negative integer`);
  }
  return value;
}

const counts = {
  rocks: configuredCount("VIRTUAL_WILDS_ROCKS", 1),
  boulders: configuredCount("VIRTUAL_WILDS_BOULDERS", 5),
};

let state = 0x51a7f00d;
function random() {
  state ^= state << 13;
  state ^= state >>> 17;
  state ^= state << 5;
  return (state >>> 0) / 0x1_0000_0000;
}

function between(minimum, maximum) {
  return minimum + (maximum - minimum) * random();
}

function format(value) {
  const normalized = Math.abs(value) < 0.00005 ? 0 : value;
  return Number(normalized.toFixed(4)).toString();
}

function vector(values) {
  return `[${values.map(format).join(", ")}]`;
}

let entityIndex = 1;
const entities = [];
function addEntity({ name, resource, position, rotation, scale, shadowCaster }) {
  const suffix = entityIndex.toString(16).padStart(12, "0");
  entityIndex += 1;
  const shadow = shadowCaster ? "\n[entities.shadow_caster]\n" : "";
  entities.push(`[[entities]]
id = "7b200000-0000-4000-8000-${suffix}"
name = "${name}"

[entities.transform]
position = ${vector(position)}
rotation = ${vector(rotation)}
scale = ${vector(scale)}

[entities.model]
resource = "${resource}"
${shadow}
[entities.shadow_receiver]
`);
}

// Shore formations occupy both the visible coves and farther reaches, giving
// camera and shadow culling enough repeated medium geometry to reject.
for (let index = 0; index < counts.rocks; index += 1) {
  const side = index % 2 === 0 ? -1 : 1;
  addEntity({
    name: `Generated Shore Formation ${index + 1}`,
    resource: resources.rocks,
    position: [side * between(10, 25), between(-1.2, 1.1), between(-178, 18)],
    rotation: [between(-0.12, 0.12), between(-Math.PI, Math.PI), between(-0.1, 0.1)],
    scale: [between(0.7, 2.1), between(0.65, 1.8), between(0.7, 2.1)],
    shadowCaster: index % 5 === 0,
  });
}

// Shared boulders punctuate the authored terraces without multiplying the
// much heavier cliff scans. The larger procedural scatter workload remains in
// the project script, where it exercises public Geometry and ECS APIs.
for (let index = 0; index < counts.boulders; index += 1) {
  const side = random() < 0.5 ? -1 : 1;
  const lateral = between(12, 43);
  const terrace = Math.floor(between(0, 4));
  const uniformScale = between(0.65, 2.7) * (1 + terrace * 0.12);
  addEntity({
    name: `Generated Talus Boulder ${index + 1}`,
    resource: resources.boulder,
    position: [
      side * lateral,
      -0.2 + (lateral - 12) * 0.19 + terrace * 0.55 + between(-0.3, 0.3),
      between(-195, 28),
    ],
    rotation: [between(-0.22, 0.22), between(-Math.PI, Math.PI), between(-0.2, 0.2)],
    scale: [
      uniformScale * between(0.8, 1.3),
      uniformScale * between(0.75, 1.35),
      uniformScale * between(0.8, 1.3),
    ],
    shadowCaster: false,
  });
}

const source = readFileSync(scenePath, "utf8");
const begin = source.indexOf(beginMarker);
const end = source.indexOf(endMarker);
if (begin < 0 || end < begin) {
  throw new Error("Virtual Wilds generated-instance markers are missing or invalid");
}

const prefix = source.slice(0, begin + beginMarker.length);
const suffix = source.slice(end);
const output = `${prefix}\n\n${entities.join("\n")}\n${suffix}`;
if (process.argv.includes("--check")) {
  if (output !== source) {
    throw new Error(
      "Virtual Wilds landscape instances are stale; run `node tools/generate_virtual_wilds_instances.mjs`",
    );
  }
  console.log(`verified ${entities.length} Virtual Wilds landscape instances`);
} else {
  writeFileSync(scenePath, output);
  console.log(`generated ${entities.length} Virtual Wilds landscape instances`);
}
