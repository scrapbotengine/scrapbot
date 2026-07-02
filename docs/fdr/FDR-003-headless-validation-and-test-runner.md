# FDR-003: Headless Validation and Test Runner

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

The headless validation and test runner lets users, CI systems, and agents check project correctness without opening a window. It validates project metadata, script ECS declarations, the default scene, and exposes machine-readable validation details for editor and agent workflows.

## Behavior

- `machina check [path]` validates project metadata, project scripts, script-declared ECS types, update schedule construction, and the default scene.
- `machina check [path] --format=json` reports project metadata and the validated update schedule batches, including system ids, runner kinds, read/write sets, and before/after ordering declarations.
- `machina render-test [path] [output.bmp]` renders the default scene offscreen, reads the output image back, and verifies BMP shape, foreground coverage, visible components, and expected warm/cool color groups for automation.
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

## Related

- **ADRs:** ADR-001, ADR-003, ADR-005, ADR-009
- **FDRs:** FDR-001, FDR-002, FDR-004, FDR-006, FDR-010

## Open Questions

- Should snapshot rendering be part of validation, testing, or a separate command?
