import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { decodePngRgba8, encodePngRgba8 } from "./png_rgba.mjs";

test("RGBA8 PNG encoding round-trips through the diagnostic decoder", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "scrapbot-png-rgba-"));
  const output = path.join(directory, "roundtrip.png");
  const pixels = Buffer.from([
    255, 0, 0, 255,
    0, 255, 0, 128,
    0, 0, 255, 64,
    255, 255, 255, 0,
  ]);
  try {
    encodePngRgba8(output, 2, 2, pixels);
    const decoded = decodePngRgba8(output);
    assert.equal(decoded.width, 2);
    assert.equal(decoded.height, 2);
    assert.deepEqual(decoded.pixels, pixels);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
