# FDR-003: Headless Validation and Test Runner

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

The headless validation and test runner lets users, CI systems, and agents check project correctness without opening a window. It exists to make project health observable and enforceable through deterministic commands.

## Behavior

- Users can run a command that validates project metadata, scenes, referenced files, asset metadata, script references, and supported configuration files.
- The initial `machina check [path]` command validates project metadata and the default scene.
- Users can run project tests without initializing graphical presentation.
- Validation and test failures produce structured, location-aware diagnostics.
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

## Related

- **ADRs:** ADR-001, ADR-003, ADR-005
- **FDRs:** FDR-001, FDR-002, FDR-004, FDR-006

## Open Questions

- What diagnostic output formats should be supported beyond human-readable text?
- Should snapshot rendering be part of validation, testing, or a separate command?
