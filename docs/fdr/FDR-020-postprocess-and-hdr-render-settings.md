# FDR-020: Postprocess and HDR Render Settings

**Status:** Active
**Last reviewed:** 2026-07-05

## Overview

Postprocess and HDR render settings let projects configure the final game-view image from text-authored ECS scene data. The first slice keeps the pass graph engine-owned while exposing a small set of built-in, validated settings through a singleton `scrapbot.renderer` component that scripts and the editor can read and write like other component data.

## Behavior

- Scenes can author at most one entity with `[entities.components."scrapbot.renderer"]`. More than one renderer component is invalid.
- `scrapbot.renderer.hdr = true` renders scene color into an internal `rgba16_float` texture before final output when the render target is created from that scene.
- `scrapbot.renderer.tone_mapping` supports `"none"`, `"reinhard"`, and `"aces"`.
- `scrapbot.renderer.exposure` applies exposure compensation before tone mapping.
- `scrapbot.renderer.postprocess_enabled` enables built-in postprocess effects, and `scrapbot.renderer.antialiasing` supports `"none"` and `"fxaa"`.
- `scrapbot.renderer` exposes flat bloom, vignette, and chromatic aberration fields: `bloom_*`, `vignette_*`, and `chromatic_aberration_*`.
- Bloom extracts bright HDR scene color into a multi-level downsampled bloom pyramid, applies separable blur per level, and composites the weighted levels during final postprocess.
- Existing projects without render settings keep the previous direct LDR render path.
- Newly initialized projects include a preconfigured `scrapbot.renderer` HDR, ACES, FXAA, bloom, chromatic aberration, and vignette profile in the default scene.
- Runtime systems can mutate postprocess, exposure, tone mapping, and effect parameters through the `scrapbot.renderer` component. The HDR scene texture format is chosen when the render target is created, so runtime HDR format toggles require renderer recreation or scene reload in this slice.
- UI and editor chrome render after postprocess, so the effect applies to the rendered scene view rather than retained UI panels.

## Design Decisions

### 1. Keep render settings in ECS scene data

**Decision:** The first configurable render pipeline surface is the scene-authored singleton component `scrapbot.renderer`.
**Why:** Renderer settings are inspectable in the same entity/component model as camera, lighting, materials, script systems, and future editor inspector controls. Systems can animate or adjust render settings without a project-metadata side channel.
**Tradeoff:** The renderer singleton is intentionally monolithic for now. Multiple camera-specific render profiles and named render assets remain future work.

### 2. Use engine-owned built-in effects

**Decision:** The project selects built-in effects and numeric parameters rather than authoring arbitrary shader or `wgpu` pipeline data.
**Why:** This preserves backend boundaries, keeps validation deterministic, and avoids exposing WebGPU details through project or scripting layers.
**Tradeoff:** Custom shaders, custom pass ordering, and user-authored render graphs are not covered yet.

### 3. Add HDR as an internal workflow first

**Decision:** HDR support starts as an internal `rgba16_float` scene target plus exposure and tone mapping into the final target.
**Why:** Bloom and future lighting/material work need headroom above LDR color values, while platform HDR presentation can be handled later behind renderer boundaries.
**Tradeoff:** This does not request HDR swapchain formats or platform display modes.

### 4. Keep UI outside the postprocess pass

**Decision:** The scene is postprocessed before retained UI and editor chrome are drawn.
**Why:** UI text, editor panels, and debug surfaces should stay crisp and predictable while scene rendering develops richer image treatment.
**Tradeoff:** Scene-authored UI is also outside postprocess in this first slice.

### 5. Keep GPU resources renderer-owned

**Decision:** `scrapbot.renderer` is authoring/runtime state, not a direct GPU buffer schema.
**Why:** Flat component fields are easy to edit and script, while the renderer can still pack values into the few uniform buffers needed by the effect passes.
**Tradeoff:** Component field changes that imply target or pipeline recreation, such as toggling HDR format, need explicit renderer lifecycle support later.

## Related

- **ADRs:** ADR-001, ADR-004, ADR-013
- **FDRs:** FDR-006, FDR-007, FDR-008, FDR-014, FDR-015, FDR-016

## Open Questions

- Should render profiles become named assets once projects need multiple cameras or scenes with different looks?
- What is the first supported material/light path that intentionally emits HDR values?
- Should bloom expose per-level tint or lens-dirt style controls once texture assets exist?
- Should scene-authored game UI be able to opt into or out of postprocess independently from editor UI?
