import assert from "node:assert/strict";
import test from "node:test";

import { parseSweepArguments } from "./profile_resolution_sweep.mjs";

test("uses a bounded default 540p through 1080p sweep", () => {
  const options = parseSweepArguments(["examples/minimal"]);
  assert.deepEqual(
    options.resolutions.map((resolution) => resolution.text),
    ["960x540", "1280x720", "1920x1080"],
  );
});

test("accepts repeated resolutions and deterministic profile controls", () => {
  const options = parseSweepArguments([
    "examples/sponza",
    "--resolution",
    "320x180",
    "--resolution",
    "640x360",
    "--warmup",
    "3",
    "--frames",
    "7",
    "--editor",
    "--cpu-culling",
  ]);
  assert.deepEqual(
    options.resolutions.map((resolution) => resolution.text),
    ["320x180", "640x360"],
  );
  assert.equal(options.warmup, 3);
  assert.equal(options.frames, 7);
  assert.equal(options.editor, true);
  assert.equal(options.cpu_culling, true);
});

test("rejects malformed and zero-sized resolutions", () => {
  assert.throws(
    () => parseSweepArguments(["examples/minimal", "--resolution", "0x720"]),
    /invalid resolution/,
  );
  assert.throws(
    () => parseSweepArguments(["examples/minimal", "--resolution", "wide"]),
    /invalid resolution/,
  );
});
