# FDR-005: Engine UI Primitives

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Engine UI primitives provide the controls and layout capabilities needed for runtime overlays, debug tools, and the future editor. They exist so Machina can build tooling with its own scene model, renderer, and input systems instead of depending on a separate editor application stack.

## Behavior

- The engine can render text-authored UI overlays in offscreen renders and interactive windows.
- Scene entities can define a UI canvas marker, screen-space colored rectangles, fixed-pixel text labels, and button markers.
- UI rectangles and text labels use screen-space positions and sizes with a top-left origin.
- Button markers currently provide semantic authoring and button styling; pointer interaction is not active yet.
- UI can be used for runtime diagnostics before a full editor exists.
- UI definitions that are part of projects or tools follow the text-first project model.
- The UI overlay renders after 3D scene content.

## Design Decisions

### 1. Use engine-hosted UI for tooling

**Decision:** Editor and runtime tools are built with Machina UI primitives.
**Why:** This keeps tooling portable and integrated with the engine. It follows ADR-007.
**Tradeoff:** Early editor work depends on maturing an engine UI system first.

### 2. Support debug overlays before full editor panels

**Decision:** The first UI milestone should support runtime diagnostics and inspection overlays.
**Why:** Overlays exercise rendering, input, layout, and engine state presentation with a smaller surface than a full editor.
**Tradeoff:** Overlay-first design must still leave room for complex editor workflows.

### 3. Keep the first slice retained and ECS-authored

**Decision:** The first UI primitives are retained scene data rather than an immediate-mode scripting API.
**Why:** Retained ECS data keeps the first slice text-first, reloadable through scene files, render-testable, and aligned with ADR-008 and ADR-013.
**Tradeoff:** Authoring dynamic UI from scripts still needs a higher-level API in a later slice.

### 4. Use a built-in pixel text path before font assets

**Decision:** Early text labels render with a deterministic fixed-pixel ASCII style.
**Why:** UI without text is not useful, and a built-in text path avoids making asset import, font atlases, shaping, and localization prerequisites for the first UI milestone.
**Tradeoff:** The current text path is suitable for diagnostics and examples, not polished editor typography.

## Related

- **ADRs:** ADR-001, ADR-004, ADR-007, ADR-008, ADR-013
- **FDRs:** FDR-001, FDR-002, FDR-003, FDR-007, FDR-008, FDR-009

## Open Questions

- What script-facing API should generate or mutate UI state for runtime tools?
- When should pointer hover, press, focus, and text input become active behavior?
- What layout primitives are needed before editor panels become practical?
- What text editing capability is needed before the editor becomes practical?
