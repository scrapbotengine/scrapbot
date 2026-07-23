# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-07-23

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend renders full indexed geometry with shared metallic-roughness GGX materials, mipmapped base-color/normal/occlusion/emissive images, a perspective camera, ambient/directional/point lighting, and optional scene-authored image-based environment lighting.
- The first directional light produces four stabilized, camera-relative 2048×2048 shadow cascades. Only entities with `ShadowCaster` contribute depth, and only entities with `ShadowReceiver` sample the cascades through 3×3 PCF.
- Lights are extracted into a bounded backend-neutral frame packet: accumulated ambient light, four directional lights, and 256 point lights. WGPU stores point lights in a storage buffer and deterministically builds a 16×9×24 clustered-light grid on the GPU. Every cluster can reference the complete packet, preventing dense moving lights from popping at an internal overflow boundary. Above the procedural horizon, World Environment contributes the first derived directional-light slot without creating an authored entity; explicit ECS lights fill the remaining directional slots.
- Base-color and emissive images use sRGB sampling while metallic-roughness, normal, occlusion, and imported environment products remain linear. Diffuse irradiance and roughness-prefiltered specular reflection join direct GGX lighting and emission in a floating-point HDR target. `scrapbot.world_environment` selects lighting and an independent imported or procedural visible sky. The procedural atmosphere exposes sky/ground color, turbidity, thickness, horizon, and an HDR sun direction, color, intensity, disc, and glow. Sun elevation planet-occludes the disc and drives a day/twilight/night transition plus hemispherical procedural fill. Above the horizon, the sun is the first derived directional render light and therefore drives ordinary GGX lighting and the primary shadow map; explicit ECS lights remain additive. World-environment exposure multiplied by active-camera exposure scales the complete HDR world before bright energy feeds a five-level bloom chain and the world is tone mapped once into an sRGB target.
- Project UI, transform gizmos, editor-only project-camera bodies and projection frusta, and editor chrome render after world postprocessing and do not bloom.
- Eligible entities receive internal render-instance components automatically.
- Shared geometry/material pairs use one instanced draw batch, and geometry and material texture uploads are cached by handle and version.
- WGPU keeps a persistent slot-addressed GPU instance table, separates static source state from hot Transform state, sends Transform-only changes through one dense update upload, coalesces nearby static slot changes into bounded uploads, retains compact render/culling uniforms and instance-to-LOD batch mappings, computes camera and shadow frustum visibility into compacted batch slices, and obtains instance counts from indexed indirect draw arguments.
- The retained draw database grows geometrically past the original 64-batch limit. It rebuilds only when render membership, geometry LOD topology, or required capacity changes.
- Large stable scenes run a depth prepass, build a max-depth Hi-Z pyramid, and conservatively reject occluded bounding spheres from the following frame. Camera or persistent-instance changes disable stale-pyramid rejection for that frame.
- UUID-backed `scrapbot.geometry_lod` project resources declare generated icosphere levels and descending projected screen-radius thresholds. The GPU visibility pass selects the geometry batch; the CPU-reference path implements the same result.
- `--cpu-culling` runs the same conservative camera/shadow visibility contract on the CPU and uploads its compacted lists and counts; it is a compatibility and correctness-reference path, not the performance default.
- Structured run results include renderer counters for GPU-driven mode, draw/instance/visibility capacity, database rebuilds, occupied slot span, cumulative instance upload calls and bytes, frustum/occlusion counts, per-LOD visible counts, and optional per-pass GPU milliseconds. Visibility and timing use asynchronous readback rings and never synchronously stall the frame.
- The `wgpu` backend can also render a losslessly compressed headless final-frame PNG with `--framegrab`.
- `--framegrab-region x,y,width,height` exports a top-left-origin 1:1 pixel crop without resampling; omitting it preserves the complete 1280×720 frame.
- WGPU sizes the live world and project UI to the complete available viewport, deriving camera aspect from its dimensions, then paints engine chrome in a separate overlay pass.
- Visible WGPU windows continue stepping and presenting frames during native live resize, reconfiguring the surface to each exposed pixel size instead of waiting for the drag to end.
- Visible windows use the project's logical startup size and request a high-pixel-density drawable independently. Headless WGPU keeps its deterministic 1280×720 offscreen target.
- The `wgpu` backend currently requires a visible window or a framegrab target. Source-project runs provide the window by default.
- Renderer runs can be limited with `--frames`; windowed `0` means run until the window closes, while headless `0` captures one frame.
- Users can request a short-lived SDL3 window with the null backend for platform smoke checks.
- Future backends should not require scene files or gameplay code to know backend-specific GPU handles.

## Design Decisions

### 1. Start with a null renderer

**Decision:** The initial runtime submits a frame summary to a null renderer.
**Why:** This proves project loading, ECS world construction, and runtime flow before introducing GPU setup. See ADR-003.
**Tradeoff:** It does not verify graphics output yet.

### 2. Make wgpu-native the first real backend

**Decision:** Implement the first headful renderer with `wgpu-native`.
**Why:** It matches the desired WebGPU direction, supports modern native graphics backends, and is available through Odin's vendor bindings. See ADR-003.
**Tradeoff:** WebGPU concepts and validation rules shape the renderer abstraction early.

### 3. Use SDL3 for the first window path

**Decision:** Open platform windows through SDL3.
**Why:** SDL3 is available through Odin's vendor bindings and gives the renderer a portable surface path. See ADR-005.
**Tradeoff:** Headful runtime work now depends on SDL3 being available in development and distribution environments. Native live resize requires a narrowly scoped SDL exposed-event watcher because the ordinary event-poll loop can be suspended by the platform resize interaction.

### 4. Render full indexed geometry

**Decision:** WGPU consumes position/normal/UV vertices with `u32` triangle indices and shared materials. Materials may provide scalar metallic-roughness factors and base-color, metallic-roughness, normal, occlusion, and emissive images; cube and plane helpers generate the same geometry representation.
**Why:** Procedural, custom, and future imported geometry should follow one rendering path.
**Tradeoff:** Normal mapping reconstructs a tangent frame from fragment derivatives instead of storing imported tangents. Local reflection probes, transparency, and advanced material extensions remain follow-up work.

### 5. Keep headless framegrabs on the same render path

**Decision:** Headless WGPU renders the same ECS cube pipeline into an offscreen texture, reads the final frame back to CPU memory, and writes a losslessly compressed full-frame PNG or explicit 1:1 pixel crop.
**Why:** This gives agents and tests a visual artifact that exercises the same scene-driven renderer path as the windowed backend while allowing focused inspection without shipping unrelated pixels through an agent conversation.
**Tradeoff:** On macOS, the current implementation creates a hidden SDL3 window for Metal adapter bootstrap even though the captured frame is rendered offscreen.

### 6. Use ECS renderable queries as the first backend boundary

**Decision:** Change-driven engine synchronization derives internal render-instance components from valid transform, geometry, and material references and maintains dense active sets for renderables, cameras, and each light kind. ECS retains the render list and updates it from a separate extraction-dirty queue, while WGPU retains draw grouping and grows existing batch membership incrementally.
**Why:** Backends need coherent scene instances, not just global component counts, and this keeps GPU code out of ECS storage without rescanning unchanged membership across the complete world every frame. See ADR-024.
**Tradeoff:** Every render-relevant value or structural mutation must mark its exact entity dirty, active sets and retained render-list maps must repair indices after swap removal, and new batch keys or capacity growth can still rebuild backend batch slices.

### 7. Share geometry and material resources by handle

**Decision:** Keep full geometry and material descriptions outside entity storage and let ECS components reference them with generational handles, as established by ADR-010. Primitive helpers produce ordinary indexed geometry rather than backend-specific primitive markers.
**Why:** Many entities should share one CPU description and one backend GPU allocation without putting GPU ownership into the ECS.
**Tradeoff:** Rendering needs an explicit reconciliation step, resource validation, and backend cache invalidation when named geometry is replaced.

The built-in indexed primitive generators cover cubes, planes, icospheres, UV spheres, square pyramids, and capped cylinders. Curved primitives expose bounded tessellation controls so projects can choose an appropriate geometry cost.

### 8. Extract ECS lights into a bounded frame packet

**Decision:** Ambient, directional, and point lights are public ECS components. ECS extraction iterates compact active sets, accumulates ambient light, and copies up to four directional and 256 point lights into each render list. WGPU builds deterministic per-cluster point-light lists entirely on the GPU. See ADR-011 and ADR-039.
**Why:** Lights remain scriptable scene state without exposing ECS storage to renderer backends, while fragment work scales with locally relevant lights instead of the complete packet.
**Tradeoff:** WGPU reserves about 3.4 MiB for cluster indices. It ignores lights beyond the 256-light frame packet, and a pathological cluster may evaluate all 256 packet lights.

### 9. Accumulate lighting in linear space and tone map the result

**Decision:** Treat authored material colors as sRGB, decode them before lighting, apply an ACES-style curve to the HDR result, and prefer sRGB render targets for presentation and framegrabs.
**Why:** Directly adding strong light contributions to display-space colors clips channels independently, washes out saturated lights, and produces inconsistent output across UNORM and sRGB targets.
**Tradeoff:** Exposure is a linear authored multiplier rather than a photographic EV model, automatic exposure, or a complete color-management pipeline.

### 10. Make shadow participation explicit

**Decision:** Expose separate engine-provided shadow caster and receiver marker components and render four stabilized camera-relative cascades from the first directional light. See ADR-039.
**Why:** Projects should control shadow cost and semantics independently for occluders and shaded surfaces without coupling them to geometry or material ownership.
**Tradeoff:** Shadows stop at 80 world units and do not yet cover point lights, multiple shadowed directional lights, cascade blending, or configurable quality levels.

### 11. Keep decoded images in resource ownership and GPU objects in the backend

**Decision:** Material resources own decoded RGBA pixels and dimensions, while WGPU lazily creates versioned textures and bind groups.
**Why:** Project validation can decode assets without a GPU, hot reload can replace a named material while preserving handles, and renderer-specific objects stay out of ECS and shared resources.
**Tradeoff:** The first slice retains decoded pixels after upload and has no streaming, compression, mipmap generation, or memory budget.

### 12. Postprocess the HDR world before UI

**Decision:** Render the world into a floating-point target, build five successively smaller bloom levels with one compute pass, composite them with the HDR scene, tone map once, and draw UI afterward.
**Why:** Bloom requires values above display white, broad halos need multiple spatial scales, and text must remain crisp. See ADR-029.
**Tradeoff:** Bloom threshold and weights remain fixed engine defaults. The compute pyramid requires storage-texture support for the floating-point bloom format, while the final composite remains a fullscreen render pass.

### 13. Keep visibility and indirect state in the backend

**Decision:** Preserve stable ECS render slots and a dirty-updated retained render list while WGPU owns persistent instance storage, retained grow-only batch membership, compute frustum culling, per-batch visible-instance compaction, and indexed indirect arguments. Camera and shadow visibility use separate outputs. See ADR-034.
**Why:** Unchanged instance data should stay resident, active renderables should not be rescanned, membership churn in an existing batch should not rebuild the draw database, and project/ECS data should remain independent from WGPU objects.
**Tradeoff:** The path has an explicit 131,072-slot limit, uses conservative bounding spheres, requires one previous frame with stable camera and instance data before Hi-Z rejection, and still encodes one indirect call per CPU-retained geometry/material/LOD batch. The draw database itself grows instead of imposing a fixed batch ceiling.

### 14. Compose the imported environment as the HDR sky and support camera exposure

**Decision:** Keep image-based lighting and visible backgrounds independent. Preserve every imported Environment's source-resolution linear panorama for an optional infinite camera-oriented background, while using importer-built irradiance and prefiltered specular cubes for lighting. One authored `scrapbot.world_environment` component selects both sources plus independent intensity, rotation, exposure compensation, and blur. An enabled background without a resource renders a procedural atmospheric sky with a distinct spherical ground hemisphere, subtly curved aerial-perspective horizon, and an independently art-directed HDR sun. The component exposes bounded sky tint, ground color, turbidity, thickness, horizon softness, sun direction, color, intensity, size, and glow; these values share the retained environment revision and uniform update instead of creating per-frame work. World-environment and active-camera exposure apply to the complete HDR world.
**Why:** Lighting probes are useful even when their photographic capture is unsuitable as scenery. A compact reflection cube is not an acceptable sharp background, while an intentionally blurred backdrop can reuse its prefiltered levels. Independent presentation avoids coupling art direction to physically useful reflections.
**Tradeoff:** Environment products retain both the full panorama and compact lighting cubes, and an enabled background keeps another prefiltered cube resident. The procedural sun consumes the first directional-light slot while above the horizon. There is no photographic EV calibration, automatic exposure, panorama mip chain, or local reflection-probe blending yet.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-010, ADR-011, ADR-029, ADR-034, ADR-038, ADR-039
- **FDRs:** FDR-001, FDR-002, FDR-008

## Open Questions

- How should authored LOD evolve from generated icospheres to imported meshes, offline simplification, and meshlets?
- How should offscreen render output be compared once scene rendering exists?
- How long should the headful runtime loop live before the editor and game loop exist?
