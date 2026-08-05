import assert from "node:assert/strict";
import test from "node:test";
import {
  parseArguments,
  validateRecordCapacity,
  validateResidencyPressure,
} from "./test_render_sequence.mjs";

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

test("render sequence arguments describe a CPU-reference comparison", () => {
  const options = parseArguments([
    "--project",
    "examples/virtual-geometry-lab",
    "--capture-range",
    "40:48",
    "--cpu-reference",
    "--minimum-psnr",
    "48",
  ]);

  assert.equal(options.cpuReference, true);
  assert.equal(options.minimumPsnr, 48);
});

test("render sequence arguments describe bounded residency pressure", () => {
  const options = parseArguments([
    "--project",
    "examples/virtual-geometry-lab",
    "--capture-range",
    "40:48",
    "--require-residency-pressure",
  ]);

  assert.equal(options.requireResidencyPressure, true);
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

test("record capacity validation rejects silent GPU record loss", () => {
  assert.throws(
    () =>
      validateRecordCapacity({
        frames: [{ index: 7, render: { visible_record_overflow: 1 } }],
      }),
    /visible_record_overflow is nonzero at frame 7/,
  );
});

test("residency validation requires bounded pressure and healthy admission", () => {
  const frame = {
    index: 8,
    render: {
      virtual_geometry: true,
      virtual_geometry_pages: 16,
      virtual_geometry_resident_pages: 8,
      virtual_geometry_page_budget_bytes: 100,
      virtual_geometry_page_resident_bytes: 95,
      virtual_geometry_deferred_groups: 3,
      virtual_geometry_page_request_overflow: 0,
      virtual_geometry_page_read_failures: 0,
      virtual_geometry_error_pixels: 1,
    },
    counter_deltas: {},
  };
  assert.doesNotThrow(() => validateResidencyPressure({ frames: [frame] }));
  assert.throws(
    () =>
      validateResidencyPressure({
        frames: [{ ...frame, render: { ...frame.render, virtual_geometry_pages: 8 } }],
      }),
    /does not exercise bounded/,
  );
  assert.throws(
    () =>
      validateResidencyPressure({
        frames: [
          frame,
          {
            ...frame,
            index: 9,
            render: { ...frame.render, virtual_geometry_error_pixels: 2 },
          },
        ],
      }),
    /changed the one-pixel/,
  );
});
