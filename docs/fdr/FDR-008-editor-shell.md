# FDR-008: Editor shell

**Status:** Active
**Last reviewed:** 2026-07-13

## Overview

The editor shell turns a running Scrapbot project into its own editing workspace without stopping play. It keeps the project visible in the center while reserving stable engine-owned regions for current status and future scene and entity inspection tools.

## Behavior

- A windowed WGPU project starts with editor chrome hidden unless `--editor` is passed.
- Pressing `Ctrl+Esc` toggles the editor shell without restarting or pausing the project.
- The shell provides a top bar, bottom status bar, left scene sidebar, and right entity/component inspector sidebar.
- The running project's world and project-authored UI always share the complete available viewport. With the editor closed that is the full window; with the editor open it is the remaining center workspace.
- Editor chrome and the project viewport follow the current drawable size when the window is resized. The camera derives its aspect ratio from the live viewport instead of enforcing a fixed ratio.
- Project pointer coordinates are remapped into the project viewport, and pointer interaction is unavailable over editor chrome.
- Opening the editor creates an editor-origin scene camera entity with Transform, Camera, and Editor Scene Camera components. Its initial view matches the project's camera, but subsequent editor navigation does not mutate the project camera.
- Holding the right mouse button inside the viewport captures relative pointer input. While captured, mouse movement changes pitch and yaw, WASD moves along the view, Space moves up, and Ctrl moves down.
- Releasing the right mouse button restores normal pointer interaction. Closing and reopening the editor preserves the scene-camera viewpoint for the current run.
- Project cameras derive their view direction from transform rotation, and rendering, viewport picking, and transform gizmos use the same camera orientation.
- The scene sidebar lists every live entity and supports pointer-wheel scrolling, hover, and stable selection.
- Scene-authored entities use mint provenance labels, runtime-spawned entities use amber labels, and editor-owned entities use violet labels. All remain selectable and inspectable.
- Selection follows the entity's generation-aware identity and clears if that entity despawns.
- The inspector shows the selected entity's name, identity, provenance, attached components, field names, and current values.
- The scene browser and component inspector scroll independently, and selecting a different entity resets the inspector to its beginning.
- Clicking rendered geometry in the live viewport selects the nearest intersected entity using the active camera and current viewport dimensions.
- Viewport selection reveals the entity in the scene browser; clicking empty viewport space clears selection.
- A selected entity with a Transform displays red X, green Y, and blue Z translation handles in the viewport.
- The editor expresses gizmo ownership as a transient `EditorTransformGizmo` component on the selected entity; changing selection or closing the editor removes it.
- Hovering emphasizes the nearest axis. Dragging an axis captures the pointer and moves the entity along that world axis while the inspector reports live values.
- Gizmo changes affect the running world only; scene persistence, snapping, and undo are not part of this slice.
- Headless WGPU runs can combine `--editor` with `--framegrab` for deterministic editor-shell screenshots.

## Design Decisions

### 1. Make editing a mode of `run`

**Decision:** Toggle editor chrome around the same runtime launched by `scrapbot run` instead of introducing a separate editor executable.
**Why:** The editor should inspect the actual running world, systems, renderer, and hot-reload lifecycle rather than a parallel simulation.
**Tradeoff:** Tool and game input routing must coexist in one window.

### 2. Keep chrome outside project ECS UI

**Decision:** Editor chrome is retained engine state rendered after project content, following ADR-015.
**Why:** Editor lifecycle must survive scene replacement and remain inaccessible to project serialization or scripts.
**Tradeoff:** Editor controls need a separate command bridge before they can mutate ECS state.

### 3. Use all available game space

**Decision:** Use the entire available rectangle for world projection, project UI, clipping, and pointer remapping, whether editor chrome is visible or not.
**Why:** The game should adapt to the actual window or workspace aspect ratio rather than wasting space through letterboxing.
**Tradeoff:** Until project UI gains responsive anchors and sizing policies, its 1280×720 logical coordinates scale to the live viewport dimensions.

### 4. Show authored and ephemeral entities together

**Decision:** Present one live entity list while visibly labeling scene-authored and runtime-spawned entities according to ADR-016.
**Why:** Debugging the running world requires access to ephemeral entities, while provenance tells users which entities belong to source data and which exist only in the current run.
**Tradeoff:** A busy runtime can produce a long, rapidly changing list, so search, grouping, and hierarchy remain important follow-up work.

### 5. Keep initial inspection read-only

**Decision:** Selection exposes component fields and live values without allowing mutation yet.
**Why:** This makes the inspector useful for debugging while avoiding premature commitments around validation, persistence, and undo semantics.
**Tradeoff:** Users can diagnose current world state but cannot change it from the inspector yet.

### 6. Pick exact rendered triangles

**Decision:** Use nearest CPU triangle-ray intersections for initial viewport picking, following ADR-017.
**Why:** Exact geometry picking matches transformed meshes more closely than screen-space bounds and avoids a GPU readback pipeline at this stage.
**Tradeoff:** Picking work grows with triangle count until a broad phase or GPU identity pass is introduced.

### 7. Keep manipulation handles screen-legible

**Decision:** Reconcile an engine-owned gizmo component onto the selected entity, then let a dedicated editor system project its world axes into fixed-apparent-size screen overlay handles and translate along the chosen world axis, following ADR-018.
**Why:** Tool ownership remains ECS-visible—including in the component inspector—while the controls stay consistently hittable and separate from serialized project components and lighting.
**Tradeoff:** The first gizmo is always world-oriented and supports only single-axis translation without persistence or undo.

### 8. Give the editor an ECS-owned scene camera

**Decision:** Use a transient editor-origin entity for the scene camera and run captured fly navigation through a dedicated ECS system, following ADR-019.
**Why:** The camera remains inspectable and composable without mutating the project's gameplay camera or hiding tool state inside the renderer.
**Tradeoff:** The world contains engine-owned entities during editing, so provenance and camera selection must explicitly distinguish project and editor ownership.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018, ADR-019
- **FDRs:** FDR-001, FDR-003, FDR-007

## Open Questions

- How should editor edit commands cross into the running ECS?
- Which panel layout and sizing state should persist per project?
- How should editor camera speed, bookmarks, and focus-selection navigation persist?
