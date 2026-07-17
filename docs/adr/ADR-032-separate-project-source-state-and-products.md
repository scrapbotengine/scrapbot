# ADR-032: Separate project source, engine state, and products

**Date:** 2026-07-17

## Context

Scrapbot projects contain three different kinds of files: authored game inputs, regenerable engine state, and distributable build products. The initial layout mixed generated Luau declarations with authored top-level directories and used `build/` for both internal extension/font caches and runnable packages. This made project roots noisy, made version-control policy unclear, and gave `build/` two incompatible meanings.

## Decision

Keep authored inputs in conventional top-level directories: `assets/`, `native/`, `resources/`, `scenes/`, and `scripts/`, with `project.toml` as the root manifest. Store all regenerable engine-owned state under `.scrapbot/`: generated Luau declarations in `.scrapbot/types/`, native extension artifacts in `.scrapbot/cache/extensions/`, and generated font atlases in `.scrapbot/cache/fonts/`. Reserve `build/` exclusively for runnable package output.

`scrapbot init` creates this canonical layout, writes `.gitignore` entries for `.scrapbot/` and `build/`, and generates editor configuration that points at the ignored Luau declaration file. Initialization may use an existing destination directory, but it preflights every file it owns and refuses to overwrite any of them. An omitted display name is derived from the destination directory.

Packages omit the development `.scrapbot/` tree, then copy only active native extension and font artifacts into the corresponding runtime paths inside the package.

## Consequences

The visible project root is dominated by authored source, ignored state can always be regenerated, and `build/` has one clear purpose. Generated declarations no longer produce routine repository diffs. Tooling and documentation must use the new paths, and existing projects must delete or ignore their old `types/`, `build/extensions/`, and `build/fonts/` outputs before regenerating them.

The `.vscode/settings.json` file remains project metadata rather than engine state because it connects an external editor to the generated declaration path. Existing `.gitignore` files are preserved rather than rewritten; users initializing inside an existing repository must already have appropriate ignore policy or add the two generated directories themselves.
