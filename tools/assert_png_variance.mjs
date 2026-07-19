import fs from "node:fs";
import zlib from "node:zlib";

const path = process.argv[2];
if (!path) {
  throw new Error("usage: node tools/assert_png_variance.mjs <image.png>");
}

const png = fs.readFileSync(path);
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
if (!png.subarray(0, 8).equals(signature)) {
  throw new Error(`${path}: not a PNG`);
}

let offset = 8;
let width = 0;
let height = 0;
const compressed = [];
while (offset < png.length) {
  const length = png.readUInt32BE(offset);
  const type = png.toString("ascii", offset + 4, offset + 8);
  const data = png.subarray(offset + 8, offset + 8 + length);
  offset += 12 + length;
  if (type === "IHDR") {
    width = data.readUInt32BE(0);
    height = data.readUInt32BE(4);
    if (data[8] !== 8 || data[9] !== 6 || data[12] !== 0) {
      throw new Error(`${path}: expected non-interlaced RGBA8 PNG`);
    }
  } else if (type === "IDAT") {
    compressed.push(data);
  } else if (type === "IEND") {
    break;
  }
}

const packed = zlib.inflateSync(Buffer.concat(compressed));
const stride = width * 4;
const pixels = Buffer.alloc(stride * height);
const paeth = (a, b, c) => {
  const prediction = a + b - c;
  const pa = Math.abs(prediction - a);
  const pb = Math.abs(prediction - b);
  const pc = Math.abs(prediction - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
};
for (let y = 0, source = 0; y < height; y += 1) {
  const filter = packed[source++];
  const row = y * stride;
  const previous = row - stride;
  for (let x = 0; x < stride; x += 1) {
    const raw = packed[source++];
    const left = x >= 4 ? pixels[row + x - 4] : 0;
    const up = y > 0 ? pixels[previous + x] : 0;
    const upperLeft = y > 0 && x >= 4 ? pixels[previous + x - 4] : 0;
    const predictor = [0, left, up, Math.floor((left + up) / 2), paeth(left, up, upperLeft)][filter];
    if (predictor === undefined) {
      throw new Error(`${path}: unsupported PNG filter ${filter}`);
    }
    pixels[row + x] = (raw + predictor) & 0xff;
  }
}

const colors = new Set();
let minimum = 255;
let maximum = 0;
for (let index = 0; index < pixels.length; index += 4) {
  const red = pixels[index];
  const green = pixels[index + 1];
  const blue = pixels[index + 2];
  colors.add((red << 16) | (green << 8) | blue);
  minimum = Math.min(minimum, red, green, blue);
  maximum = Math.max(maximum, red, green, blue);
}
if (colors.size < 4 || maximum - minimum < 24) {
  throw new Error(`${path}: frame lacks meaningful rendered color variance`);
}
