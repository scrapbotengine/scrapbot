import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_FEATURES,
  parseFeatureSweepArguments,
  profileArguments,
} from "./profile_feature_sweep.mjs";

test("uses a bounded paired 1080p all-feature sweep by default", () => {
  const options = parseFeatureSweepArguments(["examples/sponza"]);
  assert.equal(options.resolution, "1920x1080");
  assert.deepEqual(options.features, DEFAULT_FEATURES);
});

test("accepts selected features and deterministic profile controls", () => {
  const options = parseFeatureSweepArguments([
    "examples/sponza",
    "--resolution",
    "1280x720",
    "--warmup",
    "3",
    "--frames",
    "7",
    "--feature",
    "screen-space-reflections",
    "--feature",
    "bloom",
    "--editor",
  ]);
  assert.equal(options.resolution, "1280x720");
  assert.equal(options.warmup, 3);
  assert.equal(options.frames, 7);
  assert.deepEqual(options.features, ["screen-space-reflections", "bloom"]);
  assert.equal(options.editor, true);
});

test("passes profile-only disabled features without mutating project data", () => {
  const options = parseFeatureSweepArguments([
    "examples/sponza",
    "--feature",
    "ambient-occlusion",
  ]);
  const args = profileArguments(
    options,
    ["ambient-occlusion"],
    "/tmp/profile/without-ao",
  );
  assert.deepEqual(args.slice(-2), [
    "--disabled-features",
    "ambient-occlusion",
  ]);
});

test("rejects unknown features and malformed resolutions", () => {
  assert.throws(
    () =>
      parseFeatureSweepArguments([
        "examples/sponza",
        "--feature",
        "make-it-fast",
      ]),
    /unknown render feature/,
  );
  assert.throws(
    () =>
      parseFeatureSweepArguments([
        "examples/sponza",
        "--resolution",
        "retina",
      ]),
    /invalid resolution/,
  );
});
