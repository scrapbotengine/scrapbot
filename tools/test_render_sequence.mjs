import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePngRgba8 } from "./png_rgba.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function parseArguments(arguments_) {
  const options = {
    binary: "bin/scrapbot",
    warmup: 60,
    frames: 120,
    captureRange: "60:67",
    resolution: "1280x720",
    out: path.join(os.tmpdir(), "scrapbot-render-sequence"),
    stableFrontier: false,
    requireTransition: false,
    goldenDirectory: undefined,
    minimumPsnr: 32,
  };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--stable-frontier") {
      options.stableFrontier = true;
      continue;
    }
    if (argument === "--require-transition") {
      options.requireTransition = true;
      continue;
    }
    const names = new Map([
      ["--binary", "binary"],
      ["--project", "project"],
      ["--warmup", "warmup"],
      ["--frames", "frames"],
      ["--capture-range", "captureRange"],
      ["--resolution", "resolution"],
      ["--out", "out"],
      ["--golden-dir", "goldenDirectory"],
      ["--minimum-psnr", "minimumPsnr"],
    ]);
    const name = names.get(argument);
    if (!name || !arguments_[index + 1]) {
      throw new Error(`unknown or incomplete argument: ${argument}`);
    }
    options[name] = arguments_[index + 1];
    index += 1;
  }
  if (!options.project) {
    throw new Error("--project is required");
  }
  for (const name of ["warmup", "frames", "minimumPsnr"]) {
    options[name] = Number(options[name]);
  }
  const match = /^(\d+):(\d+)$/.exec(options.captureRange);
  if (!match || Number(match[1]) > Number(match[2])) {
    throw new Error("--capture-range must be an inclusive START:END range");
  }
  options.captureStart = Number(match[1]);
  options.captureEnd = Number(match[2]);
  if (options.stableFrontier && options.requireTransition) {
    throw new Error("--stable-frontier and --require-transition are mutually exclusive");
  }
  return options;
}

function run(command, arguments_) {
  const result = spawnSync(command, arguments_, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    let diagnostic = result.stdout.trim();
    try {
      const envelope = JSON.parse(result.stdout);
      diagnostic = (envelope.diagnostics ?? [])
        .map((entry) => `${entry.code}: ${entry.message}`)
        .join("; ");
    } catch {
      // Preserve the raw structured-output failure when parsing itself failed.
    }
    throw new Error(
      `${command} ${arguments_.join(" ")} exited with ${result.status}: ` +
        (diagnostic || result.stderr.trim()),
    );
  }
  return result.stdout;
}

function psnr(expectedPath, actualPath) {
  const expected = decodePngRgba8(expectedPath);
  const actual = decodePngRgba8(actualPath);
  if (expected.width !== actual.width || expected.height !== actual.height) {
    throw new Error(`golden dimensions differ for ${path.basename(actualPath)}`);
  }
  let squaredError = 0;
  let channels = 0;
  for (let index = 0; index < expected.pixels.length; index += 4) {
    for (let channel = 0; channel < 3; channel += 1) {
      const difference = expected.pixels[index + channel] - actual.pixels[index + channel];
      squaredError += difference * difference;
      channels += 1;
    }
  }
  const meanSquaredError = squaredError / channels;
  return meanSquaredError === 0
    ? Number.POSITIVE_INFINITY
    : 10 * Math.log10((255 * 255) / meanSquaredError);
}

function assertVisibleImage(image, filename) {
  let minimum = 255;
  let maximum = 0;
  for (let index = 0; index < image.pixels.length; index += 4) {
    for (let channel = 0; channel < 3; channel += 1) {
      minimum = Math.min(minimum, image.pixels[index + channel]);
      maximum = Math.max(maximum, image.pixels[index + channel]);
    }
  }
  if (maximum - minimum < 8) {
    throw new Error(`${filename} has no meaningful color range`);
  }
}

export function validateProfile(options, profile, framesDirectory) {
  if (profile.schema_version !== 2 || profile.frames?.length !== options.frames) {
    throw new Error("profile does not match the requested bounded run");
  }
  const capturedRows = profile.frames.filter(
    (frame) => frame.index >= options.captureStart && frame.index <= options.captureEnd,
  );
  if (capturedRows.length !== options.captureEnd - options.captureStart + 1) {
    throw new Error("profile is missing captured frame rows");
  }
  const captures = [];
  for (const frame of capturedRows) {
    const filename = `frame-${String(frame.index).padStart(6, "0")}.png`;
    const imagePath = path.join(framesDirectory, filename);
    const image = decodePngRgba8(imagePath);
    if (image.width < 1 || image.height < 1) {
      throw new Error(`${filename} is empty`);
    }
    assertVisibleImage(image, filename);
    let score;
    if (options.goldenDirectory) {
      score = psnr(path.resolve(root, options.goldenDirectory, filename), imagePath);
      if (score < options.minimumPsnr) {
        throw new Error(
          `${filename} PSNR ${score.toFixed(3)} dB is below ${options.minimumPsnr.toFixed(3)} dB`,
        );
      }
    }
    captures.push({ frame: frame.index, image: filename, ...(score ? { psnr_db: score } : {}) });
  }
  if (options.stableFrontier) {
    const errors = new Set(
      capturedRows.map((frame) => frame.render?.virtual_geometry_error_pixels),
    );
    for (const frame of capturedRows) {
      if (
        frame.render?.virtual_geometry !== true ||
        frame.render?.virtual_geometry_page_request_overflow !== 0 ||
        frame.render?.virtual_geometry_page_read_failures !== 0 ||
        frame.counter_deltas?.virtual_geometry_group_uploads !== 0 ||
        frame.counter_deltas?.virtual_geometry_group_activations !== 0 ||
        frame.counter_deltas?.virtual_geometry_group_evictions !== 0 ||
        frame.render?.virtual_geometry_transitioning_groups !== 0
      ) {
        throw new Error(`virtual-geometry frontier mutated during captured frame ${frame.index}`);
      }
    }
    if (errors.size !== 1) {
      throw new Error("virtual-geometry projected-error policy changed during capture");
    }
  }
  if (options.requireTransition) {
    const transitionCounts = capturedRows.map(
      (frame) => frame.render?.virtual_geometry_transitioning_groups ?? 0,
    );
    if (!transitionCounts.some((count) => count > 0)) {
      throw new Error("captured range does not contain a virtual-geometry transition");
    }
    if (
      !capturedRows.some(
        (frame) => (frame.render?.visible_virtual_blend_clusters ?? 0) > 0,
      )
    ) {
      throw new Error("captured transition does not exercise visible blended clusters");
    }
    if (transitionCounts.at(-1) !== 0) {
      throw new Error("captured virtual-geometry transition does not reach a settled endpoint");
    }
    for (const frame of capturedRows) {
      if (
        frame.render?.virtual_geometry !== true ||
        frame.render?.virtual_geometry_page_request_overflow !== 0 ||
        frame.render?.virtual_geometry_page_read_failures !== 0
      ) {
        throw new Error(`virtual-geometry transition became unhealthy at frame ${frame.index}`);
      }
    }
  }
  return captures;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  options.out = path.resolve(root, options.out);
  fs.rmSync(options.out, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(options.out), { recursive: true });
  const raw = run(path.resolve(root, options.binary), [
    "profile",
    options.project,
    "--warmup",
    String(options.warmup),
    "--frames",
    String(options.frames),
    "--resolution",
    options.resolution,
    "--capture-range",
    options.captureRange,
    "--out",
    options.out,
    "--json",
  ]);
  const envelope = JSON.parse(raw);
  if (envelope.schema_version !== 1 || envelope.command !== "profile" || envelope.ok !== true) {
    throw new Error("Scrapbot profile did not succeed");
  }
  const profile = JSON.parse(fs.readFileSync(path.join(options.out, "profile.json"), "utf8"));
  const captures = validateProfile(options, profile, path.join(options.out, "frames"));
  const manifest = {
    schema_version: 1,
    status: "passed",
    project: options.project,
    resolution: options.resolution,
    warmup_frames: options.warmup,
    recorded_frames: options.frames,
    capture_range: options.captureRange,
    stable_frontier: options.stableFrontier,
    required_transition: options.requireTransition,
    golden_directory: options.goldenDirectory ?? null,
    captures,
  };
  fs.writeFileSync(path.join(options.out, "sequence-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`render sequence passed: ${path.join(options.out, "sequence-manifest.json")}`);
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  try {
    main();
  } catch (error) {
    console.error(`[render-sequence] ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}
