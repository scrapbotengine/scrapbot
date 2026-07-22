import { createHash } from "node:crypto";
import {
  createReadStream,
  createWriteStream,
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

async function main() {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.schema_version !== 1 || !Array.isArray(manifest.assets)) {
    throw new Error("unsupported external asset manifest");
  }

  let missing = false;
  for (const asset of manifest.assets) {
    const destination = destinationPath(asset);
    if (await assetIsCurrent(asset, destination)) {
      console.log(`[external-assets] ready ${asset.id}`);
      continue;
    }
    if (checkOnly) {
      console.error(`[external-assets] missing or invalid ${asset.id}`);
      missing = true;
      continue;
    }

    console.log(`[external-assets] downloading ${asset.id}`);
    await downloadAsset(asset, destination);
    console.log(`[external-assets] verified ${asset.id}`);
  }

  if (missing) {
    throw new Error("run `mise setup-assets` to install external fixtures");
  }
}

main().catch((error) => {
  console.error(`[external-assets] ${error.message}`);
  process.exitCode = 1;
});
