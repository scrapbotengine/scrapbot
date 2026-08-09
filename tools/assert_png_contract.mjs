import fs from "node:fs";
import { decodePngRgba8 } from "./png_rgba8.mjs";

const [imagePath, contractPath, option] = process.argv.slice(2);
if (!imagePath || !contractPath) {
  throw new Error(
    "usage: node tools/assert_png_contract.mjs <image.png> <contract.json> [--report]",
  );
}

const image = decodePngRgba8(imagePath);
const contract = JSON.parse(fs.readFileSync(contractPath, "utf8"));
if (
  image.width !== contract.width ||
  image.height !== contract.height
) {
  throw new Error(
    `${imagePath}: expected ${contract.width}x${contract.height}, got ` +
      `${image.width}x${image.height}`,
  );
}

const srgbToLinear = (value) => {
  const normalized = value / 255;
  return normalized <= 0.04045
    ? normalized / 12.92
    : ((normalized + 0.055) / 1.055) ** 2.4;
};

function regionMetrics(region) {
  const [x, y, width, height] = region.rect;
  if (
    !Number.isInteger(x) ||
    !Number.isInteger(y) ||
    !Number.isInteger(width) ||
    !Number.isInteger(height) ||
    x < 0 ||
    y < 0 ||
    width <= 0 ||
    height <= 0 ||
    x + width > image.width ||
    y + height > image.height
  ) {
    throw new Error(`${region.name}: invalid region ${region.rect}`);
  }

  const count = width * height;
  const rgb = [0, 0, 0];
  let luminance = 0;
  let luminanceSquared = 0;
  let chroma = 0;
  let neighborLuminanceDelta = 0;
  let neighborCount = 0;
  const luminanceAt = (column, row) => {
    const offset = (row * image.width + column) * 4;
    return (
      0.2126 * srgbToLinear(image.pixels[offset]) +
      0.7152 * srgbToLinear(image.pixels[offset + 1]) +
      0.0722 * srgbToLinear(image.pixels[offset + 2])
    );
  };
  for (let row = y; row < y + height; row += 1) {
    for (let column = x; column < x + width; column += 1) {
      const offset = (row * image.width + column) * 4;
      const red = image.pixels[offset];
      const green = image.pixels[offset + 1];
      const blue = image.pixels[offset + 2];
      rgb[0] += red / 255;
      rgb[1] += green / 255;
      rgb[2] += blue / 255;
      const sampleLuminance =
        0.2126 * srgbToLinear(red) +
        0.7152 * srgbToLinear(green) +
        0.0722 * srgbToLinear(blue);
      luminance += sampleLuminance;
      luminanceSquared += sampleLuminance * sampleLuminance;
      chroma += (Math.max(red, green, blue) - Math.min(red, green, blue)) / 255;
      if (column + 1 < x + width) {
        neighborLuminanceDelta += Math.abs(
          sampleLuminance - luminanceAt(column + 1, row),
        );
        neighborCount += 1;
      }
      if (row + 1 < y + height) {
        neighborLuminanceDelta += Math.abs(
          sampleLuminance - luminanceAt(column, row + 1),
        );
        neighborCount += 1;
      }
    }
  }
  const meanLuminance = luminance / count;
  return {
    mean_red: rgb[0] / count,
    mean_green: rgb[1] / count,
    mean_blue: rgb[2] / count,
    mean_luminance: meanLuminance,
    luminance_deviation: Math.sqrt(
      Math.max(luminanceSquared / count - meanLuminance ** 2, 0),
    ),
    mean_neighbor_luminance_delta:
      neighborCount > 0 ? neighborLuminanceDelta / neighborCount : 0,
    mean_chroma: chroma / count,
  };
}

const metrics = new Map();
const failures = [];
for (const region of contract.regions ?? []) {
  if (!region.name || metrics.has(region.name)) {
    throw new Error("every contract region must have a unique name");
  }
  const measured = regionMetrics(region);
  metrics.set(region.name, measured);
  for (const [metric, bounds] of Object.entries(region.expect ?? {})) {
    const value = measured[metric];
    if (value === undefined || !Array.isArray(bounds) || bounds.length !== 2) {
      throw new Error(`${region.name}: invalid ${metric} expectation`);
    }
    if (value < bounds[0] || value > bounds[1]) {
      failures.push(
        `${region.name}.${metric}: expected ${bounds[0]}..${bounds[1]}, ` +
          `got ${value.toFixed(6)}`,
      );
    }
  }
}

for (const comparison of contract.comparisons ?? []) {
  const left = metrics.get(comparison.left)?.[comparison.metric];
  const right = metrics.get(comparison.right)?.[comparison.metric];
  if (left === undefined || right === undefined) {
    throw new Error(
      `invalid comparison ${comparison.left}.${comparison.metric} ` +
        `${comparison.operator} ${comparison.right}.${comparison.metric}`,
    );
  }
  const margin = comparison.margin ?? 0;
  const passes = comparison.operator === "greater"
    ? left >= right + margin
    : comparison.operator === "less"
      ? left <= right - margin
      : false;
  if (!passes) {
    failures.push(
      `${comparison.left}.${comparison.metric} (${left.toFixed(6)}) must be ` +
        `${comparison.operator} than ${comparison.right}.${comparison.metric} ` +
        `(${right.toFixed(6)}) by ${margin}`,
    );
  }
}

if (option === "--report") {
  console.log(JSON.stringify(Object.fromEntries(metrics), null, 2));
}
if (failures.length > 0) {
  throw new Error(failures.join("\n"));
}
