# FDR-014: Scene-Driven Camera and Lighting

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Scene-driven camera and lighting let projects describe the view and first directional light as ECS component data instead of relying on renderer-only constants. This keeps visible rendering behavior inspectable, testable, reloadable, and editable by humans, agents, scripts, and future editor tooling.

## Behavior

- Scenes may author a camera with `scrapbot.camera` on an entity that also has `scrapbot.transform`.
- Camera transforms define the rendered view position and rotation.
- Camera projection data includes vertical field of view, near plane, and far plane.
- Scenes may author a directional light with `scrapbot.light.directional`.
- Directional light data includes direction, color, intensity, and ambient contribution.
- Mesh lighting is the authored ambient contribution plus direct directional diffuse light; there is no scene-independent fill or rim light. A directional light with `ambient = 0.0` and `intensity = 0.0` renders current non-emissive mesh surfaces black.
- The renderer uses the first available camera and first available directional light in the ECS world.
- Rendering resolves the selected camera and directional light from the authoritative scene ECS world before drawing.
- Scenes without camera or directional light components still render with compatibility defaults matching the original demo view and light.
- Camera and light component fields participate in normal scene validation, live reload, script type hints, and `scrapbot test` field assertions.

## Design Decisions

### 1. Model render view state as ECS components

**Decision:** Camera and directional light are engine-owned ECS components rather than renderer-local configuration.
**Why:** Rendering should consume the same scene data model used by validation, scripting, testing, live reload, and editor inspection. This follows ADR-001 and ADR-008.
**Tradeoff:** Early rendering scenes need a few more component tables before the editor can generate them automatically.

### 2. Preserve fallback rendering for older scenes

**Decision:** When a scene has no camera or directional light, rendering falls back to the prior fixed view and fixed light values.
**Why:** Existing test fixtures and early projects should remain valid while the scene schema grows. This keeps data-driven rendering additive for now.
**Tradeoff:** A missing camera is not yet a validation error, so projects can render through implicit defaults until stricter scene roles are introduced.

### 3. Keep the first selection rule simple

**Decision:** The renderer uses the first camera and first directional light found in the world.
**Why:** This gives text-authored scenes a deterministic rule without introducing active camera tags, scene resources, or render-layer concepts too early.
**Tradeoff:** Multi-camera, light selection, and editor preview workflows need explicit follow-up design.

### 4. Resolve selected view and light from the scene world

**Decision:** The renderer resolves the scene camera/light rule from the scene world during frame preparation and drawing. Render-only camera overrides are applied as frame input without mutating scene camera components.
**Why:** The project scene world is the authoritative ECS owner for camera and light data. This follows ADR-022.
**Tradeoff:** The extraction rule is still simple and must evolve when active cameras, render layers, and multiple lights arrive.

## Related

- **ADRs:** ADR-001, ADR-004, ADR-005, ADR-008, ADR-022
- **FDRs:** FDR-002, FDR-007, FDR-008, FDR-009, FDR-015

## Open Questions

- How should scenes mark the active camera once projects have multiple cameras?
- Should lighting expand through more component types or a render graph/resource model?
