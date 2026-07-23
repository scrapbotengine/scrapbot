import { createHash } from "node:crypto";
import {
  createReadStream,
  createWriteStream,
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
} from "node:fs";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, resolve, sep } from "node:path";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = join(
  repositoryRoot,
  "tests/fixtures/external/manifest.json",
);
const downloadsRoot = join(
  repositoryRoot,
  "tests/fixtures/external/downloads",
);
const checkOnly = process.argv.slice(2).includes("--check");
const downloadConcurrency = 6;

async function sha256(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

function destinationPath(asset) {
  const destination = resolve(downloadsRoot, asset.path);
  const pathWithinDownloads = relative(downloadsRoot, destination);
  if (
    pathWithinDownloads === "" ||
    pathWithinDownloads === ".." ||
    pathWithinDownloads.startsWith(`..${sep}`) ||
    pathWithinDownloads.startsWith(sep)
  ) {
    throw new Error(`${asset.id}: destination escapes the downloads directory`);
  }
  return destination;
}

function placementPath(asset, placement) {
  const destination = resolve(repositoryRoot, placement);
  const pathWithinRepository = relative(repositoryRoot, destination);
  if (
    pathWithinRepository === "" ||
    pathWithinRepository === ".." ||
    pathWithinRepository.startsWith(`..${sep}`) ||
    pathWithinRepository.startsWith(sep)
  ) {
    throw new Error(`${asset.id}: placement escapes the repository`);
  }
  return destination;
}

async function assetIsCurrent(asset, destination) {
  if (!existsSync(destination)) {
    return false;
  }
  if (statSync(destination).size !== asset.bytes) {
    return false;
  }
  return (await sha256(destination)) === asset.sha256;
}

async function downloadAsset(asset, destination) {
  mkdirSync(dirname(destination), { recursive: true });
  const temporary = `${destination}.download`;
  rmSync(temporary, { force: true });

  try {
    const response = await fetch(asset.url, { redirect: "follow" });
    if (!response.ok || response.body === null) {
      throw new Error(`HTTP ${response.status} ${response.statusText}`);
    }
    await pipeline(response.body, createWriteStream(temporary));
    if (!(await assetIsCurrent(asset, temporary))) {
      throw new Error("downloaded bytes do not match the pinned size and SHA-256");
    }
    renameSync(temporary, destination);
  } finally {
    rmSync(temporary, { force: true });
  }
}

async function ensurePlacement(asset, source, placement) {
  const destination = placementPath(asset, placement);
  if (destination === source) {
    throw new Error(`${asset.id}: placement duplicates its download path`);
  }
  if (await assetIsCurrent(asset, destination)) {
    if (!asset.quiet) {
      console.log(`[external-assets] ready ${asset.id} at ${placement}`);
    }
    return true;
  }
  if (checkOnly) {
    console.error(`[external-assets] missing or invalid ${asset.id} at ${placement}`);
    return false;
  }
  mkdirSync(dirname(destination), { recursive: true });
  const temporary = `${destination}.install`;
  rmSync(temporary, { force: true });
  copyFileSync(source, temporary);
  if (!(await assetIsCurrent(asset, temporary))) {
    rmSync(temporary, { force: true });
    throw new Error(`${asset.id}: placed bytes failed verification`);
  }
  rmSync(destination, { force: true });
  renameSync(temporary, destination);
  if (!asset.quiet) {
    console.log(`[external-assets] installed ${asset.id} at ${placement}`);
  }
  return true;
}

function expandedAssets(manifest) {
  const result = [];
  for (const asset of manifest.assets) {
    if (asset.files === undefined) {
      result.push(asset);
      continue;
    }
    if (
      !Array.isArray(asset.files) ||
      asset.files.length === 0 ||
      typeof asset.base_url !== "string" ||
      asset.base_url === ""
    ) {
      throw new Error(`${asset.id}: file bundles require base_url and files`);
    }
    const placementRoots = asset.placements ?? [];
    for (const file of asset.files) {
      if (
        typeof file.path !== "string" ||
        file.path === "" ||
        file.path.includes("\\") ||
        file.path.split("/").some((part) => part === "" || part === "." || part === "..")
      ) {
        throw new Error(`${asset.id}: bundle file path must be safe and relative`);
      }
      result.push({
        ...file,
        id: `${asset.id}:${file.path}`,
        path: `${asset.path}/${file.path}`,
        url: new URL(file.path, `${asset.base_url.replace(/\/+$/, "")}/`).toString(),
        source: asset.source,
        license: asset.license,
        placements: placementRoots.map((placement) => `${placement}/${file.path}`),
        quiet: true,
      });
    }
  }
  return result;
}

async function runConcurrent(items, concurrency, operation) {
  let next = 0;
  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    async () => {
      for (;;) {
        const index = next;
        next += 1;
        if (index >= items.length) {
          return;
        }
        await operation(items[index]);
      }
    },
  );
  await Promise.all(workers);
}

async function main() {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.schema_version !== 1 || !Array.isArray(manifest.assets)) {
    throw new Error("unsupported external asset manifest");
  }

  let missing = false;
  const assets = expandedAssets(manifest);
  await runConcurrent(assets, downloadConcurrency, async (asset) => {
    const placements = asset.placements ?? [];
    if (
      !Array.isArray(placements) ||
      placements.some((placement) => typeof placement !== "string" || placement === "")
    ) {
      throw new Error(`${asset.id}: placements must be non-empty repository-relative paths`);
    }
    const destination = destinationPath(asset);
    const current = await assetIsCurrent(asset, destination);
    if (current) {
      if (!asset.quiet) {
        console.log(`[external-assets] ready ${asset.id}`);
      }
    } else if (checkOnly) {
      console.error(`[external-assets] missing or invalid ${asset.id}`);
      missing = true;
      return;
    } else {
      if (!asset.quiet) {
        console.log(`[external-assets] downloading ${asset.id}`);
      }
      await downloadAsset(asset, destination);
      if (!asset.quiet) {
        console.log(`[external-assets] verified ${asset.id}`);
      }
    }

    for (const placement of placements) {
      if (!(await ensurePlacement(asset, destination, placement))) {
        missing = true;
      }
    }
  });
  for (const asset of manifest.assets) {
    if (Array.isArray(asset.files)) {
      console.log(
        `[external-assets] ready ${asset.id} (${asset.files.length} files)`,
      );
    }
  }

  if (missing) {
    throw new Error("run `mise setup-assets` to install external fixtures");
  }
}

main().catch((error) => {
  console.error(`[external-assets] ${error.message}`);
  process.exitCode = 1;
});
