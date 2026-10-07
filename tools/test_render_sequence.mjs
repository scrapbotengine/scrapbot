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
    cpuReference: false,
    editor: false,
    uiScript: undefined,
    goldenDirectory: undefined,
    minimumPsnr: 32,
  };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--cpu-reference") {
      options.cpuReference = true;
      continue;
    }
    if (argument === "--editor") {
      options.editor = true;
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
      ["--ui-script", "uiScript"],
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
  return captures;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  options.out = path.resolve(root, options.out);
  fs.rmSync(options.out, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(options.out), { recursive: true });
  const profileArguments = [
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
    ...(options.editor ? ["--editor"] : []),
    ...(options.uiScript ? ["--ui-script", options.uiScript] : []),
    "--json",
  ];
  const raw = run(path.resolve(root, options.binary), profileArguments);
  const envelope = JSON.parse(raw);
  if (envelope.schema_version !== 1 || envelope.command !== "profile" || envelope.ok !== true) {
    throw new Error("Scrapbot profile did not succeed");
  }
  const profile = JSON.parse(fs.readFileSync(path.join(options.out, "profile.json"), "utf8"));
  const captures = validateProfile(options, profile, path.join(options.out, "frames"));
  let cpuReferenceDirectory = null;
  if (options.cpuReference) {
    cpuReferenceDirectory = `${options.out}-cpu-reference`;
    fs.rmSync(cpuReferenceDirectory, { recursive: true, force: true });
    const referenceRaw = run(path.resolve(root, options.binary), [
      "profile",
      options.project,
      "--cpu-culling",
      "--warmup",
      String(options.warmup),
      "--frames",
      String(options.frames),
      "--resolution",
      options.resolution,
      "--capture-range",
      options.captureRange,
      "--out",
      cpuReferenceDirectory,
      ...(options.editor ? ["--editor"] : []),
      ...(options.uiScript ? ["--ui-script", options.uiScript] : []),
      "--json",
    ]);
    const referenceEnvelope = JSON.parse(referenceRaw);
    if (
      referenceEnvelope.schema_version !== 1 ||
      referenceEnvelope.command !== "profile" ||
      referenceEnvelope.ok !== true
    ) {
      throw new Error("Scrapbot CPU-reference profile did not succeed");
    }
    const referenceProfile = JSON.parse(
      fs.readFileSync(path.join(cpuReferenceDirectory, "profile.json"), "utf8"),
    );
    validateProfile(
      {
        ...options,
        goldenDirectory: undefined,
        stableFrontier: false,
        requireResidencyPressure: false,
      },
      referenceProfile,
      path.join(cpuReferenceDirectory, "frames"),
    );
    for (const capture of captures) {
      const gpuPath = path.join(options.out, "frames", capture.image);
      const cpuPath = path.join(cpuReferenceDirectory, "frames", capture.image);
      const score = psnr(cpuPath, gpuPath);
      if (score < options.minimumPsnr) {
        throw new Error(
          `${capture.image} GPU/CPU PSNR ${score.toFixed(3)} dB is below ` +
            `${options.minimumPsnr.toFixed(3)} dB`,
        );
      }
      capture.cpu_reference_psnr_db = Number.isFinite(score) ? score : null;
      capture.cpu_reference_exact = !Number.isFinite(score);
    }
  }
  const manifest = {
    schema_version: 1,
    status: "passed",
    project: options.project,
    resolution: options.resolution,
    warmup_frames: options.warmup,
    recorded_frames: options.frames,
    capture_range: options.captureRange,
    cpu_reference: options.cpuReference,
    editor: options.editor,
    ui_script: options.uiScript ?? null,
    cpu_reference_directory: cpuReferenceDirectory,
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
