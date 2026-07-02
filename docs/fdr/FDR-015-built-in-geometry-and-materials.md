# FDR-015: Built-In Geometry and Materials

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Built-in geometry and materials let projects render simple 3D forms from text-authored ECS component data before Machina has an asset import pipeline. They give examples, tests, scripts, and future editor tooling a common way to describe visible objects without hardcoding everything as cubes.

## Behavior

- Scene entities can author `machina.geometry.primitive` to select a built-in primitive.
- Built-in primitives include `box`, `plane`, `sphere`, `uv_sphere`, and `ico_sphere`.
- Primitive geometry supports simple resolution fields for sphere-like primitives.
- Scene entities can author `machina.material.surface` to provide a base color.
- Renderable entities use `machina.transform`, geometry, and material component data.
- Existing `machina.render.cube` entities remain valid and render as box geometry with an inline base-color material.
- Generated geometry provides normals for the existing directional lighting model.
- The showcase example renders multiple built-in primitive types through the geometry/material path.

## Design Decisions

### 1. Split shape selection from material color

**Decision:** Geometry and material are separate ECS components instead of one renderer-specific cube component.
**Why:** Shape data and surface data will evolve independently as assets, materials, scripts, and editor tooling grow. This follows ADR-008 and ADR-013.
**Tradeoff:** Simple renderable entities need two component tables instead of one.

### 2. Keep primitives built in until asset import exists

**Decision:** Machina generates common primitives directly in the engine before loading mesh assets from disk.
**Why:** Built-ins are enough for tests, examples, editor experiments, and early gameplay while FDR-006 remains planned.
**Tradeoff:** Generated geometry is intentionally limited and not a replacement for real mesh assets.

### 3. Preserve legacy cube scenes

**Decision:** `machina.render.cube` remains supported as a compatibility shortcut.
**Why:** Existing examples, tests, and early project files should continue to run while new scenes move to geometry/material components.
**Tradeoff:** The codebase temporarily carries legacy cube naming and renderable-count APIs until a migration removes or retires the shortcut.

### 4. Use the existing lighting model

**Decision:** The first material component only carries base color; it feeds the existing directional diffuse shader.
**Why:** This decouples material data from geometry without pretending to provide a full PBR material system yet.
**Tradeoff:** Roughness, metallic, textures, transparency, and material assets remain future work.

## Related

- **ADRs:** ADR-001, ADR-004, ADR-008, ADR-013
- **FDRs:** FDR-002, FDR-006, FDR-007, FDR-008, FDR-009, FDR-014

## Open Questions

- Should primitive parameters become separate per-shape components instead of a shared primitive selector?
- When should generated geometry become cached/shared across entities instead of prepared per renderable?
- What is the first real material model beyond base color?
