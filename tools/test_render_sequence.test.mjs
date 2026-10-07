import assert from "node:assert/strict";
import test from "node:test";
import { parseArguments } from "./test_render_sequence.mjs";

test("render sequence arguments reject retired virtual-geometry gates", () => {
  for (const flag of [
    "--stable-frontier",
    "--require-transition",
    "--require-transition-activity",
    "--require-residency-pressure",
  ]) {
    assert.throws(
      () => parseArguments(["--project", "examples/minimal", flag]),
      /unknown or incomplete argument/,
    );
  }
});


test("render sequence arguments describe a bounded temporal capture", () => {
  const options = parseArguments([
    "--project",
    "examples/ecs-showcase",
    "--warmup",
    "120",
    "--frames",
    "120",
    "--capture-range",
    "104:111",
    "--golden-dir",
    "tests/fixtures/visual/goldens/indexed-metal",
    "--minimum-psnr",
    "34",
  ]);

  assert.equal(options.project, "examples/ecs-showcase");
  assert.equal(options.warmup, 120);
  assert.equal(options.frames, 120);
  assert.equal(options.captureStart, 104);
  assert.equal(options.captureEnd, 111);
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



test("render sequence arguments describe a CPU-reference comparison", () => {
  const options = parseArguments([
    "--project",
    "tests/fixtures/gpu-lod",
    "--capture-range",
    "40:48",
    "--cpu-reference",
    "--minimum-psnr",
    "48",
  ]);

  assert.equal(options.cpuReference, true);
  assert.equal(options.minimumPsnr, 48);
});


test("render sequence arguments preserve an independent editor camera script", () => {
  const options = parseArguments([
    "--project",
    "examples/ecs-showcase",
    "--capture-range",
    "850:857",
    "--editor",
    "--ui-script",
    "tests/fixtures/ui/clustered-lights-paused.json",
  ]);

  assert.equal(options.editor, true);
  assert.equal(
    options.uiScript,
    "tests/fixtures/ui/clustered-lights-paused.json",
  );
});
