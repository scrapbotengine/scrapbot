#!/usr/bin/env node

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const PRESETS = {
  small: { bays: 12, panelSegments: 32, archSegments: 24, columnSegments: 20 },
  showcase: { bays: 48, panelSegments: 36, archSegments: 48, columnSegments: 40 },
  unhinged: { bays: 96, panelSegments: 224, archSegments: 80, columnSegments: 64 },
};

function usage(message) {
  if (message) console.error(message);
  console.error("usage: node tools/generate_impossible_archive.mjs [--preset small|showcase|unhinged] [--out PATH] [--json] [--check]");
  process.exit(message ? 2 : 0);
}

function parseArgs(argv) {
  const options = {
    preset: "small",
    out: "examples/impossible-archive/assets/impossible-archive.glb",
    json: false,
    check: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") usage();
    if (argument === "--json" || argument === "--check") {
      options[argument.slice(2)] = true;
      continue;
    }
    if (argument === "--preset" || argument === "--out") {
      const value = argv[index + 1];
      if (!value) usage(`missing value for ${argument}`);
      options[argument.slice(2)] = value;
      index += 1;
      continue;
    }
    usage(`unknown argument: ${argument}`);
  }
  if (!PRESETS[options.preset]) usage(`unknown preset: ${options.preset}`);
  return options;
}

class Primitive {
  constructor(name, material) {
    this.name = name;
    this.material = material;
    this.positions = [];
    this.normals = [];
    this.indices = [];
  }

  vertex(position, normal) {
    const index = this.positions.length / 3;
    this.positions.push(...position);
    this.normals.push(...normal);
    return index;
  }

  quad(a, b, c, d, normal) {
    const base = this.positions.length / 3;
    for (const point of [a, b, c, d]) this.vertex(point, normal);
    this.indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
  }

  box(center, halfSize) {
    const [x, y, z] = center;
    const [hx, hy, hz] = halfSize;
    this.quad([x - hx, y - hy, z + hz], [x + hx, y - hy, z + hz], [x + hx, y + hy, z + hz], [x - hx, y + hy, z + hz], [0, 0, 1]);
    this.quad([x + hx, y - hy, z - hz], [x - hx, y - hy, z - hz], [x - hx, y + hy, z - hz], [x + hx, y + hy, z - hz], [0, 0, -1]);
    this.quad([x + hx, y - hy, z + hz], [x + hx, y - hy, z - hz], [x + hx, y + hy, z - hz], [x + hx, y + hy, z + hz], [1, 0, 0]);
    this.quad([x - hx, y - hy, z - hz], [x - hx, y - hy, z + hz], [x - hx, y + hy, z + hz], [x - hx, y + hy, z - hz], [-1, 0, 0]);
    this.quad([x - hx, y + hy, z + hz], [x + hx, y + hy, z + hz], [x + hx, y + hy, z - hz], [x - hx, y + hy, z - hz], [0, 1, 0]);
    this.quad([x - hx, y - hy, z - hz], [x + hx, y - hy, z - hz], [x + hx, y - hy, z + hz], [x - hx, y - hy, z + hz], [0, -1, 0]);
  }

  cylinderY(center, radius, halfHeight, segments) {
    const [cx, cy, cz] = center;
    const sideBase = this.positions.length / 3;
    for (let segment = 0; segment <= segments; segment += 1) {
      const angle = segment / segments * Math.PI * 2;
      const x = Math.cos(angle);
      const z = Math.sin(angle);
      this.vertex([cx + x * radius, cy - halfHeight, cz + z * radius], [x, 0, z]);
      this.vertex([cx + x * radius, cy + halfHeight, cz + z * radius], [x, 0, z]);
    }
    for (let segment = 0; segment < segments; segment += 1) {
      const base = sideBase + segment * 2;
      this.indices.push(base, base + 1, base + 3, base, base + 3, base + 2);
    }
    for (const sign of [-1, 1]) {
      const centerIndex = this.vertex([cx, cy + halfHeight * sign, cz], [0, sign, 0]);
      const rimBase = this.positions.length / 3;
      for (let segment = 0; segment <= segments; segment += 1) {
        const angle = segment / segments * Math.PI * 2;
        this.vertex([cx + Math.cos(angle) * radius, cy + halfHeight * sign, cz + Math.sin(angle) * radius], [0, sign, 0]);
      }
      for (let segment = 0; segment < segments; segment += 1) {
        if (sign > 0) this.indices.push(centerIndex, rimBase + segment, rimBase + segment + 1);
        else this.indices.push(centerIndex, rimBase + segment + 1, rimBase + segment);
      }
    }
  }

  arch(centerZ, radius, thickness, depth, segments) {
    const inner = radius - thickness;
    for (let segment = 0; segment < segments; segment += 1) {
      const a0 = segment / segments * Math.PI;
      const a1 = (segment + 1) / segments * Math.PI;
      const x0o = Math.cos(a0) * radius;
      const y0o = 8 + Math.sin(a0) * radius;
      const x1o = Math.cos(a1) * radius;
      const y1o = 8 + Math.sin(a1) * radius;
      const x0i = Math.cos(a0) * inner;
      const y0i = 8 + Math.sin(a0) * inner;
      const x1i = Math.cos(a1) * inner;
      const y1i = 8 + Math.sin(a1) * inner;
      for (const z of [centerZ - depth, centerZ + depth]) {
        const sign = z < centerZ ? -1 : 1;
        this.quad([x0i, y0i, z], [x1i, y1i, z], [x1o, y1o, z], [x0o, y0o, z], [0, 0, sign]);
      }
      const middle = (a0 + a1) * 0.5;
      const outerNormal = [Math.cos(middle), Math.sin(middle), 0];
      const innerNormal = [-outerNormal[0], -outerNormal[1], 0];
      this.quad([x0o, y0o, centerZ - depth], [x1o, y1o, centerZ - depth], [x1o, y1o, centerZ + depth], [x0o, y0o, centerZ + depth], outerNormal);
      this.quad([x1i, y1i, centerZ - depth], [x0i, y0i, centerZ - depth], [x0i, y0i, centerZ + depth], [x1i, y1i, centerZ + depth], innerNormal);
    }
  }

  ringZ(center, innerRadius, outerRadius, depth, segments) {
    const [cx, cy, cz] = center;
    for (let segment = 0; segment < segments; segment += 1) {
      const a0 = segment / segments * Math.PI * 2;
      const a1 = (segment + 1) / segments * Math.PI * 2;
      const points = [a0, a1].map((angle) => [Math.cos(angle), Math.sin(angle)]);
      for (const sign of [-1, 1]) {
        const z = cz + depth * sign;
        this.quad(
          [cx + points[0][0] * innerRadius, cy + points[0][1] * innerRadius, z],
          [cx + points[1][0] * innerRadius, cy + points[1][1] * innerRadius, z],
          [cx + points[1][0] * outerRadius, cy + points[1][1] * outerRadius, z],
          [cx + points[0][0] * outerRadius, cy + points[0][1] * outerRadius, z],
          [0, 0, sign],
        );
      }
      const middle = (a0 + a1) * 0.5;
      const normal = [Math.cos(middle), Math.sin(middle), 0];
      this.quad(
        [cx + points[0][0] * outerRadius, cy + points[0][1] * outerRadius, cz - depth],
        [cx + points[1][0] * outerRadius, cy + points[1][1] * outerRadius, cz - depth],
        [cx + points[1][0] * outerRadius, cy + points[1][1] * outerRadius, cz + depth],
        [cx + points[0][0] * outerRadius, cy + points[0][1] * outerRadius, cz + depth],
        normal,
      );
      this.quad(
        [cx + points[1][0] * innerRadius, cy + points[1][1] * innerRadius, cz - depth],
        [cx + points[0][0] * innerRadius, cy + points[0][1] * innerRadius, cz - depth],
        [cx + points[0][0] * innerRadius, cy + points[0][1] * innerRadius, cz + depth],
        [cx + points[1][0] * innerRadius, cy + points[1][1] * innerRadius, cz + depth],
        [-normal[0], -normal[1], 0],
      );
    }
  }
}

function reliefHeight(u, v, bay) {
  const border = Math.pow(Math.max(0, 1 - Math.min(u, 1 - u, v, 1 - v) * 10), 4) * 0.16;
  const rosetteRadius = Math.hypot(u - 0.5, v - 0.55);
  const rosette = Math.exp(-rosetteRadius * 9) * (0.09 + Math.cos(rosetteRadius * 92 + bay * 0.7) * 0.035);
  const script = Math.sin((u * 11 + Math.sin(v * 17 + bay)) * Math.PI) * Math.sin(v * 37 + bay * 1.7) * 0.018;
  const grain = Math.sin(u * 89 + bay * 3.1) * Math.sin(v * 71 - bay) * 0.008;
  return border + rosette + script + grain;
}

function addReliefPanel(primitive, side, bay, zCenter, bayLength, segments) {
  const wallX = side * 13.75;
  const yMin = 1.25;
  const yMax = 7.45;
  const zMin = zCenter - bayLength * 0.39;
  const zMax = zCenter + bayLength * 0.39;
  const base = primitive.positions.length / 3;
  const epsilon = 1 / segments;
  for (let row = 0; row <= segments; row += 1) {
    const v = row / segments;
    for (let column = 0; column <= segments; column += 1) {
      const u = column / segments;
      // Keep the complete relief surface in front of the shell. The procedural
      // variation can cross zero, so a non-zero plinth is required to avoid a
      // coplanar depth fight with the wall behind it.
      const height = 0.035 + reliefHeight(u, v, bay);
      const du = (reliefHeight(Math.min(1, u + epsilon), v, bay) - reliefHeight(Math.max(0, u - epsilon), v, bay)) / (epsilon * 2);
      const dv = (reliefHeight(u, Math.min(1, v + epsilon), bay) - reliefHeight(u, Math.max(0, v - epsilon), bay)) / (epsilon * 2);
      const normalLength = Math.hypot(1, du, dv) || 1;
      primitive.vertex(
        [wallX - side * height, yMin + (yMax - yMin) * v, zMin + (zMax - zMin) * u],
        [-side / normalLength, dv / normalLength, du / normalLength],
      );
    }
  }
  const stride = segments + 1;
  for (let row = 0; row < segments; row += 1) {
    for (let column = 0; column < segments; column += 1) {
      const a = base + row * stride + column;
      if (side < 0) primitive.indices.push(a, a + 1, a + stride + 1, a, a + stride + 1, a + stride);
      else primitive.indices.push(a, a + stride + 1, a + 1, a, a + stride, a + stride + 1);
    }
  }
}

function buildArchive(config) {
  const bayLength = 6;
  const startZ = 6;
  const endZ = startZ - config.bays * bayLength;
  const chunkCount = Math.ceil(config.bays / 4);
  const shell = new Primitive("Archive shell", 0);
  const stoneChunks = Array.from({ length: chunkCount }, (_, index) => new Primitive(`Archive stone ${index + 1}`, 0));
  const metalChunks = Array.from({ length: chunkCount }, (_, index) => new Primitive(`Archive brass ${index + 1}`, 1));
  const emberChunks = Array.from({ length: chunkCount }, (_, index) => new Primitive(`Archive glyphs ${index + 1}`, 2));

  shell.box([0, -0.45, (startZ + endZ) * 0.5], [14, 0.45, (startZ - endZ) * 0.5 + 2]);
  shell.box([-14.15, 8, (startZ + endZ) * 0.5], [0.4, 8.5, (startZ - endZ) * 0.5 + 2]);
  shell.box([14.15, 8, (startZ + endZ) * 0.5], [0.4, 8.5, (startZ - endZ) * 0.5 + 2]);

  for (let bay = 0; bay < config.bays; bay += 1) {
    const chunk = Math.floor(bay / 4);
    const stone = stoneChunks[chunk];
    const metal = metalChunks[chunk];
    const ember = emberChunks[chunk];
    const z = startZ - bay * bayLength;
    for (const side of [-1, 1]) {
      const x = side * 11.7;
      stone.cylinderY([x, 3.8, z], 0.72, 3.8, config.columnSegments);
      stone.cylinderY([x, 0.35, z], 1.05, 0.35, config.columnSegments);
      stone.cylinderY([x, 7.55, z], 1.08, 0.28, config.columnSegments);
      metal.cylinderY([x, 1.05, z], 0.82, 0.12, config.columnSegments);
      metal.cylinderY([x, 6.8, z], 0.84, 0.10, config.columnSegments);
      addReliefPanel(stone, side, bay, z - bayLength * 0.5, bayLength, config.panelSegments);
    }
    stone.arch(z, 11.7, 0.55, 0.28, config.archSegments);
    metal.arch(z - 0.32, 10.85, 0.12, 0.08, config.archSegments);

    for (let tile = -6; tile <= 6; tile += 1) {
      const x = tile * 2;
      const inset = ((bay * 17 + tile * 13) % 7) * 0.012;
      stone.box([x, 0.035 + inset, z - bayLength * 0.5], [0.94, 0.035 + inset, bayLength * 0.48]);
    }
    for (const side of [-1, 1]) {
      for (let glyph = 0; glyph < 5; glyph += 1) {
        const y = 1.7 + glyph * 1.15;
        const skew = Math.sin(bay * 2.3 + glyph) * 0.32;
        ember.box([side * 13.52, y, z - bayLength * (0.22 + skew * 0.08)], [0.035, 0.045, 0.62 + glyph * 0.05]);
      }
    }
  }

  const stone = stoneChunks.at(-1);
  const metal = metalChunks.at(-1);
  const ember = emberChunks.at(-1);
  shell.box([0, 8, endZ - 1.5], [14, 8.5, 0.45]);
  const portalZ = endZ - 0.48;
  for (let ring = 0; ring < 8; ring += 1) {
    const outerRadius = 6.3 - ring * 0.68;
    const innerRadius = outerRadius - (ring % 2 === 0 ? 0.24 : 0.42);
    const target = ring % 3 === 2 ? ember : ring % 2 === 0 ? metal : stone;
    target.ringZ([0, 7.7, portalZ + ring * 0.025], innerRadius, outerRadius, 0.08, config.archSegments * 2);
  }
  ember.box([0, 7.7, portalZ + 0.18], [0.8, 0.8, 0.06]);
  metal.box([0, 7.7, portalZ + 0.11], [1.35, 1.35, 0.1]);
  return [shell, ...stoneChunks, ...metalChunks, ...emberChunks];
}

function align4(value) {
  return (value + 3) & ~3;
}

function floatBuffer(values) {
  const buffer = Buffer.allocUnsafe(values.length * 4);
  for (let index = 0; index < values.length; index += 1) buffer.writeFloatLE(values[index], index * 4);
  return buffer;
}

function uintBuffer(values) {
  const buffer = Buffer.allocUnsafe(values.length * 4);
  for (let index = 0; index < values.length; index += 1) buffer.writeUInt32LE(values[index], index * 4);
  return buffer;
}

function buildGlb(primitives, preset) {
  const chunks = [];
  const bufferViews = [];
  const accessors = [];
  const meshPrimitives = [];
  let byteOffset = 0;

  function append(data, target) {
    const alignedLength = align4(data.length);
    const padded = alignedLength === data.length ? data : Buffer.concat([data, Buffer.alloc(alignedLength - data.length)]);
    const index = bufferViews.length;
    bufferViews.push({ buffer: 0, byteOffset, byteLength: data.length, target });
    chunks.push(padded);
    byteOffset += padded.length;
    return index;
  }

  for (const primitive of primitives) {
    const positionView = append(floatBuffer(primitive.positions), 34962);
    const normalView = append(floatBuffer(primitive.normals), 34962);
    const indexView = append(uintBuffer(primitive.indices), 34963);
    const min = [Infinity, Infinity, Infinity];
    const max = [-Infinity, -Infinity, -Infinity];
    for (let index = 0; index < primitive.positions.length; index += 3) {
      for (let axis = 0; axis < 3; axis += 1) {
        min[axis] = Math.min(min[axis], primitive.positions[index + axis]);
        max[axis] = Math.max(max[axis], primitive.positions[index + axis]);
      }
    }
    const positionAccessor = accessors.push({ bufferView: positionView, componentType: 5126, count: primitive.positions.length / 3, type: "VEC3", min, max }) - 1;
    const normalAccessor = accessors.push({ bufferView: normalView, componentType: 5126, count: primitive.normals.length / 3, type: "VEC3" }) - 1;
    const indexAccessor = accessors.push({ bufferView: indexView, componentType: 5125, count: primitive.indices.length, type: "SCALAR" }) - 1;
    meshPrimitives.push({ attributes: { POSITION: positionAccessor, NORMAL: normalAccessor }, indices: indexAccessor, material: primitive.material, mode: 4 });
  }

  const binary = Buffer.concat(chunks);
  const json = {
    asset: { version: "2.0", generator: `Scrapbot Impossible Archive (${preset})` },
    scene: 0,
    scenes: [{ name: "The Impossible Archive", nodes: [0] }],
    nodes: [{ name: "The Impossible Archive", mesh: 0 }],
    meshes: [{ name: "The Impossible Archive", primitives: meshPrimitives }],
    materials: [
      { name: "Obsidian slate", pbrMetallicRoughness: { baseColorFactor: [0.12, 0.14, 0.18, 1], metallicFactor: 0.08, roughnessFactor: 0.68 } },
      { name: "Ancient brass", pbrMetallicRoughness: { baseColorFactor: [0.34, 0.18, 0.055, 1], metallicFactor: 0.9, roughnessFactor: 0.24 } },
      { name: "Archive memory", emissiveFactor: [0.18, 0.72, 1], extensions: { KHR_materials_emissive_strength: { emissiveStrength: 7 } }, pbrMetallicRoughness: { baseColorFactor: [0.015, 0.08, 0.12, 1], metallicFactor: 0.2, roughnessFactor: 0.3 } },
    ],
    extensionsUsed: ["KHR_materials_emissive_strength"],
    buffers: [{ byteLength: binary.length }],
    bufferViews,
    accessors,
  };
  let jsonChunk = Buffer.from(JSON.stringify(json));
  jsonChunk = Buffer.concat([jsonChunk, Buffer.alloc(align4(jsonChunk.length) - jsonChunk.length, 0x20)]);
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(12 + 8 + jsonChunk.length + 8 + binary.length, 8);
  const jsonHeader = Buffer.alloc(8);
  jsonHeader.writeUInt32LE(jsonChunk.length, 0);
  jsonHeader.writeUInt32LE(0x4e4f534a, 4);
  const binaryHeader = Buffer.alloc(8);
  binaryHeader.writeUInt32LE(binary.length, 0);
  binaryHeader.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([header, jsonHeader, jsonChunk, binaryHeader, binary]);
}

const options = parseArgs(process.argv.slice(2));
const output = resolve(options.out);
const primitives = buildArchive(PRESETS[options.preset]);
const glb = buildGlb(primitives, options.preset);
const result = {
  preset: options.preset,
  output,
  bytes: glb.length,
  vertices: primitives.reduce((sum, primitive) => sum + primitive.positions.length / 3, 0),
  triangles: primitives.reduce((sum, primitive) => sum + primitive.indices.length / 3, 0),
  primitives: primitives.map((primitive) => ({ name: primitive.name, triangles: primitive.indices.length / 3 })),
};
if (options.check) {
  if (glb.readUInt32LE(0) !== 0x46546c67 || glb.readUInt32LE(4) !== 2 || glb.readUInt32LE(8) !== glb.length) {
    throw new Error("generated GLB header is inconsistent");
  }
  if (options.preset === "small" && (result.triangles !== 69_816 || result.vertices !== 58_584)) {
    throw new Error(`small preset contract drifted: ${result.vertices} vertices, ${result.triangles} triangles`);
  }
  if (options.preset === "small" && result.primitives.length !== 10) {
    throw new Error(`small preset spatial partition drifted: ${result.primitives.length} primitives`);
  }
} else {
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, glb);
}
if (options.json) console.log(JSON.stringify(result));
else if (options.check) console.log(`Impossible Archive ${options.preset} generator contract is valid`);
else console.log(`Generated ${result.triangles.toLocaleString()} triangles (${(result.bytes / 1024 / 1024).toFixed(1)} MiB) at ${output}`);
