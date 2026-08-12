---
title: Live Editor
description: Inspect, navigate, select, and transform entities while a Scrapbot project is running.
---

Scrapbot's editor is part of the running project rather than a separate executable. It inspects the same live ECS world, systems, and renderer launched by `scrapbot run`.

## Open the editor

Start a visible WGPU run and press `Cmd+E` on macOS or `Ctrl+E` elsewhere to toggle the editor:

```sh
bin/scrapbot run examples/ecs-showcase
```

Pass `--editor` to start with the editor already open:

```sh
bin/scrapbot run examples/ecs-showcase --editor
```

Opening the editor pauses an actively running project so the world does not keep changing while you orient yourself. An already paused or stopped project keeps its state. Closing the editor always starts or resumes normal playback, including when the project was paused or stopped.

The project world fills all available center space without enforcing a fixed aspect ratio. Project-authored UI keeps the same uniform canvas scale it uses outside the editor, then translates into and clips against the free-aspect viewport. Text and controls never stretch independently along X or Y.

The editor workspace is responsive:

- Drag either vertical separator beside the viewport to resize a sidebar.
- Press `Cmd/Ctrl+B` to hide or show Browse, and `Cmd/Ctrl+Alt+B` to hide or show Inspect.
- The center viewport fills the remaining space.
- Panes retain their proportions when the window changes.
- Native window resizing keeps the simulation, surface, camera aspect, viewport, and layout updating throughout the drag.

Each complete sidebar has a contrasting 10-pixel frame around its smooth scroll viewport and a small gutter between tool sections. Systems, Scene, Inspector, and component sections use the same titled card, colors, disclosure arrow, and collapse behavior. Click a title band to fold its section.

Browser filters are badge-free and share their outer edges with the selectable rows beneath them. Their entered text uses the same primary-content inset as ordinary browser rows.

Scrolling follows the pane under the pointer. A wheel event over Systems, the scene browser, or an inspector pane scrolls that pane. A wheel event over sidebar padding or non-scrollable chrome scrolls the complete sidebar.

The top bar contains the Scrapbot title and project simulation controls. The bottom bar reports simulation and persistence status. Running and paused playback display `PLAY MODE / <STATE> / CHANGES ARE TEMPORARY`. An amber badge inside the viewport states that scene edits are not saved, while an amber viewport frame and status text reinforce the warning without recoloring the complete editor. Pausing preserves the play-mode treatment because edits remain disposable. Stop returns the editor to neutral authoring chrome and removes the badge.

| Control | Behavior |
| --- | --- |
| Play | Run project systems with normal frame deltas. |
| Pause | Toggle between running and paused playback. While paused, rendering, editor UI, scene-camera navigation, picking, and gizmos remain responsive. |
| Stop | Restore the in-memory authoring state captured when playback began, discard playback mutations and runtime spawns, retain loaded Luau and Odin systems, and remain stopped. |
| Step | While pausing normal playback, run one fixed 1/60-second project update. |
| Undo / Redo | While stopped, traverse complete authoring transactions. The controls dim when no matching history step is available. |
| Save | While stopped, write dirty scene authoring and inline project-resource changes to their source files. |
| Revert | While stopped and dirty, discard unsaved authoring and reload project resources and scene entities from disk without reloading Luau, Odin, or systems. Revert clears authoring history. |

The transport also has command shortcuts while the editor is open:

| Shortcut | Behavior |
| --- | --- |
| `Cmd/Ctrl+E` | Toggle editor visibility. Opening pauses active playback; closing starts or resumes playback. |
| `Cmd/Ctrl+B` | Hide or show the left Browse sidebar. |
| `Cmd/Ctrl+Alt+B` | Hide or show the right Inspect sidebar. |
| `Cmd/Ctrl+R` | Play when stopped, resume when paused, and stop when running. |
| `Cmd/Ctrl+T` | Pause when running; advance one fixed step when paused or stopped. |
| `Cmd/Ctrl+D` | Duplicate the active entity and select the copy. The operation is authored while stopped and disposable during playback. |
| `Delete` / `Backspace` | Delete the active entity as an authored operation while stopped or a disposable operation during playback. |
| `Escape` | Clear the entity selection. A focused field or open popup consumes Escape first. |

Opening the shell pauses active playback without changing the current runtime world. Leaving it always enters running playback, so a paused project resumes and a stopped authoring world captures its in-memory playback baseline before project systems advance. Use the explicit Play, Pause, Stop, and Step controls or their shortcuts while editing.

Transport shortcuts are ignored while the scene camera captures the pointer or a project-owned input has focus. Command-modified E and R do not change the transform-gizmo mode.

Pause preserves the current runtime world so Play can resume it. Play and Step capture the current stopped authoring state in memory before simulation advances.

Stop returns to that captured state without reloading code or the scene file:

- unsaved authored entities, dirty state, selection, and undo history survive;
- playback mutations and runtime-spawned entities disappear.

Stopped is authoring mode. The bottom bar retains `/ UNSAVED` until Save—or `Ctrl/Cmd+S`—writes the changes, Undo/Redo returns to the clean history position, or Revert discards them.

Project resources participate in the same authoring state. The Resources panel composes the public filter input, virtualized selectable list, and scroll-area components with Create, Duplicate, Delete, and Reimport All controls. Type a case-insensitive name substring into its filter without changing resource selection or registry state.

Selecting a material opens an inline resource inspector:

- Name and Path rename or move the resource.
- Base color, HDR emissive, metallic, and roughness use ordinary numeric controls.
- Metallic and roughness are constrained to the authored `0`–`1` range.
- References reports consumers, and Find Usage selects the first live consumer.

Referenced resources cannot be deleted. Resource lifecycle operations are stopped-mode structural transactions, so Undo/Redo and Play/Stop preserve them in memory. Revert discards them.

Save addresses entities and resources by stable UUID. It prepares every dirty scene and resource output in memory, then validates the generated TOML and scene resource references.

File creation, replacement, moves, and deletion commit together as one recoverable project transaction. A failure before commit restores previous files and removes incomplete destinations. If a committed Save is interrupted, the next project load finishes cleanup. Resource names and paths can change without changing scene identity.

Save matches authored entities by stable UUID, not by name. Completed authoring transactions identify candidates, and constant-time UUID indexes compare each unique candidate with the parsed authored baseline.

Save preserves unrelated source text:

- Value-only edits patch semantic differences while retaining comments and surrounding formatting.
- Structural saves rewrite only their dirty entity blocks.
- Deleted UUIDs are omitted.
- Created or explicitly kept runtime UUIDs are appended in action order.

Scrapbot validates the complete generated scene before atomically replacing the source file. A successful Save marks the current history position as clean. Undoing away from that position reports unsaved changes; redoing back to it clears the warning.

Unpromoted runtime and editor-owned entities are never written. Changes made while running or paused remain disposable runtime state.

## Navigate the scene view

The editor creates an editor-owned scene-camera entity whose initial view matches the project camera. Moving it does not change the project's camera.

An editor-only infinite grid lies on the canonical XZ plane. Close views show one-unit cells regardless of the current snapping increment. The complete plane uses one resolution chosen from the camera's height above it. As the camera moves away, minor lines smoothly fade into every tenth major line before the grid advances through 10-unit, 100-unit, and 1,000-unit levels. Red X and blue Z axes preserve world orientation, while a planar-distance fade bounds the apparent infinite field. Scene depth lets opaque geometry cover the grid. It never creates an entity or enters scene persistence.

Use the `VIEW / CAMERA` menu inside the Game surface to inspect the rendered inputs:

- Lit shows the ordinary HDR result.
- Base Color, World Normals, Roughness, and Metallic isolate material inputs.
- Depth maps the camera's near-to-far range logarithmically from white to black.
- Meshlets colors the actual retained clusters submitted by capable adapters.
- LOD colors the exact GPU-selected geometry level: green for 0, blue for 1, purple for 2, and orange for 3.
- Meshlet Visibility colors submitted meshlets green and overlays rejected bounds from the GPU culler. Red and purple identify object-level frustum and Hi-Z rejection; orange, cyan, and magenta identify meshlet-level frustum, cone, and Hi-Z rejection.
- Hi-Z displays the retained max-depth pyramid in false color. Use the adjacent minus and plus controls to inspect each mip; visible cell boundaries show the exact coarse regions sampled by conservative occlusion queries.
- Occlusion Queries dims the world and overlays the exact projected rectangle tested for each object or meshlet. Mint survived; pink was rejected. Use **Freeze** to retain one valid evidence set while you inspect it; ordinary culling and simulation continue.
- Virtual Geometry colors the retained hierarchy frontier and residency state used for submission.
- Distance Field shows a middle voxel slice from the first submitted imported Geometry field. The renderer range-loads and uploads that field on demand; cyan represents unsigned surface distance, while signed fields distinguish inside and outside.

`Camera` follows the project camera's authored debug fields. Choosing another item, mip, or freeze state is a transient editor override: it changes neither the project camera nor authoring history. Non-lit views bypass temporal jitter and presentation effects so the displayed values remain stable and direct. Meshlets, Meshlet Visibility, and Occlusion Queries show a red/slate checker when the current adapter or `--cpu-culling` run uses whole-primitive submission.

| Input | Action |
| --- | --- |
| Hold right mouse button | Capture scene-camera input |
| Mouse | Look around while captured |
| `W` / `S` | Move forward / backward |
| `A` / `D` | Move left / right |
| `Space` | Move up |
| `Ctrl` | Move down |
| `Shift` | Move 4× faster while held |
| Hold middle mouse button and drag | Orbit around the current point of interest |
| Mouse wheel over Game | Dolly forward or backward |
| `F` | Frame all selected entities and make their shared center the orbit target |
| Release the active right or middle mouse button | Return to normal pointer interaction |

The point of interest follows ordinary fly translation and the center of free-look. Framing a
selection replaces it with the selected renderables' combined bounds, so subsequent middle-mouse
movement orbits their shared center without changing any Transform.

The transient fly camera inherits the project camera's field of view, far plane, and render policy,
but uses a near plane no larger than one centimeter. This keeps close surface inspection coherent;
the fly camera does not currently collide with project geometry, so crossing inside a closed mesh
still reveals its back-face-culled interior.

Wheel dolly applies only when unobstructed Game viewport content owns the pointer. Sidebar scrolling,
menus, and other editor chrome keep their ordinary wheel behavior. `F` preserves the current viewing
direction and frames every selected entity's complete rendered subtree, including generated children
of Model roots. Entities without renderable geometry contribute their resolved world Transforms.

Closing and reopening the editor preserves the scene-camera viewpoint for the current run.

While the editor is open, project and runtime cameras appear as blue, world-scaled wireframe bodies. A body naturally becomes smaller on screen as the scene viewpoint moves away. Cameras also receive a blue, fixed-size billboard icon at their world origin. The editor fly camera is excluded.

Directional lights receive a gold sun icon and point lights receive an orange bulb icon. A directional light without a Transform anchors its position-independent icon at the world origin. Selecting any icon changes it to the shared amber selection color. Overlapping icons remain at their exact projected positions and may cover one another.

Selecting a point light displays three range rings. Drag the amber radial handle to edit its positive `range`. Selecting a directional light displays an arrow; drag its endpoint over the spherical direction map to edit the normalized `direction`. Both handles capture the initiating click and continue tracking across sidebars, toolbars, and other editor chrome until release. Release commits one Undo/Redo gesture while stopped, and Escape restores the value from before the drag. Running and paused edits remain disposable playback changes like other inspector and gizmo edits.

Selecting a camera highlights it in amber and reveals a projection-frustum preview derived from:

- its field of view;
- its near clip plane;
- the current viewport aspect;
- its resolved world transform.

The preview stops after five world units, or at a shorter far clip plane, so an ordinary long far plane cannot flood the scene view. Click a camera/light icon, visible camera body, or selected frustum stroke to select its entity; these editor visualizers take priority over triangle picking.

These visualizers are editor-only. They do not create renderable project geometry or persist to the scene. The separate fly camera is never shown as project content, and closing the editor removes them. Component icons, camera visualizers, and transform gizmos stay inside the Game surface: they paint above project UI, while any editor tab or panel moved over that surface covers them.

## Browse and inspect entities

The top-left Systems panel lists every system participating in the frame. Type in its filter to match system row content case-insensitively; the public virtualized list lays out only visible matches plus bounded overscan. Engine rows cover the editor camera, transform gizmo, ECS UI, picking, render preparation, and granular render phases. Registered project-Odin and Luau systems follow them. Selecting a system retains the selection for future debugger details but currently takes no action.

Each row shows:

- a right-aligned rolling average in milliseconds with three decimal places;
- a thin, trackless contribution bar that grows leftward, where 10 ms fills the row;
- a provenance dot: mint for Engine, blue for Project Odin, or amber for Luau.

Timings publish every five successful frames from the latest 50 successful frames. Render rows report CPU callback and API time, not asynchronous GPU execution. Engine systems use `scrapbot.*` names, project-Odin systems use their registered names, and Luau systems use the optional `name` from their system options with an ordinal fallback.

Drag the horizontal separator below Systems to trade height with the complete Scene pane.

Project-system values measure callback execution and exclude scheduler setup and deferred-command application. Engine rows measure their named CPU frame phases. `scrapbot.render.cull`, `.shadow`, `.world`, `.post`, `.ui`, `.finish`, `.submit`, and `.present` expose where CPU-side renderer time is spent; none measures asynchronous GPU execution. Values above 10 ms clamp to a full-width bar.

The Scene panel contains a flush, selectable, scrollable hierarchy and a compact stopped-mode authoring toolbar. It uses the public tree-enabled `ui_list`, not an editor-only tree implementation.

Pooled direct rows store semantic parent, sibling order, and collapse state on `ui_layout`. The shared UI system owns flattening, indentation, collapsed-branch filtering, and subtree placement. Transform parent UUIDs give the tree its scene meaning, and SDF chevrons expand or collapse branches.

Drag and drop supports three targets:

- Drop on the middle of a row to make it the new parent.
- Drop on a row's top or bottom edge to adopt that row's parent and insert before or after it.
- Drop in empty Scene-list space to make the entity a root.

The reusable gesture paints an insertion line or tints the reparent target. Parent and order changes are atomic, preserve world pose, and reject cycles. A transformless source receives an identity Transform; a transformless parent contributes an identity spatial basis.

While stopped, scene entities may use only scene parents, and one completed drag is one undoable, saveable structural transaction. Save emits TOML blocks in authored order without moving live ECS storage handles. During playback, hierarchy and order edits are disposable. An authored parent with children must currently be emptied before deletion.

The compact icon toolbar creates a scene entity with a Transform, duplicates the active scene or runtime entity, removes the active entity, or explicitly pins an active runtime entity into scene data. Create and pin are available while stopped. Duplicate and Delete create undoable authored changes while stopped; while Running or Paused, they instead mutate disposable runtime state and Stop removes or restores those changes with the playback baseline. `Cmd/Ctrl+D` uses the same duplicate action and selects the copy; unmodified Delete or Backspace uses the same delete action. Entity shortcuts are ignored while a text input owns focus. The hierarchy shows scene-authored entities by default, so high-churn runtime spawns do not create thousands of editor rows. A runtime entity selected through the viewport or another tool is surfaced in muted gray and remains fully inspectable. Transient editor-origin entities—including the shell itself and scene camera—stay hidden from the browser and inspector.

The shell is built from transient ECS entities using the same public components as project UI: responsive layouts, stacks, draggable separators, dock spaces and items, scroll areas, lists, progress bars, panels, tables, text, buttons, inputs, and checkboxes. Editor origin keeps those tool entities out of project data while making the editor exercise the ordinary UI system.

Browse, Game, and Inspect are public dock items, each containing a reorderable VStack. Game keeps its viewport fixed as the first stack item while still accepting tool panels. Performance, Systems, Scene, and Resources begin inside Browse; Inspect gives stable order to its identity and runtime-reflected component panels.

The Performance metrics table scrolls vertically when its panel is resized below the complete row set.

Workspace dragging follows the same reusable rules everywhere:

- Drop over tab content or its header to insert into that tab's stack, including an inactive tab.
- Drop over empty dock-space chrome to create a separate tab.
- Drop on an enabled Game-space edge to create a public resizable left/right or above/below split.
- Drag a docked tab back into any tab stack.
- Release over no destination after crossing the drag threshold to cancel without collapsing the panel.

Directional targets take priority over nested tab stacks at an enabled edge; center drops retain normal stack and tab routing. For example, move Scene to the Game space's right edge to create a Game/Scene workspace.

Sidebar and inspector sizing uses public per-axis fill, minimum-size, ordering, and fit-to-content policies. See [ECS UI](/guides/ecs-ui/) for the project-facing component model.

Click an entry or rendered geometry to replace the selection. Shift-click an entity in either surface to toggle its membership; the most recently added entity becomes active for the inspector and local gizmo orientation. Shift-clicking empty viewport space preserves the set, while a plain empty-space click clears it. Viewport picking rejects meshes and streamed-geometry regions outside the pointer ray, then tests the surviving rendered triangles and selects the nearest hit. The browser scrolls to reveal the active viewport-picked entity and removes despawned entities from the set.

The inspector reports the active entity's editable name, identity, provenance, attached components, fields, and current values. With several entities selected, its header reports the count and active entity; field edits currently target only that active entity.

Component cards are runtime-generated:

- Scrapbot enumerates live registry membership.
- It inspects each canonical runtime payload.
- Project/native dynamic components use their registered schema as runtime type metadata.
- Each discovered field becomes a label/value row.
- Marker components naturally produce title-only cards.

Fields use an edge-to-edge, two-column property table. Labels initially receive one third of the width and values receive two thirds; drag the boundary to resize it. Cell-level spacing keeps controls inset without shrinking the table.

Click a title or its SDF disclosure arrow to collapse a component. Advanced and engine-derived components remain inspectable but start collapsed, and their disclosure state is retained while inspecting that component. Click the trailing cross to remove an authorable component.

An authored Material panel shows its resource name and UUID, editable base color, HDR emissive, metallic, and roughness values, and a stopped-mode selector populated from known material resources. Material numbers use the same typing, stepping, and whole-control scrubbing as every numeric input. While running or paused they preview immediately as disposable runtime changes; Stop restores the captured authoring resource values. While stopped they become undoable authoring transactions. Resource-reference switching remains stopped-mode authoring. Resource data stays registry-owned outside ECS; the selector and controls themselves use the public ECS UI system.

Texture, Environment, and Model resources expose their source dependency, product kind and size, warnings, errors, and status.

Their previews use the public `scrapbot.ui_viewport` component and adaptive pooled targets:

- Texture renders the complete imported image with aspect-preserving fit.
- Model renders imported geometry and materials.
- Material renders an isolated lit icosphere.
- Environment reports its derived irradiance/specular cube shape and lights Model and Material previews when selected.

Drag a 3D preview to orbit, use the wheel to zoom, and click **Reset** to restore its view. Stable previews are revision-cached.

While stopped, select a Model resource and click **Add to Scene** to create a persistent model root under the center of the Game viewport. Scrapbot places it on the nearest rendered surface, centers its transformed bounds around the contact in the surface plane, and offsets its root so the bounds rest on that contact. When the ray misses geometry, placement falls back to the world ground plane and then to a five-unit camera focus point. The new entity uses the Model's name, inherits the project's geometry policy, becomes the active selection, and participates in Undo, Redo, Save, and Revert. Add Shadow Caster or Shadow Receiver explicitly when the object needs them.

You can also drag a Model row onto an exact point in the Game viewport. A translucent amber ghost shows the complete Model at its proposed world transform while a contact reticle follows the resolved surface; a tether shows any offset between that contact and the Model root. The release uses the same previewed position. Dragging onto empty Scene space uses the viewport center; dropping on an existing Scene row additionally parents the new model there while preserving its world placement. These gestures use the public `ui_action` drag/drop contract; the editor only interprets the resource and scene meaning.

The **Snap** overlay cycles through off, 0.25, 0.5, and 1-unit translation increments. The same setting quantizes Model-placement contacts and transform gestures. It does not rotate the Model's imported orientation to the surface normal.

Selecting an entity with rendered geometry adds an amber silhouette outline. Selecting a Model root outlines the combined projected silhouette of all generated mesh primitives owned by that root. During Running and Paused play mode, the outline becomes animated dashes to signal that live scene changes are temporary; run-global engine time keeps the animation active while ECS project clocks are paused. Stopped authoring mode keeps the steady solid outline. Closing the editor hides the outline but preserves the selection for when you reopen it. The outline intentionally appears through occluding geometry so selection remains identifiable in dense scenes, but it does not fill or recolor the selected surface. This is transient editor feedback: it does not modify materials, components, or saved project data.

Click **Reimport** to force only the selected importer, update its live registry entry, and reconcile model instances when necessary. This does not restart Luau, native Odin, or the scene world. **Reimport All** forces every imported declaration. Failed imports retain the prior atomic product and surface the error in the inspector.

Discovered Bool, String, Number, Vec2, Vec3, Vec4, Color, and entity-UUID values select reusable public controls. Vector rows provide one input per axis, scalar and string rows use one full-width input, and Color fields use the public linear-RGBA picker with bounded or HDR behavior from their semantics.

Runtime-reflected Odin enums use a choice button targeting a public popup-layout root with ordinary list and scroll-area content generated from the enum's live option names. Unknown enum backing values remain visible and read-only.

Entity UUIDs use a searchable popup composed from the same public button, input, virtualized list, and scroll-area components. `None` clears the reference. Candidate rows show entity names and UUID prefixes, omit incompatible targets and hierarchy cycles, and retain a missing current UUID so it can be diagnosed and repaired. The picker enumerates scene candidates only when opened; it does no candidate work on stable closed frames.

Nested records and fixed arrays appear as expandable rows showing their field or item count. Their children recurse through the same runtime type inspection and reuse the ordinary leaf controls, so writable nested leaves keep validation and component-scoped Undo/Redo while engine-derived values stay read-only. Collapsed containers do not materialize descendant controls. Resizable dynamic-array schemas and add/remove/reorder actions are not supported yet.

Shared UI owns popup anchoring, viewport clamping, filtering, scrolling, outside/Escape dismissal, and close-on-selection. Choosing an enum, color, or entity value commits the same component-scoped transaction as another reflected edit. Engine-derived state and unsupported or opaque values remain read-only until they gain an honest public editing contract. A complete stopped-mode reflected edit records only that component's before/after snapshot as one authoring transaction, so Undo, Redo, Save, and Revert work without field-specific editor history code.

Click **Add Component** to open a floating, independently scrollable picker. Type in its public filter input to match generated group or component names case-insensitively. Its entries come from the live component registry:

- single-token project components appear under **Project**;
- dotted engine and library names are nested by namespace token;
- components already attached to the entity are omitted.

Remove an authorable component with the cross in its panel title. While stopped, scene-entity membership changes are undoable authoring transactions. While running or paused, membership changes apply immediately for experimentation, stay outside Undo and Save, and disappear on Stop.

Engine-defined components such as Transform, Camera, lights, render data, and UI remain mutable because the entity owns their membership. Engine-managed derived state such as Render Instance and editor gizmo ownership remains visible but intentionally has no removal action.

Click outside the menu, press Escape, or choose a component to close it.

Click a value to focus it and select its complete contents. Typed text replaces the selection. Left/Right/Home/End move the cursor, Shift extends the selection, and Backspace/Delete edit it. Numeric typing and keyboard stepping remain staged without changing the component until Enter commits and leaves the field. Escape, clicking elsewhere, or using Tab/Shift+Tab restores the value captured when focus began; Tab still moves through fields in visual order, including independent X/Y/Z/W controls. Pointer scrubbing remains a live preview and commits once on release.

Numeric typing and keyboard stepping stay local to the focused control until Enter commits a valid value. Invalid numbers receive a red border and never reach the active world.

Keyboard stepping uses the field's configured step:

- Up/Down uses the normal step.
- Shift+Up/Down uses a 10× step.
- Ctrl/Cmd+Up/Down uses a 0.1× step.

Built-in editor numbers and custom fields marked `draggable` can be scrubbed horizontally across the complete control. Scrubbing previews live and commits once on release.

Use the top-bar controls or `Ctrl/Cmd+Z` and `Ctrl/Cmd+Shift+Z` for Undo and Redo. Complete typing, stepping, scrubbing, boolean changes, gizmo drags, renames, entity operations, promotions, and component membership changes each occupy one bounded history entry. Dependent boolean fields changed by one control remain atomic.

While stopped, authored changes can be saved. Edits to unpromoted runtime entities and all edits made while running or paused are session-only and do not enter authoring history.

Resource-browser values and the selected entity's running component values refresh every 200 ms. Selection and stopped-authoring changes refresh immediately. Periodic refresh leaves actively edited text alone and does not rebuild the Scene browser; hierarchy invalidation, filter edits, and selection changes do.

Type in the Scene filter to match entity labels case-insensitively. Matching descendants retain their hierarchy context and appear beneath collapsed ancestors without changing saved collapse state.

Scene and Resources use the public virtualized-list contract, so scrolling visits only visible rows plus a small overscan window. Their filters, scroll targets, and Inspector scroll remain independent. Each supports frame-time smoothing without line snapping, clipped partial content, proportional scrollbars, and fractional trackpad deltas.

## Transform an entity

Selecting an entity with a Transform adds a screen-legible transform gizmo. Pointer drags remain available on its visible handles. Blender-style keys immediately start a modal transform; an optional axis key can constrain it afterward:

| Chord | Result |
| --- | --- |
| `G` | Translate freely in the camera plane |
| `G`, then `X`, `Y`, or `Z` | Translate on that axis |
| `G`, then `Shift+X`, `Shift+Y`, or `Shift+Z` | Translate on the plane excluding that axis |
| `R` | Rotate around the current view axis |
| `R`, then `X`, `Y`, or `Z` (with optional Shift) | Rotate in the complementary plane, around that axis |
| `S` | Scale all axes uniformly |
| `S`, then `X`, `Y`, or `Z` | Scale on that axis |
| `S`, then `Shift+X`, `Shift+Y`, or `Shift+Z` | Scale on the plane excluding that axis |

Move the pointer as soon as you press `G`, `R`, or `S`. Pressing an axis key during the gesture re-evaluates the complete transform from its starting value under that constraint, like Blender's modal transform map. The cursor remains visible, stays confined to the editor window, and wraps to the opposite edge when it reaches a boundary, so a long transform can continue without running out of pointer travel. Click or press Enter to commit; Escape restores the transform from before the chord. An uppercase axis means the Shift-modified excluded-plane form, not a different coordinate system. Axis constraints use the current World or Local orientation.

The viewport's **Snap** control applies to pointer handles and modal chords. Translation uses the displayed world-unit increment along the gesture's frozen axes, rotation uses 15-degree increments, and scale uses 0.1-factor increments around the starting size. `SNAP OFF` disables all three. Hold `Cmd/Ctrl` during a gesture to temporarily invert the setting: it disables configured snapping, or enables the default 0.5-unit, 15-degree, and 0.1-factor increments while snapping is off.

The axis colors remain consistent in every mode:

- Red moves along X.
- Green moves along Y.
- Blue moves along Z.

Hover an axis to affect one component, or hover an XY, XZ, or YZ wall to affect that pair. Translation follows the 3D ray under the pointer: an axis handle finds the closest point on its world/local axis, a plane wall intersects its world/local plane, and the center handle intersects the camera-facing plane through the entity's starting position. The result stays spatially attached to what the pointer indicates at the entity's depth instead of scaling raw screen motion into world units. It does not snap to arbitrary scene surfaces. Pair scaling applies one linked multiplier to both included axes, preserving their relative proportions while leaving the excluded axis unchanged. In scale mode, the center handle changes all three scale components uniformly.

After a pointer handle starts dragging, it keeps ownership across the complete editor window instead of stopping at the Game boundary. Transform drags remain confined to the window and wrap at its outer edges, with their captured anchors adjusted so the edit stays continuous. Gizmo ownership and mode are represented by a transient editor component on the active entity; the component is removed when selection changes or the editor closes. Transform chords are ignored while the scene camera is capturing fly or orbit input, or a text field owns keyboard focus.

Use `WORLD` or `LOCAL` in the viewport's upper-left corner to choose gizmo orientation. World keeps the rails, walls, and rings aligned to scene axes. Local rotates them with the active entity's resolved world orientation: movement follows its rotated axes, rotation composes around those axes, and scale continues to edit the corresponding local X, Y, or Z scale.

Use `ORIGIN` or `CENTER` beside them to choose the manipulation pivot. Origin uses the entity's resolved Transform position—the canonical point inherited by children. Center uses the combined rendered-bounds center of the entity, its Transform descendants, and generated Model children, falling back to Origin for a transform-only entity. Center translation preserves the origin offset; Center rotation and scale move the origin around the center. This is transient editor policy: it does not add a serialized pivot or alter an imported asset origin.

The selected space and pivot are stored on the transient gizmo component. A drag freezes its basis and pivot when it begins, so the handle stays stable even while the transform changes. For a parented entity, the gizmo edits its world pose and derives the new local Transform automatically.

While stopped, transform edits to scene-authored entities participate in explicit Save. During running or paused playback they affect only runtime state. A complete single- or multi-entity gizmo drag is one undoable transaction, including multi-axis handles, snapping, shared-pivot movement, and parent/child selections. Editing asset origins, custom pivots, and arbitrary surface snapping are not implemented yet.

## Capture the editor

For deterministic documentation or renderer checks, combine the editor with a headless framegrab:

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend wgpu \
  --editor \
  --headless \
  --frames 20 \
  --framegrab /tmp/scrapbot-editor.png
```

Headless runs normally have no platform pointer. Add a semantic `--ui-script` and `--ui-dump` to reproduce editor clicks, scrolling, typing, hover, focus, and assertions without OS automation; a `capture` action can crop the final 1:1 PNG to its resolved target. See [Rendering And Testing](/guides/rendering-testing/#semantic-ui-diagnostics).
