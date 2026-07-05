# FDR-006: Asset Import and Cache

**Status:** Planned
**Last reviewed:** 2026-07-01

## Overview

Asset import and cache handling lets projects keep source assets in ordinary files while Scrapbot generates runtime-ready artifacts as needed. It exists so binary source assets can coexist with a text-first project model without making generated data authoritative.

## Behavior

- Projects can reference source assets such as images, audio, models, fonts, and shaders.
- The engine can import supported source assets into runtime-ready cache artifacts.
- Generated cache artifacts are separate from source project files and can be regenerated.
- Asset import can run from headless commands.
- Asset references in scenes, materials, UI, and scripts can be validated.
- Import failures produce diagnostics that identify the source asset and reason for failure.

## Design Decisions

### 1. Treat source assets as authoritative

**Decision:** Original asset files and text metadata are the source of truth; imported artifacts are generated outputs.
**Why:** This preserves reviewable project state while allowing efficient runtime formats. It follows ADR-001.
**Tradeoff:** The engine needs cache invalidation and import reproducibility rules.

### 2. Make import available headlessly

**Decision:** Asset import runs through the same binary in non-interactive mode.
**Why:** Builds, tests, CI, and agents need deterministic asset preparation. It follows ADR-003.
**Tradeoff:** Importers cannot depend on editor-only state or UI prompts.

## Related

- **ADRs:** ADR-001, ADR-003, ADR-005
- **FDRs:** FDR-001, FDR-002, FDR-003

## Open Questions

- What asset types are included in the first import slice?
- How are stable asset identifiers assigned and stored?
- Which cache directory is canonical?
