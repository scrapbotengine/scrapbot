# FDR-008: Editor shell

**Status:** Active
**Last reviewed:** 2026-07-31

## Overview

The editor shell turns a running Scrapbot project into its own editing workspace with live playback control. It keeps the project visible in the center while transient editor-origin ECS UI entities provide the surrounding tools.

## Behavior

- A windowed WGPU project starts with editor chrome hidden unless `--editor` is passed.
- Pressing `Cmd/Ctrl+E` opens or closes the editor shell without restarting the project. Opening preserves the current running, paused, or stopped transport state; closing always starts or resumes normal playback.
- The shell provides a top bar, bottom status bar, left scene sidebar, and right entity/component inspector sidebar.
- While the shell is visible, every non-editor camera with a valid world Transform receives a world-scaled wireframe body and lens in the scene viewport. The editor-owned fly camera is excluded.
- The selected camera additionally shows a projection-frustum preview derived from FOV, near clip, viewport aspect, and world transform. It extends five world units or stops at a shorter far clip, preventing ordinary long ranges from dominating a zoomed-out view.
- Clicking a camera body or selected frustum stroke selects its entity before rendered-triangle picking. Camera visualizers and transform gizmos paint above project UI but remain clipped to Game and below editor chrome, so covering tabs and panels occlude them.
- The top bar contains only the Scrapbot brand and Play, Pause, Stop, Step, Undo, Redo, Save, and Revert.
- Play captures authoring state and runs project systems with normal deltas. Pause freezes project systems and world time while tools remain responsive; clicking it again resumes. Stop restores the captured world while retaining loaded Luau and Odin systems. Step captures when necessary, advances one fixed 1/60-second update, and remains paused.
- Undo and Redo traverse stopped-mode transactions. Save validates every dirty authored scene and resource value, then commits the file set as one recoverable project transaction. Revert reloads resources and scene entities without reloading project code.
- The bottom bar contains only simulation and persistence status. Running and paused states read `PLAY MODE / <STATE> / CHANGES ARE TEMPORARY`; a pre-existing dirty authoring baseline also adds `/ UNSAVED AUTHORING`. The top and bottom bars always use the same neutral chrome-bar recipe as the rest of the editor. While in play mode, amber status text and a two-pixel viewport frame persist through both Running and Paused without repainting either application bar as a different surface. Stopped mode reports `STOPPED`, optionally with `/ UNSAVED`. Save/revert failures remain explicit. Runtime statistics and keyboard hints stay in their relevant tool surfaces or documentation instead of the persistent chrome. Both bars use ordinary ECS HStacks for layout.
- Browse, Game, and Inspect are ordinary editor-origin `ui_dock_item` entities inside public `ui_dock_space` groups. Browse and Inspect may transfer between the existing draggable groups; Game remains fixed because it owns the central project viewport. The groups live inside the same public draggable fill HStack that owns the vertical pane boundaries, minimum sidebar sizes, and center fill. The editor owns panel content and bindings but no private docking tree, tab renderer, drag logic, or docking styles.
- Browse, Game, and Inspect each host one public reorderable VStack inside their dock item. The Game stack begins with the fixed live viewport and uses the same public fill, separator, ordering, and drop mechanics as both sidebars.
- Each complete sidebar dock is a smooth scroll viewport with a 10-pixel inset around a minimum-height content pane. The tab strip remains fixed, and short windows can still reach every tool section.
- Performance, Systems, Scene, and Resources are movable public panels inside Browse. Inspect uses explicit stable ordering for its header and runtime-reflected component panels.
- Title dragging can reorder public siblings, transfer a panel into an existing tab stack, or create a tab on empty dock-space chrome. A tab-header drop targets that tab's stack even when inactive; otherwise the deepest compatible content stack under the pointer wins. A docked panel can return through its tab.
- A title click still collapses its panel. Crossing the drag threshold and releasing without a destination cancels without changing collapse state.
- Systems, Scene, Inspector identity, and component sections share one titled ECS panel treatment: a common title height, disclosure icon, near-black tonal elevation, and subtle radius without card outlines. Scene removes inner padding so selectable rows fill the panel edge to edge.
- Nested Systems, Scene, and Inspector scroll areas receive the wheel while hovered. Hovering sidebar padding or non-scrollable chrome addresses the outer sidebar instead.
- Authoring chrome uses Unity-Pro-like almost-black surfaces, embedded Inter typography, gray-to-white text, tonal selection, and restrained mint accents for a dense professional tool aesthetic. Disposable playback is the deliberate amber exception.
- Header bands, inspector surfaces, controls, popups, and selection use tonal contrast and softly rounded public ECS boxes instead of persistent one-pixel outlines. Focus, validation, destructive actions, and playback may use stronger semantic emphasis. Pooled browser rows use hidden subtrees rather than leaving the ECS lifecycle. The default desktop density uses 13-pixel body text, 12-pixel technical section titles, 32-pixel scene rows, 32-pixel inspector rows around 28-pixel controls, and a 420-pixel inspector pane so labels and three-axis controls remain comfortable without becoming oversized.
- Editor composition applies the same engine-owned reduced-dark recipes exposed to scene TOML, Luau, and native Odin before writing ordinary public component values. The renderer has no editor-theme path, and editor bindings add project meaning without owning visual mechanics.
- The running project's world and project-authored UI always share the complete available viewport. With the editor closed that is the full window; with the editor open it is the remaining center workspace.
- The Game viewport has a public-ECS popup selector for `Camera`, Lit, Base Color, World Normals, Roughness, Metallic, Depth, Meshlets, LOD, Meshlet Visibility, Hi-Z, and Occlusion Queries. Hi-Z adds ordinary adjacent minus/label/plus controls for selecting a retained pyramid mip. Occlusion Queries adds an ordinary Freeze toggle for preserving the latest valid GPU evidence. `Camera` follows authored debug settings; editor choices override only the extracted camera copy, so inspection never enters history or marks the scene dirty.
- Editor chrome and the project viewport follow the current drawable size when the window is resized. The camera derives its aspect ratio from the live viewport instead of enforcing a fixed ratio.
- The derived project viewport is intersected with the physical render target. Extremely small or high-density diagnostic targets may clip editor chrome, but no world, postprocess, or UI pass may emit a viewport or scissor beyond the target.
- Visible windows request a native high-pixel-density backbuffer. Editor chrome keeps logical dimensions while text and controls paint at the display's physical pixel density.
- Project pointer coordinates are remapped into the project viewport, and pointer interaction is unavailable over editor chrome.
- Opening the editor creates an editor-origin scene camera entity with Transform, Camera, and Editor Scene Camera components. Its initial view matches the project's camera, but subsequent editor navigation does not mutate the project camera.
- Holding the right mouse button inside the viewport captures relative pointer input. While captured, mouse movement changes pitch and yaw, WASD moves along the view, Space moves up, and Ctrl moves down.
- Releasing the right mouse button restores normal pointer interaction. Closing and reopening the editor preserves the scene-camera viewpoint for the current run.
- Project cameras derive their view direction from transform rotation, and rendering, viewport picking, and transform gizmos use the same camera orientation.
- Systems and Scene share the darker reusable ECS selectable-list surface with subtly rounded, edge-to-edge selection rows and no inner container padding. Their badge-free filters share the rows' exact outer bounds and use public input-icon fields for the leading search symbol.
- Both panels compose an ordinary public `ui_input`, `ui_list`, and `ui_scroll_area`. Each list references its filter input by UUID and uses public uniform-row virtualization.
- Scene renders the Transform UUID graph as an expandable tree in stable scene order, without a count strip or nested card. It includes authored roots and runtime spawns, case-insensitive filtering, pixel-continuous scrolling, clipped partial rows, hover, stable selection, and generic direct-child dragging.
- Filtered Scene results retain their ancestors and reveal matches below collapsed branches without changing collapse state. Reusable SDF chevron icon buttons collapse branches.
- A drop on a Scene row's middle makes that row the new parent. A drop on its top or bottom insertion zone adopts the target's parent and places the source before or after it atomically. Empty-list space makes the entity a root.
- A transformless child receives an identity Transform; a transformless parent contributes an identity spatial basis. The stopped-mode toolbar creates, duplicates, deletes, or explicitly keeps a selected runtime entity as authored scene data.
- The Resources panel independently composes the same public filter-input, virtualized-list, and scroll-area contract around its pooled uniform rows. Filtering matches authored resource names case-insensitively without changing selection or registry state; scrolling lays out only the visible rows plus bounded overscan. Its fixed toolbar remains outside list row flow.
- Systems lists every engine and project system participating in the frame. Its public filter matches row content case-insensitively, and uniform-row virtualization lays out only visible matches plus overscan.
- Engine rows cover the editor camera, transform gizmo, ECS UI, picking, render preparation, and render submission. Scheduled project-Odin and Luau systems follow. Selection is retained for future debugger detail views but has no action yet.
- Right-aligned average callback times use milliseconds with three decimal places. A mint, blue, or amber dot identifies Engine, Project Odin, or Luau provenance. A matching two-pixel bar grows leftward from the panel's right edge on an absolute scale where 10 ms fills the complete content width; it has no background track.
- Engine names use `scrapbot.*`, project-Odin systems use their registered names, and Luau systems use optional project-facing names with an ordinal fallback.
- The profiler publishes every five successful frames from a rolling 50-frame window. It refreshes immediately when system topology, a system name, or the published sample changes. A horizontal separator resizes the Systems and Scene panes.
- Scene-authored entity names use normal white editor text and runtime-spawned entity names use muted gray. Editor-origin entities are hidden from the browser and cannot be selected in the inspector. Stopped-mode hierarchy authoring allows scene entities to use only scene parents, preserves world pose, rejects cycles, and enters one undoable structural transaction. Playback reparenting is disposable. Runtime parent removal detaches children without teleporting them; authored parents with children must be emptied before deletion.
- Selection follows the entity's generation-aware identity and clears if that entity despawns.
- Authored Material components show a reusable resource selector plus inline base-color and HDR-emissive controls. Resource data stays outside ECS; only this editor presentation is composed from ECS UI entities.
- Material numeric controls remain writable while running or paused for immediate disposable previews. The playback baseline captures authored material values alongside scene entities, so Stop restores runtime resource edits. Only stopped-mode material edits enter authoring history or dirty state.
- The inspector shows the selected entity's editable name, stable UUID, provenance, attached components, field names, and current values.
- Component cards come entirely from live registry membership and runtime inspection of canonical typed payloads. Project/native dynamic components use registry schemas as runtime type metadata. No component owns an editor panel builder or hand-authored row list.
- Components form vertically stacked, collapsible titled panels in an independently scrollable sidebar. Each panel renders discovered fields in an edge-to-edge resizable property table with one-third label and two-thirds value columns. Cell-level inset keeps content comfortable without disturbing table alignment.
- Registry definitions may mark bookkeeping-heavy components as advanced. They remain visible and inspectable but start collapsed whenever a pooled panel is rebound; the user's expansion persists for the current binding. Marker components naturally produce title-only cards.
- Bool, String, Number, Vec2, Vec3, Vec4, and Color fields select reusable checkbox, input, and HDR color-picker controls from runtime type and honest registry semantics. Vector controls compose two to four equal-width axis inputs in a fill HStack. Field metadata supplies validation, staged keyboard editing, and optional live scrubbing. Engine-managed derived values and unsupported payload types remain read-only.
- Runtime-reflected Odin enums and `Entity_UUID` fields compose public buttons and popup-layout roots from ordinary list, input, and scroll content. Shared UI owns anchoring, viewport clamping, filtering, virtualization, dismissal, and close-on-selection.
- Enum options come from the live type. Entity-reference candidates are UUID-backed scene entities validated for the field's relationship semantics. `None` clears a reference, duplicate names show UUID prefixes, cycles and incompatible targets are omitted, and missing or current UUIDs remain visible for repair.
- Add Component opens a floating menu composed from public layout, VStack, input, list, scroll-area, text, and button components. Its UUID-linked filter matches generated group/item text case-insensitively. Mixed-height group and item rows use ordinary filtered flow instead of uniform-row virtualization.
- The Add Component menu reads the live registry, reuses cached name tokens, and rebuilds its sorted definition cache only when the registry revision changes. It nests dotted engine and library names by token, groups single-token project components under Project, and lists only components absent from the selected entity.
- Every removable component panel places an ordinary direct-child icon button in its title band. Activating it removes the component without toggling collapse.
- Stopped scene-entity membership changes are exact per-component undoable authoring transactions. Running and paused changes apply immediately to scene or runtime entities as disposable playback state. Engine-defined scene components remain mutable because the entity owns their membership; engine-managed derived components remain visible without a removal action.
- Nested records and fixed arrays appear as recursively expandable rows with field/item counts. Each disclosure is an ordinary public button, and expanded leaves reuse the same public typed controls and component-snapshot history path as top-level values. Collapsed containers do not materialize descendant controls. Dynamic arrays cannot resize or reorder until their schemas can express those mutation semantics.
- Clicking an inspector value selects its complete contents. Cursor and selection commands work inside the field. Numeric typing and keyboard stepping remain staged until Enter commits and leaves the field; Escape, focus loss, and Tab/Shift+Tab restore the captured value without creating history. Tab traversal still follows paint order—including X, Y, and Z independently. Pointer scrubbing remains a live preview and commits as one transaction on release.
- Numeric fields reject non-finite, unparsable, and field-invalid values with a red focus border without mutating the running world. Up and Down step by the field's default increment, Shift uses a coarse 10× step, and Ctrl/Cmd uses a fine 0.1× step. Camera planes remain positive and ordered, camera field of view stays within 1–179 degrees, and light colors and non-negative light properties remain within their valid ranges.
- Vector controls expose restrained red, green, blue, and amber X/Y/Z/W label strips. Custom Number, Vec2, Vec3, Vec4, and Color fields use registry editor metadata to opt individual numeric controls into whole-surface scrubbing, stepping, and bounds; built-in writable numeric adapters opt in explicitly. Releasing a scrub commits the complete drag as one edit.
- Completed stopped-mode inspector edits, gizmo drags, entity operations, and component membership changes enter one bounded transaction history. Each complete gesture or structural action is one step, including dependent fields changed by one control; Escape and invalid values create none. Returning to the last successful Save position clears dirty state.
- `Cmd/Ctrl+Z` undoes, `Cmd/Ctrl+Shift+Z` redoes, and `Cmd/Ctrl+S` saves while the editor is open. `Cmd/Ctrl+R` plays when stopped, resumes when paused, and stops when running. `Cmd/Ctrl+T` pauses a running project and advances one fixed step while paused or stopped.
- Transport shortcuts do not consume project input while chrome is closed, the fly camera owns input, or a project-owned input has focus. `Cmd/Ctrl+E` remains available to open or close the shell.
- Entity membership, names, resource-browser values, and the selected entity's running component values refresh from the live world every 200 ms. The inspector also refreshes immediately when selection, component membership revision, selected resource version, or authoring mode changes. Stopped-mode inspector values remain change-driven. A focused input is not overwritten by a snapshot, and hover, scrolling, picking, gizmo input, and text editing remain frame-rate responsive.
- The Scene and Resource browsers and component inspector have independent pixel offsets and targets, frame-time smoothing without row or field snapping, clipping, and proportional scrollbars. Browser scrolling lays out only visible 32-pixel rows plus bounded overscan; filter/content/hierarchy revisions rebuild compact row order, while stable frames and scroll-only frames do not scan all rows. Selecting a different entity resets the inspector to its beginning.
- Clicking rendered geometry in the live viewport selects the nearest intersected entity using the active camera and current viewport dimensions.
- Viewport selection reveals the entity in the scene browser; clicking empty viewport space clears selection.
- A selected entity with a Transform displays a transform gizmo in the viewport. W selects translation rails, E selects axis rotation rings, and R selects scale rails with square handles. An ECS-built viewport toolbar chooses World or Local orientation and appears only while a transform-bearing entity is selected.
- Move and scale modes include XY, XZ, and YZ plane walls. Their center handle provides camera-plane free translation in move mode and uniform XYZ scaling in scale mode.
- The editor expresses gizmo ownership as a transient `EditorTransformGizmo` component on the selected entity; its mode and World/Local space are ECS-visible, and changing selection or closing the editor removes it.
- World space keeps canonical scene axes. Local space derives the visible rails, walls, and rings from the selected entity's resolved world rotation; translation follows those rotated axes, rotation composes around them, and scale edits the matching local scale components. A gesture freezes its world and screen bases at pointer-down so its active handles remain stable throughout the drag. For parented entities, gizmos manipulate the world pose and convert the result back into local Transform values.
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

**Decision:** Use the entire available rectangle for world projection and give that same host rectangle to the project's public `scrapbot.ui_canvas` transform for project UI, clipping, pointer remapping, and semantic diagnostics, whether editor chrome is visible or not.
**Why:** The game should adapt to the actual window or workspace aspect ratio while each project explicitly chooses whether its UI expands, letterboxes, crops, stretches, or preserves integer pixels.
**Tradeoff:** Project UI may intentionally leave bars or crop when its authored canvas policy differs from the free-aspect world viewport. Projects without a canvas retain the legacy top-left 1280×720 fit.

### 4. Keep runtime churn out of the default entity browser

**Decision:** Present scene-authored entities by default. Do not materialize browser rows for every runtime spawn. When viewport picking or another tool selects a runtime entity, surface that selected entity in muted text so it remains inspectable according to ADR-016.
**Why:** High-churn simulations can create tens of thousands of short-lived entities that are useful to ECS systems and rendering but actively harmful as continuously reconciled editor widgets. Authored hierarchy remains stable, while an explicitly selected runtime entity is still debuggable.
**Tradeoff:** Runtime entities cannot currently be browsed exhaustively. Search, an opt-in runtime filter, and a public inspectability policy remain follow-up work; they must preserve bounded row materialization rather than restoring one UI entity per live runtime entity.

### 5. Edit reflected fields through typed snapshots

**Decision:** Enumerate attached components from the live registry, locate their canonical payload through the registry storage kind, and derive panel titles and rows by runtime payload inspection. Odin-backed structs expose their actual runtime fields; project/native dynamic payloads use the registry schema as their runtime type description. Select reusable checkbox/input rows only from discovered field types, compose reflected Odin enums from a public popup-layout root plus ordinary button/list/scroll primitives and runtime enum names, apply validated per-component snapshots on commit, render markers as title-only cards, and keep derived or unsupported values read-only. Never add component-name branches or per-component panel builders.
**Why:** A newly registered or newly extended component becomes inspectable without editor composition work, and the inspector cannot silently drift into a second component schema. Component-scoped snapshots piggyback on structural authoring history, undo/redo, and persistence without rewriting unrelated entity data.
**Tradeoff:** Storage-kind adapters still locate canonical payloads, and component validation may specialize by semantic invariant. Semantic Color fields use the public `ui_color_picker`; reflected Vec3/Vec4 fields remain numeric unless their registry type is Color. Dynamic project/native schemas do not yet describe enum choices or entity-reference fields. Arrays, nested values, and unknown types remain visible only when a generic read-only representation exists.

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

**Decision:** Apply the shared reduced-dark recipe vocabulary to every editor surface and control:

- Keep local editor code responsible only for geometry, content, and semantic recipe selection. Application bars, selected and warning buttons, semantic frames, provenance colors, vector axes, and transient overlays come from the theme contract.
- Build hierarchy from almost-black tonal surfaces and embedded Inter text. Use Scrapbot mint sparingly for identity, focus, selection, and authoring status; reserve amber for disposable playback.
- Use 13-pixel body text and 12-pixel technical section titles.
- Keep resting controls and panels borderless with subtle radii. Communicate hierarchy through surface elevation and reserve stronger fields or thicker soft emphasis for meaningful state.
- Render each dock group as one subtly padded elevated sheet with quiet inactive labels and a top-rounded active tab connected to the sheet.
- Give every sidebar section the same collapsible titled-panel recipe instead of styling Systems, Scene, identity, and component panels independently.

**Why:** Low-chroma chrome keeps attention on live project content and dense inspection data while retaining a recognizable Scrapbot accent.
**Tradeoff:** The editor deliberately uses only a restrained subset of the public style space. Playback, provenance, validation, and gizmo colors remain intentionally saturated semantic exceptions and must continue to meet contrast requirements.

### 10. Snapshot inspection data at tool cadence

**Decision:** Refresh scene/resource browsers and the selected entity's formatted inspector values at 5 Hz while simulation is running. Keep stopped-mode inspector refresh change-driven through selected component revision, selected resource version, selection, and authoring-mode changes. Opening the editor or changing selection refreshes immediately. During a numeric scrub, mutate the bound ECS/resource value and input text directly and defer browser, profiler, and inspector snapshots until the gesture ends. Never replace the actively focused input's staged text from a snapshot.
**Why:** Runtime systems may mutate existing component storage without changing membership revisions, so bounded value sampling keeps the live inspector honest without returning to per-frame rebuilding. Stopped authoring remains fully reactive, and pointer feedback and manipulation remain frame-responsive.
**Tradeoff:** Passive running-world changes can take up to 200 ms to appear. A visible running inspector performs bounded formatting work at 5 Hz even when the selected values are stable, and profiler values intentionally remain frozen during a continuous scrub before refreshing on release.

### 11. Reuse split-group layout behavior for workspace panes

**Decision:** Drive left, center, and right allocation through an editor-origin fill-enabled public HStack with draggable separators. Make each region a public dock space and its tool content a public dock item, following ADR-045. Lock the Game item itself, but opt its center dock into both public split axes so movable tools can create Game/Scene-style side-by-side or stacked regions.
**Why:** Sidebars need direct manipulation, tab transfer, edge-created regions, and automatic center fill, and using ordinary stack/dock behavior proves that the same components work for project-scale applications.
**Tradeoff:** Pane sizes and transferred items persist only for the current run. Same-group tab reordering, automatic empty-branch collapse, floating windows, and saved workspace layouts remain future work.

### 12. Compose inspection from reusable panel and table entities

**Decision:** Pool editor-origin panel, table, label, and input-cell entities and rebuild their values at the editor's snapshot cadence. Place the inspector identity card and every component panel as direct siblings in one scrollable sidebar VStack so they share the same width, horizontal inset, titled-card styling, and collapse behavior. Configure the public table component with first-row weights of `1:2` and enable its reusable draggable separator.
**Why:** Dogfooding the public UI primitives gives components real visual hierarchy and makes future editable property controls a cell-level evolution instead of a multiline-text rewrite.
**Tradeoff:** Resized column proportions remain local to the current retained UI session; they are not yet persisted as editor preferences.

### 13. Reuse the ECS input control for inspector traversal

**Decision:** Express inspector scalar/text values as ordinary `ui_input` entities and boolean values as ordinary `ui_checkbox` entities, with editor-only bindings describing the selected component field and optional vector axis behind each writable control. Compose one to four controls inside the table's value cell through a fill HStack.
**Why:** The editor dogfoods public focus, selection, cursor, pointer, and boolean-control behavior instead of maintaining separate inspector widgets.
**Tradeoff:** The internal binding layer stores a runtime component ID, reflected field index, and optional vector axis; it is not a general public data-binding or command-event API.

### 14. Stage keyboard edits and commit one authoring transaction per gesture

**Decision:** Following ADR-027, keep typed numeric text and keyboard stepping staged in the focused control until Enter, while applying pointer scrubbing, boolean changes, and gizmo drags as live previews. Capture starting values and add one UUID-addressed transaction only when the complete interaction commits. A transaction may contain multiple typed field changes, so a three-axis gizmo drag remains one undo step.
**Why:** Keyboard edits never leak incomplete values into simulation, while direct-manipulation gestures retain immediate scene feedback without turning every pointer pixel into a separate undo step.
**Tradeoff:** History is limited to 128 transactions. Structural entries own complete serializable entity snapshots, while field entries stay compact; dirty candidates are conservative across previews, cancellation, and undo, and semantic comparison at Save determines whether source actually differs.

### 15. Profile systems at their execution boundary

**Decision:** Feed engine CPU frame phases and scheduled project callbacks into one fixed-storage rolling timing snapshot, then render it through a titled, two-column, smoothly scrollable ECS UI panel above the scene list. Engine timing begins at the actual editor-camera, transform-gizmo, ECS-UI, picking, render-preparation, culling, shadow, world, postprocess, UI encoding, command-finalization, queue-submission, and presentation execution boundaries. Compose each row from ordinary ECS boxes: a provenance-colored rounded marker beside the name and one trackless, right-anchored bar beneath the row. Size that bar against a fixed 10 ms maximum and the panel's complete live content width. Nest that panel and the complete scene pane in a draggable fill VStack.
**Why:** System costs should be visible in the same live world the editor inspects, and the panel should dogfood the ordinary panel, table, text, and scroll-area components.
**Tradeoff:** Unnamed legacy Luau systems still receive ordinal fallback labels. All `scrapbot.render.*` rows measure CPU encoding and API boundaries, not asynchronous GPU execution. Values over 10 ms clamp to a full-width bar, and the rolling average favors a stable comparison over single-frame spikes. Times remain diagnostic samples rather than a full frame profiler.

### 16. Gate project simulation without freezing editor services

**Decision:** Store transport state in the editor UI state and gate the project frame-system callback at the render-loop boundary. Continue rendering and processing editor UI, scene-camera, picking, and gizmo systems while project simulation is paused or stopped. Capture every scene-origin entity and its component revision when playback begins. Consume Step as one fixed 1/60-second project update. Consume Stop as a one-shot restoration of that in-memory baseline before another project update can execute while retaining the loaded Luau VM, Odin extensions, scheduler, resources, and registered systems.
**Why:** Transport controls must stop project mutation without making the editor itself unresponsive, a fixed step gives frame-by-frame inspection stable time semantics, and Stop must discard simulation without destroying unsaved authoring work or reloading code and source files.
**Tradeoff:** Restoring the baseline rebuilds the active world and discards runtime-spawned entities, but project-script global state remains alive because code runtimes are intentionally retained. Keeping concurrent authoring and play worlds remains future work.

### 17. Make stopped authoring persistence explicit

**Decision:** Following ADR-026 through ADR-028 and ADR-031, treat Stopped as authoring mode and mark transaction target UUIDs for authored or explicitly promoted entities as dirty candidates. Let Play and Step snapshot dirty authoring state without writing it. Save compares candidates with the disk-authored baseline, patches value-only differences, rewrites only structurally dirty entity blocks, excludes unpromoted runtime/editor entities, and commits all prepared scene/resource files through one recoverable project transaction. The history records the successful Save cursor as clean. Stop restores the in-memory playback baseline, while explicit Revert restores the disk-authored baseline and clears history.
**Why:** Explicit persistence prevents simulation output from leaking into source while still making the live ECS world useful for authoring. Stable UUIDs keep persistence correct when names are duplicated or changed.
**Tradeoff:** The single-world model restores authoring state only when playback stops rather than keeping it concurrently inspectable. Revert is intentionally destructive and cannot itself be undone. A structurally rewritten entity block uses canonical TOML formatting, and runtime-generated resources are not automatically promoted into project resource declarations.

### 18. Separate component definition from runtime ownership

**Decision:** Let the editor add or remove every registry component whose canonical lifecycle is authored, including engine-defined Transform, camera, light, render, and UI components. Keep storage kind and authored-versus-derived lifecycle in the component registry rather than a parallel editor taxonomy. Mutate only the selected component's typed storage and record only its exact before/after snapshot in stopped-mode history. Route stopped changes on scene entities through authoring history and persistence, while applying running or paused changes directly to scene and runtime entities as disposable playback state. Keep engine-managed derived components visible for inspection but omit them from membership actions.
**Why:** A component being defined by Scrapbot does not mean the engine owns its membership on a particular scene entity. Derived render and editor state, however, is reconciled by engine systems and cannot be meaningfully authored or removed by users.
**Tradeoff:** Registry metadata is now part of the component lifecycle contract and every new engine storage kind must provide snapshot, presence, add, and remove support. Stop discards live membership changes together with other playback mutations.

### 19. Reserve command-modified keys for editor commands

**Decision:** Route command-modified E, R, and T through the editor input path as shell toggle, Play/Stop, and Pause/Step commands. Toggling the shell changes only editor visibility and never changes running, paused, or stopped transport state. Ignore command-modified E and R in the unmodified transform-gizmo shortcut path, and gate transport commands while project text input or fly-camera capture owns the keyboard.
**Why:** Playback controls need fast platform-native shortcuts without stealing ordinary project input or accidentally changing the active transform tool. Editor visibility and simulation transport are independent decisions; users can explicitly Pause when they need a stable world.
**Tradeoff:** The shell toggle remains global by design, while transport shortcuts only work when the editor is visible and no higher-priority project or camera interaction owns input. A running project continues simulating behind the editor until explicitly paused or stopped.

### 20. Keep reflection metadata honest across public surfaces

**Decision:** Treat the canonical runtime payload as the field-shape authority for Odin-backed components and the live registry schema as the authority for dynamic project/native payloads. Public registry field metadata may refine semantic type and editor options only when every public surface supports that contract; it must not hide real runtime fields or invent editor-only ones.
**Why:** The inspector stays automatic without turning convenience metadata into a second payload definition or accidentally expanding generated project APIs.
**Tradeoff:** Fields present in an engine payload can appear read-only before every public authoring surface exposes them, while dynamic components remain limited to field shapes representable by their registry schema.

### 21. Make disposable playback visually persistent

**Decision:** Treat every non-stopped transport state as play mode, including Pause and Step. Keep both application bars on the shared neutral chrome recipe, then compose a persistent amber warning from the shared warning-text and warning-frame recipes: frame the viewport and state that changes are temporary. Stop removes that semantic emphasis when it returns to authoring mode.
**Why:** A selected Play or Pause button is too local to communicate that inspector, gizmo, component, and resource changes are disposable across the complete workspace. Pause must not look like authoring merely because simulation time is frozen.
**Tradeoff:** The warning is deliberately quieter than recoloring complete application bars, and the long status copy may clip on extremely narrow windows. It does not prevent playback edits; it communicates their lifecycle.

### 22. Author the UUID transform graph as an expandable scene tree

**Decision:** Following ADR-033, derive the browser tree from Transform parent UUIDs plus a stable internal scene-order key, compose each row from the public selectable-list, button, icon, text, and layout components, and keep collapsed UUIDs in transient editor state. Interpret `into` as a world-pose-preserving reparent to the target and `before`/`after` as a world-pose-preserving reparent to the target's parent plus adjacent ordering. Treat the combined parent-and-order mutation as one structural transaction and serialize scene blocks in the resulting order.
**Why:** Spatial hierarchy should be visible and editable without introducing an editor-only tree widget or a second hierarchy model.
**Tradeoff:** The reusable list gesture provides distinct insertion lines and into-row tint but no drag ghost. Insertion intentionally follows tree-editor convention: its destination level is the target's level, so a cross-level insertion also changes parent. Authored parent deletion is conservative until one transaction can safely encode parent deletion plus child detachment.

### 23. Publish frame diagnostics through a retained snapshot

**Decision:** Publish frame diagnostics through bounded, revision-driven state:

- Accumulate tick-to-tick intervals and active CPU durations in fixed storage over independent rolling 50-frame windows.
- Publish a revisioned snapshot every five frames and copy in the renderer's latest GPU timestamp, draw-batch, instance, and visibility counters.
- Use guaranteed FIFO presentation for window pacing without a second fixed sleep. Acquire the presentation surface before active-frame timing so expected vsync wait affects FPS but not `FRAME` duration or Systems attribution.
- Maintain scene, runtime, and editor entity counts at spawn/despawn boundaries instead of scanning world capacity.
- Render FPS, active CPU, GPU, effective render scale, project-entity, draw-batch, Hi-Z state, frustum-rejection, object-occlusion, and meshlet-occlusion values through an editor-origin collapsible panel composed only from public panel, table, scroll-area, VStack, layout, and text components. The table scrolls vertically when panel resizing leaves less height than its rows require.

**Why:** Basic performance health should be visible without leaving the editor, but observing the engine must not add an entity scan, rebuild UI every frame, or introduce private diagnostic widgets. A revision lets stable frames reuse the existing panel and paint stream.
**Tradeoff:** FPS reflects the rolling wall-clock presentation interval, including display pacing, while `FRAME` reports active CPU work and GPU frame time appears only when timestamp queries have produced a valid asynchronous sample. Engine phases are sequential attribution, but non-conflicting native project systems may overlap, so all displayed callback durations are not guaranteed to form an exact arithmetic sum. “Draw batches” is the retained GPU-driven grouping unit; it is intentionally not labeled “draw calls,” because one batch can participate in multiple render passes and UI/postprocess commands have different submission shapes.

### 24. Compose entity references from public searchable-list controls

**Decision:** Recognize canonical `Entity_UUID` payload fields through runtime type inspection and present them with an ordinary public button, popup layout, input, virtualized list, scroll area, and UUID selection. Build and validate candidate rows only when the popup opens. List scene-origin candidates plus a missing/current reference, provide an explicit `None`, and apply the chosen UUID through the same component snapshot and history path as another reflected edit.
**Why:** Entity references need names, search, identity disambiguation, compatibility checks, and cycle prevention that raw UUID text cannot provide. Reusing the public UI contract keeps filtering, virtualization, popup placement, selection, interaction revisions, and rendering out of editor-private mechanics.
**Tradeoff:** The authoring picker deliberately does not enumerate the potentially unbounded runtime population; a currently referenced runtime UUID remains visible for diagnosis and clearing. Dynamic project/native schemas cannot opt into entity-reference semantics until their field types can represent UUIDs.

### 25. Traverse reflected containers through bounded paths

**Decision:** Represent each nested struct field or array element as one step in a bounded runtime reflection path. Compose container rows from the existing public table, text, and icon-button controls, recurse only while expanded, and route supported leaves through the same typed control and component-snapshot transaction paths as top-level fields.
**Why:** Nested data should not require component-specific panel builders or a second editor-only widget system. Stable paths let pooled controls preserve identity and focus while whole-component validation, Undo/Redo, and persistence remain authoritative.
**Tradeoff:** Fixed arrays expose their existing elements but cannot resize. Dynamic project/native schemas still need an explicit recursive type and mutation contract before the editor can honestly offer add, remove, or reorder actions.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-014, ADR-016, ADR-017, ADR-018, ADR-019, ADR-021, ADR-023, ADR-024, ADR-025, ADR-026, ADR-027, ADR-028, ADR-031, ADR-033, ADR-040, ADR-044
- **FDRs:** FDR-001, FDR-003, FDR-007

## Open Questions

- Should Scrapbot eventually maintain concurrent authoring and playback worlds?
- Which panel layout and sizing state should persist per project?
- How should editor camera speed, bookmarks, and focus-selection navigation persist?
