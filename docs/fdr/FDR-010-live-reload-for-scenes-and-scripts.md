# FDR-010: Live Reload for Scenes, Scripts, and Native Modules

**Status:** Active
**Last reviewed:** 2026-07-03

## Overview

Live reload lets users, editor tools, and agents change scene, script, and project-local native source files while the engine is running. It shortens the edit-run loop and makes text-first project state practical for interactive development.

## Behavior

- Interactive runs detect changed scene, script, and project-local native source files.
- The current implementation polls project metadata, the active scene, project-listed scripts, and `native = "native/game.zig"` during `scrapbot run`, including changes to the project's `default_scene`.
- Reloaded files are parsed and validated before they replace active runtime state.
- Compatible scene changes replace the active scene world after validation.
- Script reloads validate Luau source, execute script ECS registration, rebuild the component registry, and rebuild schedule batches.
- Native reloads rebuild the project-local Zig module, load it, call its registration entrypoint, rebuild the ECS program, validate the current scene against the new registry, and swap only after all stages succeed.
- Script-only reloads do not replay startup systems against an already-running world.
- Native-only reloads do not replay startup systems against an already-running world.
- Project reloads and scene reloads create a fresh scene generation, so startup systems run again before the next update.
- Failed script reloads report structured diagnostics with failure stage, script path, and message.
- Failed native builds, loads, and registrations report structured diagnostics with native stage, native path, and message.
- Failed reloads leave the last known good state active.
- Headless commands can exercise reload behavior deterministically for tests and agent workflows.
- Reload diagnostics are exposed in a form suitable for command-line output, editor panels, and future structured machine-readable output.

## Design Decisions

### 1. Treat reload as runtime behavior

**Decision:** Live reload belongs in the engine runtime, not only in editor UI code.
**Why:** Headful runs, the future editor, scripts, and headless tests need the same reload semantics. It follows ADR-003 and ADR-009.
**Tradeoff:** Core engine services need file tracking, staged validation, and state patching support.

### 2. Validate before applying changes

**Decision:** The runtime stages changed scene and script data, then applies it only if validation succeeds.
**Why:** Users and agents need failed edits to produce diagnostics without destroying the running state. It follows ADR-001 and ADR-009.
**Tradeoff:** Reload needs temporary parsed state and careful resource lifetime handling.

### 3. Use stable entity identity as the scene patch anchor

**Decision:** Scene reload patches entities and components by stable ids rather than by array position or renderer allocation order.
**Why:** Stable ids allow meaningful diffs, editor selections, script references, and live reload patches. It follows ADR-008 and ADR-009.
**Tradeoff:** The scene schema needs explicit identity rules and duplicate-id diagnostics.

### 4. Keep reload diagnostics agent-friendly

**Decision:** Reload errors should be precise enough for a human, editor UI, or coding agent to locate and repair the source file.
**Why:** Reload is part of the agentic workflow, not just a visual convenience. It follows ADR-001 and ADR-009.
**Tradeoff:** Diagnostics need structured source locations and eventually machine-readable output.

## Related

- **ADRs:** ADR-001, ADR-003, ADR-006, ADR-008, ADR-009, ADR-011, ADR-019
- **FDRs:** FDR-002, FDR-003, FDR-004, FDR-009, FDR-012, FDR-013

## Open Questions

- Which file watching backend should Scrapbot use on each platform?
- How should script state be preserved or reset across reloads?
- What schema migration support is required for live scene reload?
