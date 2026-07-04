# FDR-001: Project Directory Runtime

**Status:** Active
**Last reviewed:** 2026-07-05

## Overview

The project directory runtime lets users and agents run the `machina` binary inside a project folder and operate on that project without additional setup. It exists so interactive play, editor startup, validation, importing, testing, and building all share the same project discovery and loading behavior.

## Behavior

- Users can launch Machina commands from a project directory.
- Users can pass an explicit project path when they do not want to rely on the current working directory.
- The runtime locates project metadata, resolves project-relative paths, and reports clear diagnostics when the directory is not a valid project.
- Users can initialize a new project with `machina init [path]`, defaulting to the current directory.
- `machina init` creates the target directory when needed, writes `project.machina.toml`, and writes the default scene at `scenes/main.scene.toml`.
- Fresh projects contain a small script-free scene with a renderer singleton, cube, camera, and directional light using the current scene-authored components.
- Fresh default scenes include a preconfigured `machina.renderer` HDR, color, and postprocess profile.
- `machina init` does not overwrite an existing project; it fails if `project.machina.toml` already exists in the target directory.
- Interactive and headless commands use the same project loading rules.
- Commands that write files keep generated artifacts separate from authoritative source files.

## Design Decisions

### 1. Treat the current directory as a project entrypoint

**Decision:** `machina` commands default to the current working directory as the active project.
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
