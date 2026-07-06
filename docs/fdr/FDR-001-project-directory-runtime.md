# FDR-001: Project Directory Runtime

**Status:** Active
**Last reviewed:** 2026-07-06

## Overview

The project directory runtime lets users and agents run the `scrapbot` binary inside a project folder and operate on that project without additional setup. It exists so interactive play, editor startup, validation, importing, testing, and building all share the same project discovery and loading behavior.

## Behavior

- Users can launch Scrapbot commands from a project directory.
- Users can pass an explicit project path when they do not want to rely on the current working directory.
- The runtime locates project metadata, resolves project-relative paths, and reports clear diagnostics when the directory is not a valid project.
- Users can initialize a new project with `scrapbot init [path]`, defaulting to the current directory.
- `project.toml` is the canonical project manifest. Existing `project.scrapbot.toml` manifests remain loadable as a compatibility alias, but `project.toml` wins when both files are present.
- `scrapbot init` creates the target directory when needed, writes `project.toml`, writes the startup scene at `scenes/main.scene.toml`, writes a starter Luau script at `scripts/main.luau`, and creates `assets/.gitkeep`.
- Fresh projects contain a small scene with a renderer singleton, spinning cube, camera, and directional light using the current scene-authored components.
- Fresh project manifests list `scripts/main.luau`, and the starter script declares a project-local `spin` component plus an update system that rotates matching entities.
- Fresh default scenes include a preconfigured `scrapbot.renderer` HDR, color, and postprocess profile.
- Fresh project manifests keep the optional native module line commented out and do not create native source files.
- `scrapbot init` does not overwrite an existing project; it fails if `project.toml` or the legacy `project.scrapbot.toml` already exists in the target directory.
- Interactive and headless commands use the same project loading rules.
- Commands that write files keep generated artifacts separate from authoritative source files.

## Design Decisions

### 1. Treat the current directory as a project entrypoint

**Decision:** `scrapbot` commands default to the current working directory as the active project.
**Why:** This supports ordinary shell workflows, CI jobs, editor terminals, and coding agents. It follows ADR-003.
**Tradeoff:** Commands must be careful about diagnostics when run from the wrong directory.

### 2. Keep generated files out of the source model

**Decision:** Generated caches and build artifacts are written outside the authoritative project files.
**Why:** The project model is text-first and reviewable. It follows ADR-001.
**Tradeoff:** The runtime needs explicit cache and artifact path rules.

## Related

- **ADRs:** ADR-001, ADR-003
- **FDRs:** FDR-002, FDR-003, FDR-006, FDR-020

## Open Questions

- Generated cache and artifact path rules still need to be formalized beyond the Zig build cache.
