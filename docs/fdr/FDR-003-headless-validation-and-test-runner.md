# FDR-003: Headless Validation and Test Runner

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

The headless validation and test runner lets users, CI systems, and agents check project correctness and script behavior without opening a window. It validates project metadata, script ECS declarations, the default scene, runs deterministic update frames, and exposes machine-readable validation details for editor and agent workflows.

## Behavior

- `machina check [path]` validates project metadata, project scripts, script-declared ECS types, schedule construction, and the default scene.
- `machina check [path] --format=json` reports project metadata and the validated schedule batches, including phases, system ids, runner kinds, read/write sets, and before/after ordering declarations.
- `machina step [path] [--frames N] [--dt seconds]` loads the default scene, runs startup once, runs the update schedule headlessly for the requested frame count, and reports final scene and simulation counts.
- `machina step [path] --format=json` reports project metadata, final scene summary, simulation summary, schedule batches, and structured runtime diagnostics when a system fails.
- Automated scenario fixtures live under `tests/projects/` and use complete text-authored Machina projects rather than sharing example projects.
- `machina test [tests-path|project-path]` discovers text-authored test projects, reads each project's `test.machina.toml`, steps the project headlessly, and checks declared ECS field expectations.
- `machina test --format=json` reports each project case, simulation summary, per-field expected/actual assertion data, diagnostics, and a suite summary.
- `machina render-test [path] [output.bmp]` renders the default scene offscreen, including UI overlays, reads the output image back, and verifies BMP shape, foreground coverage, visible components, and expected warm/cool color groups for automation.
- Future headless test commands can exercise scene and script live reload deterministically.
- Users can run project validation without initializing graphical presentation.
- Validation failures produce command-line diagnostics and non-zero process exit codes.
- Commands return appropriate process exit codes for automation.
- Headless commands avoid creating or mutating source files unless the command explicitly performs a repair, import, or generation action.

## Design Decisions

### 1. Make validation a core runtime capability

**Decision:** Project validation is part of the engine binary, not an external lint script.
**Why:** Interactive and headless modes need identical rules. It follows ADR-003.
**Tradeoff:** The engine must keep validators available without depending on editor-only systems.

### 2. Keep headless mode independent from presentation

**Decision:** Validation and tests run without requiring a window or GPU surface.
**Why:** CI and agent workflows need reliable execution in non-graphical environments. It follows ADR-003 and ADR-005.
**Tradeoff:** Some rendering behavior requires separate snapshot or backend-specific tests.

### 3. Prefer offscreen render assertions for visual checks

**Decision:** The first visual verification command uses offscreen BMP output and pixel analysis instead of screenshotting a headful window.
**Why:** Offscreen rendering is easier to run in agent and CI workflows, and parsing the output artifact can catch regressions like missing foreground content or collapsed multi-object renders.
**Tradeoff:** Pixel analysis is still coarse and does not replace future golden-image or semantic render tests.

### 4. Add deterministic stepping and manifest assertions before full test scripting

**Decision:** Script behavior tests use a small `test.machina.toml` manifest with frame count, timestep, and ECS field equality assertions instead of introducing a full test scripting DSL.
**Why:** Agents and CI need a small, reliable way to prove script systems mutate ECS state and surface runtime diagnostics. Keeping the assertions text-first makes them easy to inspect and patch. This follows ADR-003 and ADR-006.
**Tradeoff:** The manifest currently supports direct component field equality, not arbitrary predicates, setup/teardown hooks, or multi-scene flows.

### 5. Keep gameplay test fixtures separate from examples

**Decision:** Game-shaped automated fixtures live in `tests/projects/`, not under `examples/`.
**Why:** Examples are user-facing smoke projects, while tests need purpose-built scenes and scripts that can change to cover edge cases without implying supported sample content.
**Tradeoff:** Some project files are duplicated between examples and tests until package/shared-fixture tooling exists.

## Related

- **ADRs:** ADR-001, ADR-003, ADR-005, ADR-006, ADR-009
- **FDRs:** FDR-001, FDR-002, FDR-004, FDR-005, FDR-006, FDR-010

## Open Questions

- Should snapshot rendering be part of validation, testing, or a separate command?
