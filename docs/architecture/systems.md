# Engine Systems

**Last verified:** 2026-07-24
**Canonical names:** `engine_system_profile_name` in `src/scrapbot/scrapbot.odin`  
**Execution boundaries:** `run_frame_system` in `src/scrapbot/render/render.odin` and WGPU frame encoding in `src/scrapbot/render/wgpu.odin`

These are the engine-owned rows published to the editor's Systems panel. They are profiled frame phases, not project-scheduler registrations: native Odin and Luau systems are appended dynamically after them and execute through the access-declared scheduler.

## Inventory

<!-- inventory:engine-systems:start -->
| System | Responsibility | Runs when | Primary implementation |
| --- | --- | --- | --- |
| `scrapbot.camera` | Updates the transient editor fly camera from captured scene-view input. | An editor UI state exists; visibility/input determine whether it mutates. | `ecs.editor_scene_camera_system` |
| `scrapbot.gizmo` | Reconciles camera visualization, transform gizmo interaction, and the editor-world overlay stream. | An editor UI state exists; most work is conditional on editor visibility and selection. | `render/render.odin`, `render/gizmo.odin`, `render/camera_visualizer.odin` |
| `scrapbot.ui` | Reconciles retained ECS UI, editor composition, layout, interaction, and paint revisions. | An editor/UI state exists; stable domains skip unchanged work. | `ui/ui.odin`, `ui/editor_*.odin` |
| `scrapbot.pick` | Resolves requested camera-mesh or exact scene-geometry picking and updates editor selection. | The phase is measured with editor state; intersection work runs only for a pending pick. | `render/picking.odin`, `render/camera_visualizer.odin` |
| `scrapbot.environment` | Reconciles the singleton authored world environment into retained resource handles plus imported-background and procedural-atmosphere presentation state. | Every rendered frame performs a cached revision check; UUID resolution and bounded atmosphere-value copies run only after membership or value changes. Resource reimports update the retained handles in place. | `resources.reconcile_world_environment` |
| `scrapbot.prepare` | Applies render extraction mutations and prepares retained GPU draw batches/uniform inputs. | Every rendered frame; changed work follows render/resource dirty signals. | `ecs.populate_resource_render_list`, `render/wgpu_gpu_driven.odin` |
| `scrapbot.render.cull` | Encodes GPU visibility, frustum/Hi-Z rejection, LOD selection, and indirect visibility compaction. | WGPU frames; CPU-reference mode substitutes CPU culling. | `render/wgpu_visibility.odin`, `render/wgpu_hiz.odin` |
| `scrapbot.render.shadow` | Encodes directional shadow rendering. | WGPU frames with applicable shadow state. | `wgpu_encode_shadow_pass` |
| `scrapbot.render.world` | Encodes depth and world geometry into HDR, surface-data, and indirect-diffuse targets and resolves visibility/timing work. | WGPU frames. | `render/wgpu.odin` |
| `scrapbot.render.post` | Encodes global height/distance fog with shadowed directional and clustered point-light scattering, thickness-aware visibility-bitmask ambient occlusion, depth-aware temporal resolution, material-aware screen-space reflections, HDR bloom, and compositing into the presentation target. | WGPU frames. | `render/wgpu_post.odin` |
| `scrapbot.render.ui` | Converts changed retained UI streams when needed and encodes project, editor, and overlay UI draws. | WGPU frames; unchanged streams reuse retained GPU buffers. | `render/wgpu.odin`, `render/wgpu_shader.odin` |
| `scrapbot.render.finish` | Finalizes the command encoder into a command buffer. | WGPU frames. | `wgpu.CommandEncoderFinish` boundary in `render/wgpu.odin` |
| `scrapbot.render.submit` | Submits the command buffer and advances asynchronous GPU diagnostics. | WGPU frames. | `wgpu.QueueSubmit` boundary in `render/wgpu.odin` |
| `scrapbot.render.present` | Presents the acquired surface texture. | Windowed WGPU frames; offscreen/headless paths have no surface presentation. | `wgpu.SurfacePresent` boundary in `render/wgpu.odin` |
<!-- inventory:engine-systems:end -->

## Per-system contracts

<!-- inventory:engine-system-details:start -->
### `scrapbot.camera`

- **Phase/order:** First engine-owned phase after scheduled project simulation.
- **Inputs:** SDL scene-view input, editor visibility/capture state, editor-camera Transform and movement settings.
- **Outputs:** Mutated transient editor-camera pose and input-capture state.
- **Stable-frame behavior:** With no captured movement/look input, it performs bounded camera/input checks and does not rebuild scene or render membership.
- **Boundary:** Main-thread CPU editor system; never replaces or mutates the authored project camera.
- **Source/tests:** `render/render.odin`, `ecs/editor.odin`; `ecs/editor_test.odin`, `render/render_test.odin`.

### `scrapbot.gizmo`

- **Phase/order:** After editor camera and before retained UI.
- **Inputs:** Editor selection, resolved world transforms, active editor camera, pointer state, gizmo mode/orientation, camera components.
- **Outputs:** Targeted Transform edits, camera visualization geometry, gizmo/overlay paint stream and interaction state.
- **Stable-frame behavior:** Reuses retained overlay/camera geometry until selection, camera, viewport, mode, or interaction revisions change.
- **Boundary:** Main-thread CPU editor tooling; visualization is an overlay consumer, not an authored renderable entity.
- **Source/tests:** `render/gizmo.odin`, `render/camera_visualizer.odin`, `ui/editor_ecs.odin`; `render/gizmo_test.odin`, `render/camera_visualizer_test.odin`.

### `scrapbot.ui`

- **Phase/order:** After gizmo/editor overlays and before scene picking/render preparation.
- **Inputs:** Public `scrapbot.ui_*` ECS components, structural dirty queues, project/editor revisions, pointer/keyboard input, editor bindings.
- **Outputs:** Retained hierarchy/layout/interaction state, renderer-owned `ui_state`, paint streams and independent output revisions.
- **Stable-frame behavior:** Unchanged domains reuse hierarchy, layout, paint commands, and GPU-facing streams; work follows structural, layout, paint, or interaction dirtiness.
- **Boundary:** Main-thread CPU retained UI system shared by project UI and editor composition.
- **Source/tests:** `ui/ui.odin`, `ui/editor_ecs.odin`, `ecs/ui_components.odin`; `ui/ui_retained_test.odin`, `ui/ui_test.odin`.

### `scrapbot.pick`

- **Phase/order:** After UI has resolved whether the scene view owns the pointer and before render preparation.
- **Inputs:** Pending editor pick request, scene-view coordinates, active editor camera, camera visualizer bounds, retained render geometry.
- **Outputs:** Editor selection UUID or cleared selection.
- **Stable-frame behavior:** With no pending pick, exact intersection and camera-visualizer tests are skipped.
- **Boundary:** Main-thread CPU query against retained scene inputs; it does not mutate project component data.
- **Source/tests:** `render/picking.odin`, `render/camera_visualizer.odin`, `render/render.odin`; `render/picking_test.odin`, `render/camera_visualizer_test.odin`.

### `scrapbot.environment`

- **Phase/order:** After project simulation and editor authoring, before render preparation consumes environment state.
- **Inputs:** World-environment structural revision, retained singleton entity index/component revision, and Environment resource registry.
- **Outputs:** Resolved lighting/background handles, intensity/rotation/exposure/background presentation values, and a monotonic renderer environment revision.
- **Stable-frame behavior:** Compares retained revisions only. It scans entities solely after structural membership changes and resolves UUIDs solely after component changes; resource reimports version the retained handles in place.
- **Boundary:** Main-thread backend-neutral ECS-to-resource-cache reconciliation; WGPU consumes the cache without scanning ECS.
- **Source/tests:** `resources/environments.odin`, `render/render.odin`; `resources/resources_test.odin`, WGPU framegrab smoke tests.

### `scrapbot.prepare`

- **Phase/order:** Bridge between CPU simulation/editor phases and backend render encoding.
- **Inputs:** Separate structural/static and Transform-only ECS dirtiness, retained render list, resource versions, active camera/lights, viewport/backend state.
- **Outputs:** Updated stable render slots, GPU instance/batch database changes, one dense transform-update stream, compact uniforms and frame draw state.
- **Stable-frame behavior:** Stable renderables retain slots and GPU records; Transform-only writes bypass resource and batch lookup, pack one dense 64-byte update per changed slot, and use one upload before dirty-only GPU expansion. Static/resource changes use the heavier retained-record path, while compact frame-valued inputs remain bounded.
- **Boundary:** Main-thread CPU and WGPU preparation boundary; backend-neutral ECS extraction stays separate from backend-owned caches.
- **Source/tests:** `ecs/world.odin`, `render/render.odin`, `render/wgpu_gpu_driven.odin`; `ecs/world_test.odin`, `render/render_test.odin`.

### `scrapbot.render.cull`

- **Phase/order:** First WGPU render-encoding phase after preparation.
- **Inputs:** GPU instance/draw database, camera frustum, previous valid Hi-Z state, LOD/visibility configuration.
- **Outputs:** Visible instance compaction, indirect draw arguments, explicit frustum accepted/rejected and occlusion-rejected counters, LOD counters, and next-pass state.
- **Stable-frame behavior:** Does not rebuild membership; it encodes bounded GPU work over retained draw capacity. Hi-Z samples a coarse mip covering the complete projected sphere footprint and skips unsafe camera-crossing or large near-field projections. CPU-reference mode is an explicit diagnostic substitute.
- **Boundary:** WGPU compute/encoding phase with CPU fallback for reference testing.
- **Source/tests:** `render/wgpu_visibility.odin`, `render/wgpu_hiz.odin`, `render/wgpu_gpu_driven.odin`; `render/render_test.odin`, `render/wgpu_math.odin` reference tests.

### `scrapbot.render.shadow`

- **Phase/order:** After visibility preparation and before depth/world shading.
- **Inputs:** Four stabilized directional-light views, per-cascade GPU/CPU-reference shadow-visible indirect draws, retained geometry/material pipeline state.
- **Outputs:** Four-layer directional shadow depth texture consumed by receivers through cascade selection and PCF.
- **Stable-frame behavior:** Reuses pipelines, buffers, and batch membership; only frame commands and explicitly dirty records are encoded/uploaded.
- **Boundary:** WGPU render-pass encoding; absent/inapplicable shadow state keeps the phase bounded or empty.
- **Source/tests:** `render/wgpu.odin`, `render/wgpu_shader.odin`, `render/wgpu_gpu_driven.odin`; `render/render_test.odin`.

### `scrapbot.render.world`

- **Phase/order:** After shadow encoding and before HDR postprocessing.
- **Inputs:** Visible indirect draws, camera/light uniforms, geometry/material caches, shadow/depth resources.
- **Outputs:** Depth, HDR world-color, compact surface-data, and indirect-diffuse targets plus timing/query state needed by later phases.
- **Stable-frame behavior:** Reuses retained draw databases, resource caches, pipelines, and unchanged instance buffers.
- **Boundary:** WGPU depth/world render-pass encoding.
- **Source/tests:** `render/wgpu.odin`, `render/wgpu_shader.odin`, `render/wgpu_gpu_driven.odin`; `render/render_test.odin`, WGPU smoke/framegrab tests.

### `scrapbot.render.post`

- **Phase/order:** After HDR world rendering and before UI compositing.
- **Inputs:** HDR world target, scene depth, octahedral view normal/roughness/metallic surface target, separately retained indirect diffuse light, optional singleton `scrapbot.volumetric_fog`, primary directional light and shadow cascades, GPU-built clustered point-light buffers, active-camera TAA/fast-AA/AO/SSR/bloom switches, current/previous camera projection state, retained temporal color/depth history, ambient-occlusion/reflection/bloom resources, and presentation format.
- **Outputs:** Composited scene color in the presentation target.
- **Stable-frame behavior:** Reuses postprocess pipelines, bind groups, full-resolution surface/reflection targets, and color/depth history at stable size. Resize, sampled-depth replacement, world replacement, a detected camera cut, or a TAA-mode change rejects history. Disabled AO, SSR, and bloom skip their compute passes; disabled TAA skips projection jitter and history copies.
- **Boundary:** WGPU compute/render encoding first integrates optional deterministic six-step height/distance fog with filtered primary-directional shadows and the complete relevant point-light list from each sampled GPU-built cluster. It then performs optional half-resolution visibility-bitmask ambient occlusion with rotated slices, constant-thickness depth samples, 32 angular sectors, joint depth/normal-aware blur and upsampling, and indirect-diffuse-only composition; optional bounded view-space SSR over material surface data; then either camera-reprojected temporal resolution, lightweight current-frame fast AA, or a direct resolve; followed by optional bloom, tone mapping, and composite. TAA takes precedence over fast AA. Culling remains unjittered, while UI is excluded and remains crisp.
- **Source/tests:** `render/wgpu_post.odin`, `render/wgpu_shader.odin`; WGPU smoke/framegrab tests.

### `scrapbot.render.ui`

- **Phase/order:** After world/postprocess composition and before encoder finalization.
- **Inputs:** Independently revisioned project, editor, and overlay paint streams plus font atlases and viewport clips.
- **Outputs:** UI draw commands over the presentation target and updated per-stream GPU vertex buffers when revisions changed.
- **Stable-frame behavior:** Each unchanged stream retains CPU vertices, GPU buffer, and upload revision; empty streams never issue draws requiring an absent vertex buffer.
- **Boundary:** CPU paint-to-vertex conversion only on changed streams, followed by WGPU UI pass encoding.
- **Source/tests:** `render/wgpu.odin`, `render/wgpu_shader.odin`, `ui/ui.odin`; `ui/ui_retained_test.odin`, WGPU UI framegrab tests.

### `scrapbot.render.finish`

- **Phase/order:** After all render/UI pass encoding and before queue submission.
- **Inputs:** Completed WGPU command encoder.
- **Outputs:** One finalized command buffer.
- **Stable-frame behavior:** Required bounded backend command finalization; it does not reconcile ECS or rebuild retained data.
- **Boundary:** WGPU `CommandEncoderFinish` API boundary.
- **Source/tests:** `render/wgpu.odin`; WGPU smoke tests.

### `scrapbot.render.submit`

- **Phase/order:** After encoder finalization and before presentation.
- **Inputs:** Final command buffer and queued resource writes.
- **Outputs:** Submitted GPU work plus advancement of asynchronous timing/error diagnostics.
- **Stable-frame behavior:** Required backend submission boundary; upload volume remains governed by exact dirty/revision checks in earlier phases.
- **Boundary:** WGPU `QueueSubmit` and device-poll boundary.
- **Source/tests:** `render/wgpu.odin`, `render/wgpu_timing.odin`; WGPU smoke/runtime-stat tests.

### `scrapbot.render.present`

- **Phase/order:** Final profiled engine phase for windowed frames.
- **Inputs:** Acquired surface texture containing composited world and UI output.
- **Outputs:** Presented OS-window image.
- **Stable-frame behavior:** Required window-system operation; no ECS reconciliation or retained-data mutation.
- **Boundary:** WGPU surface presentation; headless/offscreen frames record an empty placeholder.
- **Source/tests:** `render/wgpu.odin`, `platform/sdl3.odin`; windowed WGPU smoke tests.
<!-- inventory:engine-system-details:end -->

## Frame order

The windowed WGPU core loop configures and acquires its FIFO-paced presentation surface before the profiled and active-CPU frame. Display waiting contributes to the observed FPS interval but is excluded from the Performance panel's `FRAME` duration and from engine-system timings.

1. Begin the profiling sample and process editor transport/save/revert requests.
2. Advance project time and execute the cached schedule plan when playback permits it.
3. Run editor camera, gizmo/overlay, ECS UI, and requested picking.
4. Prepare backend-neutral render extraction and backend-owned draw state.
5. Encode culling, shadow, world, postprocess, and UI work.
6. Finish, submit, present when applicable, and commit the profiling sample.

The null backend executes the same project/editor frame boundary and render preparation needed for diagnostics, then records zero-duration placeholders for GPU-only phases.

## Project systems

- Native extension systems and Luau systems register dynamically; they do not belong in this fixed table.
- The scheduler caches an access-derived execution plan. Non-conflicting native systems may run in parallel; Luau systems execute serially as barriers.
- Structural commands are deferred until scheduled systems finish, then applied deterministically.
- The Systems panel publishes a rolling 50-frame average every five frames for engine, native, and Luau entries.

See [FDR-005](../fdr/FDR-005-system-scheduling.md), [ADR-009](../adr/ADR-009-parallelize-access-declared-native-systems.md), and [FDR-008](../fdr/FDR-008-editor-shell.md).
