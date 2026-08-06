import assert from "node:assert/strict";
import test from "node:test";
import {
  isVirtualGeometryErrorTier,
  parseArguments,
  validateRecordCapacity,
  validateResidencyPressure,
} from "./test_render_sequence.mjs";

test("virtual-geometry error validation accepts only bounded power-of-two tiers", () => {
  for (const tier of [1, 2, 4, 8, 16]) {
    assert.equal(isVirtualGeometryErrorTier(tier), true);
  }
  for (const invalid of [0, 3, 32, Number.NaN, Number.POSITIVE_INFINITY]) {
    assert.equal(isVirtualGeometryErrorTier(invalid), false);
  }
  assert.equal(isVirtualGeometryErrorTier(4, 2), false);
});

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

test("render sequence arguments preserve an independent editor camera script", () => {
  const options = parseArguments([
    "--project",
    "examples/virtual-wilds",
    "--capture-range",
    "850:857",
    "--editor",
    "--ui-script",
    "tests/fixtures/ui/virtual-wilds-editor-camera-history.json",
  ]);

  assert.equal(options.editor, true);
  assert.equal(
    options.uiScript,
    "tests/fixtures/ui/virtual-wilds-editor-camera-history.json",
  );
});

test("render sequence arguments preserve the long compact address-window replay", () => {
  const options = parseArguments([
    "--project",
    "examples/virtual-wilds",
    "--frames",
    "7000",
    "--capture-range",
    "6950:6957",
    "--require-residency-pressure",
    "--editor",
    "--ui-script",
    "tests/fixtures/ui/virtual-wilds-address-window.json",
  ]);

  assert.equal(options.frames, 7000);
  assert.equal(options.captureStart, 6950);
  assert.equal(options.captureEnd, 6957);
  assert.equal(options.requireResidencyPressure, true);
  assert.equal(
    options.uiScript,
    "tests/fixtures/ui/virtual-wilds-address-window.json",
  );
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
  assert.doesNotThrow(() =>
    validateResidencyPressure({
      frames: [
        {
          ...frame,
          render: {
            ...frame.render,
            dynamic_resolution: true,
            virtual_geometry_error_pixels: 8,
          },
        },
      ],
    }),
  );
  assert.throws(
    () =>
      validateResidencyPressure({
        frames: [
          {
            ...frame,
            render: {
              ...frame.render,
              dynamic_resolution: true,
              virtual_geometry_error_pixels: 3,
            },
          },
        ],
      }),
    /left its bounded tiers/,
  );
});
