#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const examplesRoot = path.join(root, "examples");
const outputPath = path.join(root, "types", "scrapbot.d.luau");
const checkOnly = process.argv.includes("--check");
const projectDefinitionPath = ".scrapbot/types/scrapbot.d.luau";

const allProjectRoots = fs
  .readdirSync(examplesRoot, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => path.join(examplesRoot, entry.name))
  .filter((projectRoot) => fs.existsSync(path.join(projectRoot, "project.toml")))
  .sort();

// gltf-showcase intentionally depends on ignored external fixtures installed by
// `mise setup-assets`, so the ordinary repository workspace aggregate is built
// from the self-contained examples exercised by the default suite.
const workspaceProjectNames = new Set([
  "assets",
  "asteroids",
  "ecs-showcase",
  "ecs-stress",
  "minimal",
  "ui-showcase",
]);
const projectRoots = allProjectRoots.filter((projectRoot) =>
  workspaceProjectNames.has(path.basename(projectRoot)),
);

const declarationFiles = projectRoots.map((projectRoot) => ({
  projectRoot,
  path: path.join(projectRoot, projectDefinitionPath),
}));

function readSettings(settingsPath) {
  if (!fs.existsSync(settingsPath)) {
    throw new Error(`missing ${path.relative(root, settingsPath)}`);
  }
  return JSON.parse(fs.readFileSync(settingsPath, "utf8"));
}

const rootSettingsPath = path.join(root, ".vscode", "settings.json");
// Root editor settings are intentionally ignored because they commonly contain
// developer-local tool paths. Validate the Scrapbot declaration path when a
// checkout has opted into those settings, but keep clean clones supported.
if (fs.existsSync(rootSettingsPath)) {
  const rootSettings = readSettings(rootSettingsPath);
  if (rootSettings["luau-lsp.types.definitionFiles"]?.scrapbot !== "types/scrapbot.d.luau") {
    throw new Error(
      `${path.relative(root, rootSettingsPath)} does not load workspace Luau declarations`,
    );
  }
}

for (const projectRoot of allProjectRoots) {
  const settingsPath = path.join(projectRoot, ".vscode", "settings.json");
  const settings = readSettings(settingsPath);
  if (settings["luau-lsp.types.definitionFiles"]?.scrapbot !== projectDefinitionPath) {
    throw new Error(
      `${path.relative(root, settingsPath)} does not load project-local Luau declarations`,
    );
  }
}

for (const declaration of declarationFiles) {
  if (!fs.existsSync(declaration.path)) {
    const relativeProject = path.relative(root, declaration.projectRoot);
    throw new Error(
      `missing generated declarations for ${relativeProject}; run bin/scrapbot check ${relativeProject}`,
    );
  }
}

function parseDeclarations(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  const declareOffset = text.lastIndexOf("declare scrapbot: Scrapbot");
  if (declareOffset < 0) {
    throw new Error(`${path.relative(root, filePath)} does not declare the scrapbot global`);
  }

  const body = text.slice(0, declareOffset);
  const matches = [...body.matchAll(/^export type ([A-Za-z_][A-Za-z0-9_]*)\s*=/gm)];
  if (matches.length === 0) {
    throw new Error(`${path.relative(root, filePath)} contains no exported types`);
  }

  const prefix = body.slice(0, matches[0].index).trimEnd();
  const declarations = matches.map((match, index) => {
    const end = index + 1 < matches.length ? matches[index + 1].index : body.length;
    return {
      name: match[1],
      text: body.slice(match.index, end).trim(),
    };
  });
  return { prefix, declarations };
}

const merged = new Map();
let prefix = "";
for (const declarationFile of declarationFiles) {
  const parsed = parseDeclarations(declarationFile.path);
  if (prefix === "") {
    prefix = parsed.prefix;
  } else if (parsed.prefix !== prefix) {
    throw new Error(
      `${path.relative(root, declarationFile.path)} has a different generated preamble`,
    );
  }

  for (const declaration of parsed.declarations) {
    const existing = merged.get(declaration.name);
    if (existing === undefined) {
      merged.set(declaration.name, {
        text: declaration.text,
        source: declarationFile.path,
      });
      continue;
    }
    if (existing.text !== declaration.text) {
      throw new Error(
        `conflicting generated type ${declaration.name} in ` +
          `${path.relative(root, existing.source)} and ${path.relative(root, declarationFile.path)}`,
      );
    }
  }
}

const output = `${prefix}\n\n${[...merged.values()]
  .map((declaration) => declaration.text)
  .join("\n\n")}\n\ndeclare scrapbot: Scrapbot\n`;

if (checkOnly) {
  const current = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8") : "";
  if (current !== output) {
    console.error("workspace Luau declarations are stale; run mise luau-workspace-types");
    process.exit(1);
  }
  process.exit(0);
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, output);
console.log(
  `wrote ${path.relative(root, outputPath)} from ${declarationFiles.length} Scrapbot projects`,
);
