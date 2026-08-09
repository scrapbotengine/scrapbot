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
const cliffSources = new Map([
  [
    "7b000000-0000-4000-8000-000000000003",
    "examples/virtual-wilds/assets/coastal_cliff_04/coastal_cliff_04_1k.gltf",
  ],
  [
    "7b000000-0000-4000-8000-00000000000e",
    "examples/virtual-wilds/assets/coastal_cliff_01/coastal_cliff_01_1k.gltf",
  ],
  [
    "7b000000-0000-4000-8000-00000000000f",
    "examples/virtual-wilds/assets/coastal_cliff_02/coastal_cliff_02_1k.gltf",
  ],
]);

const resources = {
  rocks: "7b000000-0000-4000-8000-00000000000b",
  boulder: "7b000000-0000-4000-8000-00000000000c",
  fir: "7b000000-0000-4000-8000-00000000000d",
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
  firs: configuredCount("VIRTUAL_WILDS_FIRS", 12),
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

function sceneTransform(source, entityName) {
  const block = source
    .split("[[entities]]")
    .find((candidate) => candidate.includes(`name = "${entityName}"`));
  if (!block) {
    throw new Error(`Virtual Wilds ground entity ${entityName} is missing`);
  }
  const readVector = (field) => {
    const match = block.match(new RegExp(`^${field} = (\\[[^\\n]+\\])$`, "m"));
    if (!match) {
      throw new Error(`${entityName} has no ${field} transform field`);
    }
    return JSON.parse(match[1]);
  };
  return {
    position: readVector("position"),
    rotation: readVector("rotation"),
    scale: readVector("scale"),
    resource: block.match(/^resource = "([^"]+)"$/m)?.[1],
  };
}

function transformPoint(point, transform) {
  let [x, y, z] = point.map((value, axis) => value * transform.scale[axis]);
  const [rx, ry, rz] = transform.rotation;
  [y, z] = [y * Math.cos(rx) - z * Math.sin(rx), y * Math.sin(rx) + z * Math.cos(rx)];
  [x, z] = [x * Math.cos(ry) + z * Math.sin(ry), -x * Math.sin(ry) + z * Math.cos(ry)];
  [x, y] = [x * Math.cos(rz) - y * Math.sin(rz), x * Math.sin(rz) + y * Math.cos(rz)];
  return [
    x + transform.position[0],
    y + transform.position[1],
    z + transform.position[2],
  ];
}

function subtract(left, right) {
  return left.map((value, axis) => value - right[axis]);
}

function cross(left, right) {
  return [
    left[1] * right[2] - left[2] * right[1],
    left[2] * right[0] - left[0] * right[2],
    left[0] * right[1] - left[1] * right[0],
  ];
}

function length(value) {
  return Math.hypot(...value);
}

function readAccessor(gltf, binary, accessorIndex) {
  const accessor = gltf.accessors[accessorIndex];
  const view = gltf.bufferViews[accessor.bufferView];
  const componentBytes = {5121: 1, 5123: 2, 5125: 4, 5126: 4}[accessor.componentType];
  const components = {SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4}[accessor.type];
  if (!componentBytes || !components) {
    throw new Error(`unsupported glTF accessor ${accessor.componentType}/${accessor.type}`);
  }
  const stride = view.byteStride ?? componentBytes * components;
  const base = (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0);
  const data = new DataView(binary.buffer, binary.byteOffset, binary.byteLength);
  const readComponent = (offset) => {
    if (accessor.componentType === 5121) return data.getUint8(offset);
    if (accessor.componentType === 5123) return data.getUint16(offset, true);
    if (accessor.componentType === 5125) return data.getUint32(offset, true);
    return data.getFloat32(offset, true);
  };
  return {
    count: accessor.count,
    read(index) {
      const offset = base + index * stride;
      if (components === 1) return readComponent(offset);
      return Array.from(
        { length: components },
        (_, component) => readComponent(offset + component * componentBytes),
      );
    },
  };
}

function loadCliffGeometry(resource) {
  const source = cliffSources.get(resource);
  if (!source) {
    throw new Error(`Virtual Wilds ground resource ${resource} has no source geometry`);
  }
  const sourcePath = resolve(repositoryRoot, source);
  const gltf = JSON.parse(readFileSync(sourcePath, "utf8"));
  const binaryPath = resolve(dirname(sourcePath), gltf.buffers[0].uri);
  const binary = readFileSync(binaryPath);
  const primitive = gltf.meshes[0].primitives[0];
  return {
    positions: readAccessor(gltf, binary, primitive.attributes.POSITION),
    indices: readAccessor(gltf, binary, primitive.indices),
  };
}

function groundedFirPlacements(source, count) {
  if (count === 0) return [];
  const groundNames = [
    "Western Canyon Wall",
    "Western Canyon Reach",
    "Outer Headland",
    "Near Great Cliff",
    "Cove Gate Cliff",
    "Far Great Cliff",
    "Drowned Horizon Ridge",
  ];
  const grounds = groundNames.map((name) => sceneTransform(source, name));
  const geometryByResource = new Map();
  const candidates = [];
  for (const ground of grounds) {
    let geometry = geometryByResource.get(ground.resource);
    if (!geometry) {
      geometry = loadCliffGeometry(ground.resource);
      geometryByResource.set(ground.resource, geometry);
    }
    for (let index = 0; index < geometry.indices.count; index += 3) {
      const a = transformPoint(geometry.positions.read(geometry.indices.read(index)), ground);
      const b = transformPoint(geometry.positions.read(geometry.indices.read(index + 1)), ground);
      const c = transformPoint(geometry.positions.read(geometry.indices.read(index + 2)), ground);
      const normalArea = cross(subtract(b, a), subtract(c, a));
      const doubleArea = length(normalArea);
      if (doubleArea <= 0.000001 || normalArea[1] / doubleArea < 0.9) continue;
      const centroid = a.map((value, axis) => (value + b[axis] + c[axis]) / 3);
      if (centroid[1] < 1.5 || centroid[2] < -230 || centroid[2] > 45) continue;
      // Area-weighted triangle admission keeps the offline scatter independent
      // of source tessellation density while retaining only a bounded candidate set.
      const admission = Math.min(1, doubleArea * 0.55);
      if (random() > admission) continue;
      const root = Math.sqrt(random());
      const blend = random();
      const weights = [1 - root, root * (1 - blend), root * blend];
      const point = a.map(
        (value, axis) => value * weights[0] + b[axis] * weights[1] + c[axis] * weights[2],
      );
      const normal = normalArea.map((value) => value / doubleArea);
      candidates.push(point.map((value, axis) => value - normal[axis] * 0.025));
    }
  }
  const groundCellSize = 3;
  const groundCells = new Map();
  const groundCellKey = (x, z) =>
    `${Math.floor(x / groundCellSize)},${Math.floor(z / groundCellSize)}`;
  for (const point of candidates) {
    const key = groundCellKey(point[0], point[2]);
    const cell = groundCells.get(key) ?? [];
    cell.push(point);
    groundCells.set(key, cell);
  }
  const nearbyGround = (x, z) => {
    const cellX = Math.floor(x / groundCellSize);
    const cellZ = Math.floor(z / groundCellSize);
    let nearest = undefined;
    let nearestDistanceSquared = 1.25 ** 2;
    for (let offsetX = -1; offsetX <= 1; offsetX += 1) {
      for (let offsetZ = -1; offsetZ <= 1; offsetZ += 1) {
        const cell = groundCells.get(`${cellX + offsetX},${cellZ + offsetZ}`) ?? [];
        for (const point of cell) {
          const dx = point[0] - x;
          const dz = point[2] - z;
          const distanceSquared = dx * dx + dz * dz;
          if (distanceSquared < nearestDistanceSquared) {
            nearest = point;
            nearestDistanceSquared = distanceSquared;
          }
        }
      }
    }
    return nearest;
  };

  // Fisher-Yates gives us a deterministic permutation without relying on a
  // non-transitive random sort comparator.
  for (let index = candidates.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(random() * (index + 1));
    [candidates[index], candidates[swapIndex]] = [candidates[swapIndex], candidates[index]];
  }
  const selected = [];
  const minimumSpacing = 12;
  for (const candidate of candidates) {
    const scale = between(3.2, 4.2);
    const scaleX = scale * between(0.9, 1.1);
    const yaw = between(-Math.PI, Math.PI);
    const childRootsAreGrounded = [1, 2].every((childOffset) => {
      const x = candidate[0] + Math.cos(yaw) * scaleX * childOffset;
      const z = candidate[2] - Math.sin(yaw) * scaleX * childOffset;
      const ground = nearbyGround(x, z);
      return ground !== undefined && Math.abs(ground[1] - candidate[1]) <= 0.45;
    });
    if (
      childRootsAreGrounded &&
      selected.every((other) => {
        const offset = subtract(candidate, other.position);
        return offset[0] * offset[0] + offset[2] * offset[2] >= minimumSpacing ** 2;
      })
    ) {
      selected.push({
        position: candidate,
        rotation: [0, yaw, 0],
        scale: [scaleX, scale * between(0.94, 1.14), scaleX],
      });
      if (selected.length === count) return selected;
    }
  }
  throw new Error(`only found ${selected.length} grounded fir sites for ${count} groves`);
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

// Every photogrammetry fir root contains three distinct trees.
// Their primary roots are sampled directly from upward-facing triangles on the
// same transformed cliff meshes the renderer consumes. A grove is admitted
// only when neighboring surface samples also support both offset child roots.
const firPlacements = groundedFirPlacements(source, counts.firs);
for (let index = 0; index < firPlacements.length; index += 1) {
  const placement = firPlacements[index];
  addEntity({
    name: `Generated Cliff Fir Grove ${index + 1}`,
    resource: resources.fir,
    position: placement.position,
    rotation: placement.rotation,
    scale: placement.scale,
    shadowCaster: index % 6 === 0,
  });
}

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
