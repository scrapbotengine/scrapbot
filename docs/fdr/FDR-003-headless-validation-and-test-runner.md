# FDR-003: Headless Validation and Test Runner

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

The headless validation and test runner lets users, CI systems, and agents check project correctness without opening a window. The initial implementation validates project metadata and the default scene; broader asset, script, and configuration validation will be added as those systems come online.

## Behavior

- The initial `machina check [path]` command validates project metadata and the default scene.
- `machina render-test [path] [output.bmp]` renders the default scene offscreen, reads the output image back, and verifies BMP shape, foreground coverage, visible components, and expected warm/cool color groups for automation.
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

- **ADRs:** ADR-001, ADR-003, ADR-005
- **FDRs:** FDR-001, FDR-002, FDR-004, FDR-006

## Open Questions

- What diagnostic output formats should be supported beyond human-readable text?
- How should location-aware diagnostics be represented once schemas become richer?
- Should snapshot rendering be part of validation, testing, or a separate command?
