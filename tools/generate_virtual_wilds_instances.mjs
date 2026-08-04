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
  heroPine: "7b000000-0000-4000-8000-00000000000d",
  forestPines: [
    "7b000000-0000-4000-8000-00000000000e",
    "7b000000-0000-4000-8000-00000000000f",
    "7b000000-0000-4000-8000-000000000010",
    "7b000000-0000-4000-8000-000000000011",
    "7b000000-0000-4000-8000-000000000012",
    "7b000000-0000-4000-8000-000000000013",
  ],
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
  heroPines: configuredCount("VIRTUAL_WILDS_HERO_PINES", 5),
  forestPines: configuredCount("VIRTUAL_WILDS_FOREST_PINES", 560),
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

// Each photogrammetry pine root contains three distinct saplings. A small hero
// grove brings alpha-masked needles close to the route without multiplying its
// 398k-triangle source into an unbounded GPU submission table.
for (let index = 0; index < counts.heroPines; index += 1) {
  const side = index % 2 === 0 ? -1 : 1;
  const lateral = between(11, 17);
  const scale = between(4.5, 6.4);
  addEntity({
    name: `Generated Hero Pine Grove ${index + 1}`,
    resource: resources.heroPine,
    position: [
      side * lateral,
      2.4 + (lateral - 11) * 0.22 + between(-0.25, 0.35),
      4 - index * 42 + between(-4, 4),
    ],
    rotation: [between(-0.025, 0.025), between(-Math.PI, Math.PI), between(-0.02, 0.02)],
    scale: [
      scale * between(0.88, 1.12),
      scale * between(0.9, 1.18),
      scale * between(0.88, 1.12),
    ],
    shadowCaster: index % 3 === 0,
  });
}

// Hundreds of tiny CC0 forest-kit models form the distant canopy. They remain
// ordinary model components: shared resources, transforms, batching, frustum
// culling, and sparse shadows all flow through the same public engine path.
for (let index = 0; index < counts.forestPines; index += 1) {
  const side = index % 2 === 0 ? -1 : 1;
  const lateral = between(42, 78);
  const scale = between(4.8, 9.2);
  addEntity({
    name: `Generated Forest Pine ${index + 1}`,
    resource: resources.forestPines[index % resources.forestPines.length],
    position: [
      side * lateral + Math.sin(index * 2.399963) * 7,
      18 + (lateral - 42) * 0.28 + between(-0.5, 0.7),
      between(-215, 45),
    ],
    rotation: [between(-0.035, 0.035), between(-Math.PI, Math.PI), between(-0.03, 0.03)],
    scale: [
      scale * between(0.82, 1.18),
      scale * between(0.9, 1.25),
      scale * between(0.82, 1.18),
    ],
    shadowCaster: index % 24 === 0,
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
