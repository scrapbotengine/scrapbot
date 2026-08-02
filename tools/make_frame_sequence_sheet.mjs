#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { decodePngRgba8, encodePngRgba8 } from "./png_rgba.mjs";

const arguments_ = process.argv.slice(2);
const framesDirectory = arguments_[0];
const outputPath = arguments_[1];
if (!framesDirectory || !outputPath) {
  throw new Error(
    "usage: node tools/make_frame_sequence_sheet.mjs <frames-directory> <output.png> [--columns N] [--cell-width N] [--difference-scale N]",
  );
}

function numericOption(name, fallback) {
  const index = arguments_.indexOf(name);
  if (index < 0) return fallback;
  const value = Number(arguments_[index + 1]);
  if (!Number.isFinite(value) || value <= 0) throw new Error(`expected positive ${name}`);
  return Math.floor(value);
}

const columns = numericOption("--columns", 4);
const cellWidth = numericOption("--cell-width", 400);
const differenceScale = numericOption("--difference-scale", 6);
const framePaths = fs
  .readdirSync(framesDirectory)
  .filter((name) => /^frame-\d+\.png$/.test(name))
  .sort()
  .map((name) => path.join(framesDirectory, name));
if (framePaths.length < 2) {
  throw new Error(`${framesDirectory}: expected at least two frame-NNNNNN.png files`);
}

const frames = framePaths.map(decodePngRgba8);
const { width, height } = frames[0];
for (let index = 1; index < frames.length; index += 1) {
  if (frames[index].width !== width || frames[index].height !== height) {
    throw new Error(`${framePaths[index]}: frame dimensions differ`);
  }
}

const cellHeight = Math.max(1, Math.round(height * cellWidth / width));
const rows = Math.ceil(frames.length / columns);
const sheetWidth = columns * cellWidth;
const sheetHeight = rows * cellHeight;
const sheet = Buffer.alloc(sheetWidth * sheetHeight * 4, 18);
const differences = Buffer.alloc(sheet.length, 0);
for (let index = 3; index < sheet.length; index += 4) sheet[index] = 255;
for (let index = 3; index < differences.length; index += 4) differences[index] = 255;

function blitScaled(target, frame, cellIndex, differenceFrom) {
  const cellX = (cellIndex % columns) * cellWidth;
  const cellY = Math.floor(cellIndex / columns) * cellHeight;
  for (let y = 0; y < cellHeight; y += 1) {
    const sourceY = Math.min(height - 1, Math.floor(y * height / cellHeight));
    for (let x = 0; x < cellWidth; x += 1) {
      const sourceX = Math.min(width - 1, Math.floor(x * width / cellWidth));
      const source = (sourceY * width + sourceX) * 4;
      const destination = ((cellY + y) * sheetWidth + cellX + x) * 4;
      for (let channel = 0; channel < 3; channel += 1) {
        const value = differenceFrom
          ? Math.min(255, Math.abs(frame.pixels[source + channel] - differenceFrom.pixels[source + channel]) * differenceScale)
          : frame.pixels[source + channel];
        target[destination + channel] = value;
      }
      target[destination + 3] = 255;
    }
  }
}

const transitions = [];
for (let index = 0; index < frames.length; index += 1) {
  blitScaled(sheet, frames[index], index, null);
  if (index === 0) continue;
  blitScaled(differences, frames[index], index, frames[index - 1]);
  let changedPixels = 0;
  let absoluteDifference = 0;
  const maximumHistogram = new Uint32Array(256);
  for (let offset = 0; offset < frames[index].pixels.length; offset += 4) {
    let maximum = 0;
    for (let channel = 0; channel < 3; channel += 1) {
      const difference = Math.abs(
        frames[index].pixels[offset + channel] - frames[index - 1].pixels[offset + channel],
      );
      absoluteDifference += difference;
      maximum = Math.max(maximum, difference);
    }
    if (maximum > 0) changedPixels += 1;
    maximumHistogram[maximum] += 1;
  }
  const percentileTarget = Math.ceil(width * height * 0.99);
  let cumulative = 0;
  let p99MaximumDifference = 0;
  for (let value = 0; value < maximumHistogram.length; value += 1) {
    cumulative += maximumHistogram[value];
    if (cumulative >= percentileTarget) {
      p99MaximumDifference = value;
      break;
    }
  }
  transitions.push({
    from: path.basename(framePaths[index - 1]),
    to: path.basename(framePaths[index]),
    changed_pixel_fraction: changedPixels / (width * height),
    mean_absolute_rgb_difference: absoluteDifference / (width * height * 3),
    p99_maximum_rgb_difference: p99MaximumDifference,
  });
}

fs.mkdirSync(path.dirname(path.resolve(outputPath)), { recursive: true });
encodePngRgba8(outputPath, sheetWidth, sheetHeight, sheet);
const extension = path.extname(outputPath);
const differencePath = `${outputPath.slice(0, -extension.length)}-differences${extension}`;
encodePngRgba8(differencePath, sheetWidth, sheetHeight, differences);
console.log(JSON.stringify({
  schema_version: 1,
  frames: framePaths.map((framePath) => path.basename(framePath)),
  contact_sheet: path.resolve(outputPath),
  difference_sheet: path.resolve(differencePath),
  difference_scale: differenceScale,
  transitions,
}));
