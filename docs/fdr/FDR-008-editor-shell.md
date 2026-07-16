# FDR-008: Editor shell

**Status:** Active
**Last reviewed:** 2026-07-16

## Overview

The editor shell turns a running Scrapbot project into its own editing workspace with live playback control. It keeps the project visible in the center while transient editor-origin ECS UI entities provide the surrounding tools.

## Behavior

- A windowed WGPU project starts with editor chrome hidden unless `--editor` is passed.
- Pressing `Cmd/Ctrl+E` toggles the editor shell without restarting or changing the project's playback state.
- The shell provides a top bar, bottom status bar, left scene sidebar, and right entity/component inspector sidebar.
- The top bar contains only the Scrapbot brand and Play, Pause, Stop, Step, Undo, Redo, Save, and Revert controls. Play captures the current authoring world and then runs project systems with normal frame deltas; Pause freezes project systems and world time while editor rendering and tools remain responsive; Stop restores the captured in-memory authoring world while retaining loaded Luau and Odin systems, then remains stopped; Step captures authoring state when necessary, advances one fixed 1/60-second project update, and remains paused. Undo and Redo traverse stopped-mode authoring transactions. Save explicitly persists dirty authored values, while Revert reloads scene entities from disk without reloading project code or resources.
- The bottom bar contains only the current simulation and persistence status, such as `RUNNING`, `PAUSED`, `STOPPED`, the corresponding state with `/ UNSAVED`, `SAVE FAILED / UNSAVED`, or `REVERT FAILED / UNSAVED`; runtime statistics and keyboard hints stay in their relevant tool surfaces or documentation instead of the persistent chrome. Both bars use ordinary ECS HStacks for layout.
- The vertical boundaries around the project viewport are draggable. Resizing either sidebar preserves a minimum center viewport and the center automatically fills the remaining width.
- Each complete sidebar is a smooth scroll viewport with a contrasting 10-pixel frame around a minimum-height content pane, so the dock inset remains visually clear and short windows can reach every tool section. Systems, Scene, Inspector identity, and component sections use the same titled, collapsible ECS panel treatment: one title height, disclosure icon, charcoal title/body colors, border, and radius. The Scene panel removes inner padding so its selectable rows fill the panel from edge to edge. Separate Systems and Scene sections use a six-pixel gutter. Nested Systems, Scene, and inspector scroll areas receive wheel input when hovered; hovering sidebar padding or non-scrollable chrome addresses the outer sidebar.
- Editor chrome uses neutral near-black and charcoal surfaces, gray-to-white text, quiet gray selection, and restrained mint accents for a dense professional tool aesthetic.
- Header bands, inspector surfaces, viewport seams, and selection use the shared ECS box border fields; pooled browser rows use hidden subtrees rather than leaving the ECS lifecycle. The default desktop density uses 13-pixel text, 32-pixel scene rows, 32-pixel inspector rows around 28-pixel controls, and a 420-pixel inspector pane so labels and three-axis controls remain comfortable without becoming oversized.
- The running project's world and project-authored UI always share the complete available viewport. With the editor closed that is the full window; with the editor open it is the remaining center workspace.
- Editor chrome and the project viewport follow the current drawable size when the window is resized. The camera derives its aspect ratio from the live viewport instead of enforcing a fixed ratio.
- Visible windows request a native high-pixel-density backbuffer. Editor chrome keeps logical dimensions while text and controls paint at the display's physical pixel density.
- Project pointer coordinates are remapped into the project viewport, and pointer interaction is unavailable over editor chrome.
- Opening the editor creates an editor-origin scene camera entity with Transform, Camera, and Editor Scene Camera components. Its initial view matches the project's camera, but subsequent editor navigation does not mutate the project camera.
- Holding the right mouse button inside the viewport captures relative pointer input. While captured, mouse movement changes pitch and yaw, WASD moves along the view, Space moves up, and Ctrl moves down.
- Releasing the right mouse button restores normal pointer interaction. Closing and reopening the editor preserves the scene-camera viewpoint for the current run.
- Project cameras derive their view direction from transform rotation, and rendering, viewport picking, and transform gizmos use the same camera orientation.
- The Systems and Scene panels use the same darker reusable ECS selectable-list surface with edge-to-edge selection rows and no inner container padding. The Scene list has no count strip or nested card; it lists scene-authored and runtime-spawned entities and supports pixel-continuous pointer-wheel and trackpad scrolling, clipped partial rows, hover, and stable selection. Its stopped-mode toolbar creates, duplicates, deletes, or explicitly keeps a selected runtime entity as authored scene data.
- Above it, the systems panel uses the same selectable-list component for every engine and project system participating in the frame. Engine rows cover the editor camera, transform gizmo, ECS UI, picking, render preparation, and render submission; scheduled project-Odin and Luau systems follow them. Selection is retained for future debugger detail views but has no action yet. Right-aligned average callback times are always formatted in milliseconds with three decimal places. A mint, blue, or amber dot identifies Engine, Project Odin, or Luau provenance. A matching two-pixel bar beneath each row is anchored to the panel's right edge and grows leftward across its complete content width on an absolute scale where 10 ms fills the row. The bar has no background track. Engine names use the `scrapbot.*` namespace, project-Odin systems use their registered names, and Luau systems use their optional project-facing names with an ordinal fallback when unnamed. The profiler publishes every five successful frames from a rolling window of the last 50 successful frames and refreshes immediately when the system topology, system name, or published sample changes. A horizontal separator resizes the systems and scene panes.
- Scene-authored entity names use normal white editor text and runtime-spawned entity names use muted gray. Editor-origin entities are hidden from the browser and cannot be selected in the inspector.
- Selection follows the entity's generation-aware identity and clears if that entity despawns.
- The inspector shows the selected entity's editable name, stable UUID, provenance, attached components, field names, and current values. Components are vertically stacked collapsible titled panels, and each panel renders its fields in an edge-to-edge, resizable two-column property table with a one-third label column and two-thirds value column inside an independently scrollable sidebar. Individual label and value cells provide the horizontal inset, keeping the table geometry aligned with the panel while its contents retain comfortable spacing. Values use reusable input controls: transform, camera, light, and custom Vec3 fields are live-editable, while unsupported field types remain selectable and read-only. Vec3 value cells compose three equal-width X, Y, and Z inputs with a fill HStack; scalar value cells contain one full-width input. A stopped-mode Manage Components button opens a floating, independently scrollable menu composed from the same public layout, scroll-area, VStack, text, and button components. The menu reads the live component registry, nests dotted engine and library names by token, groups single-token project components under Project, and exposes explicit `+` add and `-` remove actions as undoable membership changes. Engine-defined scene components remain authorable; engine-managed derived components remain inspector-visible but are not offered as membership actions.
- Clicking an inspector value selects its complete contents. Cursor and selection commands work inside the field, Tab and Shift+Tab traverse values in paint order—including X, Y, and Z independently—Enter commits and leaves the field, and Escape restores the value captured when editing began.
- Numeric fields reject non-finite, unparsable, and field-invalid values with a red focus border without mutating the running world. Up and Down step by the field's default increment, Shift uses a coarse 10× step, and Ctrl/Cmd uses a fine 0.1× step. Camera planes remain positive and ordered, camera field of view stays within 1–179 degrees, and light colors and non-negative light properties remain within their valid ranges.
- Vec3 controls expose restrained red, green, and blue X/Y/Z label strips. Dragging a strip horizontally scrubs that axis; releasing commits the complete drag as one edit.
- Completed stopped-mode inspector typing, stepping, scrubbing, boolean changes, transform-gizmo drags, entity operations, and component membership changes enter one bounded transaction history. `Cmd/Ctrl+Z` undoes, `Cmd/Ctrl+Shift+Z` redoes, and `Cmd/Ctrl+S` saves scene-authoring changes while the editor is open. `Cmd/Ctrl+R` plays when stopped, resumes when paused, and stops when running. `Cmd/Ctrl+T` pauses a running project and advances one fixed step while paused or stopped. Each complete gesture or structural action is one history step, including every dependent field changed by one control; Escape and invalid values do not create history. Returning to the last successful Save position clears dirty state. Transport shortcuts do not consume project input while chrome is closed, the fly camera owns input, or a project-owned input has focus; `Cmd/Ctrl+E` remains available to reopen or close the shell.
- Entity membership, names, status counts, and formatted inspector values refresh from the running world every 200 ms. Opening the editor or changing selection refreshes immediately; a focused input is not overwritten by a periodic snapshot, and hover, scrolling, picking, gizmo input, and text editing remain frame-rate responsive.
- The scene browser and component inspector have independent pixel offsets and targets, frame-time smoothing without row or field snapping, clipping, and proportional scrollbars. Selecting a different entity resets the inspector to its beginning.
- Clicking rendered geometry in the live viewport selects the nearest intersected entity using the active camera and current viewport dimensions.
- Viewport selection reveals the entity in the scene browser; clicking empty viewport space clears selection.
- A selected entity with a Transform displays a transform gizmo in the viewport. W selects translation rails, E selects axis rotation rings, and R selects scale rails with square handles. An ECS-built viewport toolbar chooses World or Local orientation and appears only while a transform-bearing entity is selected.
- Move and scale modes include XY, XZ, and YZ plane walls. Their center handle provides camera-plane free translation in move mode and uniform XYZ scaling in scale mode.
- The editor expresses gizmo ownership as a transient `EditorTransformGizmo` component on the selected entity; its mode and World/Local space are ECS-visible, and changing selection or closing the editor removes it.
- World space keeps canonical scene axes. Local space derives the visible rails, walls, and rings from the selected Transform's rotation; translation follows those rotated axes, rotation composes around them, and scale edits the matching local scale components. A gesture freezes its world and screen bases at pointer-down so its active handles remain stable throughout the drag.
- Hovering emphasizes the nearest axis, plane, or center handle. Dragging captures the pointer and updates position, rotation, or scale according to the gizmo's ECS-visible mode and space. Mode shortcuts are ignored during RMB fly-camera capture, and the orientation toolbar receives pointer input ahead of coincident gizmo handles.
- Gizmo changes to scene-origin entities are undoable authoring transactions while stopped. While playing or paused they are disposable runtime changes and do not move the authoring-history cursor. Snapping is not part of this slice.
- Stopped is the authoring state. Inspector, gizmo, entity, and component operations on scene-origin entities mark the scene dirty. Runtime-spawned entities remain disposable unless explicitly promoted with Keep; editor-owned entities never become save candidates. Play and Step include unsaved authoring changes in their in-memory baseline. Stop removes playback-only changes while preserving dirty state, undo history, selected authored UUID, and unsaved authored entities.
- Save uses the dirty UUID candidates produced by authoring transactions and compares them with the parsed authored baseline. Value-only edits patch semantic field differences. Structural saves preserve every clean entity block verbatim, normalize only dirty entity blocks, omit deleted UUIDs, and append created or promoted UUIDs in transaction order. Duplicate names are safe and the source file is replaced atomically. Revert discards unsaved authoring and its history by rebuilding scene entities from disk while retaining loaded code, systems, and resources. Running and paused mutations remain disposable runtime state.
- Headless WGPU runs can combine `--editor` with semantic UI action replay, structured UI-tree dumps, assertions, and target-cropped framegrabs for deterministic editor workflows without OS pointer automation.

## Design Decisions

### 1. Make editing a mode of `run`

**Decision:** Toggle editor chrome around the same runtime launched by `scrapbot run` instead of introducing a separate editor executable.
**Why:** The editor should inspect the actual running world, systems, renderer, and hot-reload lifecycle rather than a parallel simulation.
**Tradeoff:** Tool and game input routing must coexist in one window.

### 2. Build chrome from transient ECS UI

**Decision:** Construct editor chrome as transient `.Editor` entities with the same UI components and retained reconciler as project UI, following ADR-021.
**Why:** The editor should prove the ECS UI system while retaining a distinct lifecycle, coordinate domain, paint order, and internal semantic bindings.
**Tradeoff:** The world contains editor UI entities, so project-facing browsers, inspectors, counts, and selection paths must filter by origin.

### 3. Use all available game space

**Decision:** Use the entire available rectangle for world projection, project UI, clipping, and pointer remapping, whether editor chrome is visible or not.
**Why:** The game should adapt to the actual window or workspace aspect ratio rather than wasting space through letterboxing.
**Tradeoff:** Until project UI gains responsive anchors and sizing policies, its 1280×720 logical coordinates scale to the live viewport dimensions.

### 4. Show authored and ephemeral entities together

**Decision:** Present one live entity list while distinguishing scene-authored and runtime-spawned entities by name color according to ADR-016.
**Why:** Debugging the running world requires access to ephemeral entities, while provenance tells users which entities belong to source data and which exist only in the current run.
**Tradeoff:** A busy runtime can produce a long, rapidly changing list, so search, grouping, and hierarchy remain important follow-up work.

### 5. Edit common fields directly in the active world

**Decision:** Bind input controls for transform, camera, light, and custom Vec3 fields directly to the selected entity's active component storage; render unsupported fields through the same control in read-only mode. Treat those mutations as authoring changes only when stopped and targeting a scene-origin entity.
**Why:** Common scene work becomes immediately useful while one consistent value-cell control preserves traversal and selection for every reflected field.
**Tradeoff:** Editing and persistence currently rely on field-specific parsing and constraints. General reflection-based mutation and structural editing remain future work.

### 6. Pick exact rendered triangles

**Decision:** Use nearest CPU triangle-ray intersections for initial viewport picking, following ADR-017.
**Why:** Exact geometry picking matches transformed meshes more closely than screen-space bounds and avoids a GPU readback pipeline at this stage.
**Tradeoff:** Picking work grows with triangle count until a broad phase or GPU identity pass is introduced.

### 7. Keep manipulation handles screen-legible

**Decision:** Reconcile an engine-owned gizmo component onto the selected entity, then let a dedicated editor system project fixed-apparent-size translation rails, rotation rings, or scale rails and manipulate the chosen Transform axis, following ADR-018.
**Why:** Tool ownership remains ECS-visible—including in the component inspector—while the controls stay consistently hittable and separate from serialized project components and lighting.
**Tradeoff:** The gizmo supports world/local single-axis and two-axis plane translation, free camera-plane translation, world/local axis rotation, local-component per-axis scaling, and uniform scaling. It does not yet support snapping, depth-aware handles, or multi-selection.

### 8. Give the editor an ECS-owned scene camera

**Decision:** Use a transient editor-origin entity for the scene camera and run captured fly navigation through a dedicated ECS system, following ADR-019.
**Why:** The camera remains inspectable and composable without mutating the project's gameplay camera or hiding tool state inside the renderer.
**Tradeoff:** The world contains engine-owned entities during editing, so provenance and camera selection must explicitly distinguish project and editor ownership.

### 9. Reserve color for identity and state

**Decision:** Build editor hierarchy from neutral dark surfaces and legible gray text, using Scrapbot mint as a thin identity and status signal rather than a panel tint. Use one 13-pixel text size throughout editor chrome and tooling; express hierarchy only through normal or bold weight and full-strength or faded color. Give every sidebar section the same collapsible titled-card tokens instead of styling Systems, Scene, identity, and component panels independently. Pair those invariants with modestly padded controls and enough default inspector width for three-axis editing.
**Why:** Low-chroma chrome keeps attention on live project content and dense inspection data while retaining a recognizable Scrapbot accent.
**Tradeoff:** Provenance and gizmo colors remain intentionally saturated semantic exceptions and must continue to meet contrast requirements.

### 10. Snapshot inspection data at tool cadence

**Decision:** Rebuild the scene-browser and formatted component-inspector snapshots at 5 Hz, with immediate refreshes when the editor opens or selection changes, while repainting and processing interaction every frame.
**Why:** World scans and value formatting do not need render-frame precision, but pointer feedback and manipulation do.
**Tradeoff:** Passive entity and field changes can take up to 200 ms to appear in the editor.

### 11. Reuse split-group layout behavior for workspace panes

**Decision:** Drive the editor's left, center, and right allocation through an editor-origin fill-enabled UI stack with draggable separators.
**Why:** Sidebars need direct manipulation and automatic center fill, and using the ordinary stack behavior proves that the same component works for application-scale layouts.
**Tradeoff:** Pane sizes persist only for the current run; project-level workspace persistence remains future work.

### 12. Compose inspection from reusable panel and table entities

**Decision:** Pool editor-origin panel, table, label, and input-cell entities and rebuild their values at the editor's snapshot cadence. Place the inspector identity card and every component panel as direct siblings in one scrollable sidebar VStack so they share the same width, horizontal inset, titled-card styling, and collapse behavior. Configure the public table component with first-row weights of `1:2` and enable its reusable draggable separator.
**Why:** Dogfooding the public UI primitives gives components real visual hierarchy and makes future editable property controls a cell-level evolution instead of a multiline-text rewrite.
**Tradeoff:** Resized column proportions remain local to the current retained UI session; they are not yet persisted as editor preferences.

### 13. Reuse the ECS input control for inspector traversal

**Decision:** Express inspector scalar/text values as ordinary `ui_input` entities and boolean values as ordinary `ui_checkbox` entities, with editor-only bindings describing the selected component field and optional Vec3 axis behind each writable control. Compose one or three controls inside the table's value cell through a fill HStack.
**Why:** The editor dogfoods public focus, selection, cursor, pointer, and boolean-control behavior instead of maintaining separate inspector widgets.
**Tradeoff:** The internal binding layer is field-specific and runtime-only; it is not a general public data-binding or command-event API.

### 14. Preview immediately and commit one authoring transaction per gesture

**Decision:** Following ADR-027, apply valid previews to the active ECS, but capture starting values and add one UUID-addressed transaction only when typing, stepping, scrubbing, a boolean change, or a complete gizmo drag commits. A transaction may contain multiple typed field changes, so a three-axis gizmo drag remains one undo step.
**Why:** Scene feedback remains immediate without turning every character or pointer pixel into a separate undo step.
**Tradeoff:** History is limited to 128 transactions. Structural entries own complete serializable entity snapshots, while field entries stay compact; dirty candidates are conservative across previews, cancellation, and undo, and semantic comparison at Save determines whether source actually differs.

### 15. Profile systems at their execution boundary

**Decision:** Feed engine frame phases and scheduled project callbacks into one fixed-storage rolling timing snapshot, then render it through a titled, two-column, smoothly scrollable ECS UI panel above the scene list. Engine timing begins at the actual editor-camera, transform-gizmo, ECS-UI, picking, render-preparation, and render-submission execution boundaries. Compose each row from ordinary ECS boxes: a provenance-colored rounded marker beside the name and one trackless, right-anchored bar beneath the row. Size that bar against a fixed 10 ms maximum and the panel's complete live content width. Nest that panel and the complete scene pane in a draggable fill VStack.
**Why:** System costs should be visible in the same live world the editor inspects, and the panel should dogfood the ordinary panel, table, text, and scroll-area components.
**Tradeoff:** Unnamed legacy Luau systems still receive ordinal fallback labels. GPU submission measures CPU callback time through queue submission rather than asynchronous GPU execution. Values over 10 ms clamp to a full-width bar, and the rolling average favors a stable comparison over single-frame spikes. Times remain diagnostic samples rather than a full frame profiler.

### 16. Gate project simulation without freezing editor services

**Decision:** Store transport state in the editor UI state and gate the project frame-system callback at the render-loop boundary. Continue rendering and processing editor UI, scene-camera, picking, and gizmo systems while project simulation is paused or stopped. Capture every scene-origin entity and its component revision when playback begins. Consume Step as one fixed 1/60-second project update. Consume Stop as a one-shot restoration of that in-memory baseline before another project update can execute while retaining the loaded Luau VM, Odin extensions, scheduler, resources, and registered systems.
**Why:** Transport controls must stop project mutation without making the editor itself unresponsive, a fixed step gives frame-by-frame inspection stable time semantics, and Stop must discard simulation without destroying unsaved authoring work or reloading code and source files.
**Tradeoff:** Restoring the baseline rebuilds the active world and discards runtime-spawned entities, but project-script global state remains alive because code runtimes are intentionally retained. Keeping concurrent authoring and play worlds remains future work.

### 17. Make stopped authoring persistence explicit

**Decision:** Following ADR-026 through ADR-028, treat Stopped as authoring mode and mark transaction target UUIDs for authored or explicitly promoted entities as dirty candidates. Let Play and Step snapshot dirty authoring state without writing it. Save compares candidates with the disk-authored baseline, patches value-only differences, rewrites only structurally dirty entity blocks, and excludes unpromoted runtime/editor entities. The history records the successful Save cursor as clean. Stop restores the in-memory playback baseline, while explicit Revert restores the disk-authored baseline and clears history.
**Why:** Explicit persistence prevents simulation output from leaking into source while still making the live ECS world useful for authoring. Stable UUIDs keep persistence correct when names are duplicated or changed.
**Tradeoff:** The single-world model restores authoring state only when playback stops rather than keeping it concurrently inspectable. Revert is intentionally destructive and cannot itself be undone. A structurally rewritten entity block uses canonical TOML formatting, and runtime-generated resources are not automatically promoted into project resource declarations.

### 18. Separate component definition from runtime ownership

**Decision:** Let stopped authoring add or remove every registry component with a scene-serializable representation, including engine-defined Transform, camera, light, render, and UI components. Keep engine-managed derived components visible for inspection but omit them from membership actions.
**Why:** A component being defined by Scrapbot does not mean the engine owns its membership on a particular scene entity. Derived render and editor state, however, is reconciled by engine systems and cannot be meaningfully authored or removed by users.
**Tradeoff:** The registry's namespace and owner identify who defines a component, while the editor maintains a narrower authoring-support policy until serializability and runtime ownership become explicit registry metadata.

### 19. Reserve command-modified keys for editor commands

**Decision:** Route command-modified E, R, and T through the editor input path as shell toggle, Play/Stop, and Pause/Step commands. Ignore command-modified E and R in the unmodified transform-gizmo shortcut path, and gate transport commands while project text input or fly-camera capture owns the keyboard.
**Why:** Playback controls need fast platform-native shortcuts without stealing ordinary project input or accidentally changing the active transform tool.
**Tradeoff:** The shell toggle remains global by design, while transport shortcuts only work when the editor is visible and no higher-priority project or camera interaction owns input.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-014, ADR-016, ADR-017, ADR-018, ADR-019, ADR-021, ADR-023, ADR-024, ADR-026, ADR-027, ADR-028
- **FDRs:** FDR-001, FDR-003, FDR-007

## Open Questions

- Should Scrapbot eventually maintain concurrent authoring and playback worlds?
- Which panel layout and sizing state should persist per project?
- How should editor camera speed, bookmarks, and focus-selection navigation persist?
