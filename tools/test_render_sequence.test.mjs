import assert from "node:assert/strict";
import test from "node:test";
import { parseArguments } from "./test_render_sequence.mjs";

test("render sequence arguments describe a bounded temporal capture", () => {
  const options = parseArguments([
    "--project",
    "examples/virtual-wilds",
    "--warmup",
    "120",
    "--frames",
    "120",
    "--capture-range",
    "104:111",
    "--stable-frontier",
    "--golden-dir",
    "tests/fixtures/visual/goldens/virtual-wilds-metal",
    "--minimum-psnr",
    "34",
  ]);

  assert.equal(options.project, "examples/virtual-wilds");
  assert.equal(options.warmup, 120);
  assert.equal(options.frames, 120);
  assert.equal(options.captureStart, 104);
  assert.equal(options.captureEnd, 111);
  assert.equal(options.stableFrontier, true);
  assert.equal(options.minimumPsnr, 34);
});

test("render sequence arguments reject reversed capture ranges", () => {
  assert.throws(
    () =>
      parseArguments([
        "--project",
        "examples/minimal",
        "--capture-range",
        "8:4",
      ]),
    /inclusive START:END/,
  );
});

test("render sequence arguments describe a transition capture", () => {
  const options = parseArguments([
    "--project",
    "tests/fixtures/gpu-virtual-geometry-pressure",
    "--capture-range",
    "31:56",
    "--require-transition",
  ]);

  assert.equal(options.requireTransition, true);
  assert.equal(options.stableFrontier, false);
  assert.equal(options.captureEnd, 56);
});

test("render sequence arguments describe sustained transition activity", () => {
  const options = parseArguments([
    "--project",
    "examples/virtual-wilds",
    "--capture-range",
    "200:224",
    "--require-transition-activity",
  ]);

  assert.equal(options.requireTransitionActivity, true);
  assert.equal(options.requireTransition, false);
  assert.equal(options.stableFrontier, false);
});

test("render sequence arguments keep settled and transitioning gates distinct", () => {
  assert.throws(
    () =>
      parseArguments([
        "--project",
        "examples/minimal",
        "--stable-frontier",
        "--require-transition",
      ]),
    /mutually exclusive/,
  );
});
