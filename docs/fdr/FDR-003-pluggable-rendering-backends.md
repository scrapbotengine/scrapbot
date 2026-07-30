# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-07-30

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend renders full indexed geometry with shared metallic-roughness GGX materials, mipmapped base-color/normal/occlusion/emissive images, a perspective camera, ambient/directional/point lighting, and optional scene-authored image-based environment lighting.
- The first directional light produces four stabilized, camera-relative 2048×2048 shadow cascades. Only entities with `ShadowCaster` contribute slope-biased depth, and only entities with `ShadowReceiver` sample the cascades through a wider tent-weighted nine-comparison PCF kernel after a cascade-texel-scaled receiver-normal offset. The last 10% of each cascade blends into the next; the final cascade blends to unshadowed beyond the configured shadow distance.
- Lights are extracted into compact backend-neutral frame data: accumulated ambient light, four directional lights, and a growable retained point-light list. WGPU grows its point-light and cluster-index buffers geometrically and deterministically builds a 16×9×24 view-frustum grid on the GPU. Every cluster can reference the complete retained list, preventing dense moving lights from popping at an internal overflow boundary. Editor-inset rendering uses the viewport's origin and extent for fragment-to-cluster lookup. Above the procedural horizon, World Environment contributes the first derived directional-light slot without creating an authored entity; explicit ECS lights fill the remaining directional slots.
- The HDR pipeline:
  - samples base-color and emissive images as sRGB while material data and imported environments remain linear;
  - combines diffuse irradiance, roughness-prefiltered reflection, direct GGX lighting, and emission;
  - supports imported environment lighting plus an independently imported or procedural visible sky;
  - derives an above-horizon procedural sun as the first directional render light;
  - applies half-resolution, 32-sector visibility-bitmask AO only to indirect diffuse;
  - resolves TAA with camera reprojection, previous-depth rejection, and neighborhood clamping;
  - optionally meters viewport log luminance and adapts exposure entirely on the GPU;
  - builds five bloom levels, then tone maps once into the sRGB presentation target.
- Project UI, transform gizmos, editor-only project-camera bodies and projection frusta, and editor chrome render after world postprocessing and do not bloom.
- Eligible entities receive internal render-instance components automatically.
- Shared geometry/material pairs use one instanced draw batch, and geometry and material texture uploads are cached by handle and version.
- WGPU keeps a persistent slot-addressed GPU instance table, separates static source state from hot Transform state, sends Transform-only changes through one dense update upload, coalesces nearby static slot changes into bounded uploads, retains compact render/culling uniforms and instance-to-LOD batch mappings, computes camera and shadow frustum visibility into compacted batch slices, and obtains instance counts from indexed indirect draw arguments.
- The retained draw database grows geometrically past the original 64-batch limit. It rebuilds only when render membership, geometry LOD topology, or required capacity changes.
- Every Geometry version owns bounded meshlets. Adapters with indirect-first-instance support retain one indirect command and aligned visible-instance slice per meshlet. Compute culls camera meshlets by sphere, normal cone, and Hi-Z and shadow meshlets by cascade sphere, then world, depth, and shadow issue one native fixed multi-draw per retained batch. Unsupported adapters, `--cpu-culling`, and layouts above the bounded visibility capacity use the whole-primitive path.
- The active camera selects a backend-neutral debug view: lit output, base color, mapped world normals, perceptual roughness, metallic, logarithmic camera depth, retained meshlet identity, exact GPU-selected LOD, or object/meshlet visibility classification. Non-lit views skip temporal jitter, AO, SSR, volumetric fog, automatic exposure, bloom, tone mapping, and temporal/fast AA so diagnostics remain direct and stable. Meshlet identity is topology-owned and uploaded only when retained meshlet layout changes. Visibility mode emits rejected bounds into an opt-in GPU diagnostic stream and draws it indirectly without CPU readback. An explicit diagnostic pattern reports when the active backend is using whole-primitive submission.
- Large stable scenes run a depth prepass, build a max-depth Hi-Z pyramid, and conservatively reject occluded bounding spheres from the following frame. Camera or persistent-instance changes disable stale-pyramid rejection for that frame. Hi-Z queries cover the complete coarse-mip footprint; camera-plane crossings and large near-field bounds remain visible rather than risking a false rejection.
- UUID-backed `scrapbot.geometry_lod` project resources declare generated icosphere levels and descending projected screen-radius thresholds. The GPU visibility pass selects the geometry batch; the CPU-reference path implements the same result.
- `--cpu-culling` runs the same conservative camera/shadow visibility contract on the CPU and uploads its compacted lists and counts; it is a compatibility and correctness-reference path, not the performance default.
- Structured run results include renderer counters for GPU-driven mode, meshlet capability/activation/draw/visibility state, draw/instance/visibility capacity, database rebuilds, occupied slot span, cumulative instance upload calls and bytes, instance/meshlet frustum, cone, and occlusion counts, per-LOD visible counts, and optional per-pass GPU milliseconds. Visibility and timing use asynchronous readback rings and never synchronously stall the frame.
- Headless `wgpu` creates an adapter and device without SDL or an OS presentation surface, renders into an offscreen texture, and can run bounded GPU workloads without reading pixels back.
- The offscreen path can optionally render a losslessly compressed final-frame PNG with `--framegrab`.
- `--framegrab-region x,y,width,height` exports a top-left-origin 1:1 pixel crop without resampling; omitting it preserves the complete 1280×720 frame.
- `scrapbot profile` drives the same headless WGPU path at the project resolution or an explicit override. It collects tagged per-frame timestamp results without mapping render-target pixels, then optionally repeats the run to capture a narrow lossless sequence.
- WGPU sizes the live world and project UI to the complete available viewport, deriving camera aspect from its dimensions, then paints engine chrome in a separate overlay pass.
- Visible WGPU windows continue stepping and presenting frames during native live resize, reconfiguring the surface to each exposed pixel size instead of waiting for the drag to end.
- Visible windows use the project's logical startup size and request a high-pixel-density drawable independently. Headless WGPU keeps its deterministic 1280×720 offscreen target.
- Source-project runs provide a visible WGPU window by default. `--headless` selects the offscreen path whether or not a framegrab is requested.
- Renderer runs can be limited with `--frames`; windowed `0` means run until the window closes,
  while headless `0` renders one frame.
- `mise test-gpu-offscreen` qualifies the surface-free path with a bounded Metal CI gate. It
  preserves one structured envelope, stderr log, and 1:1 PNG per case plus a timing/counter
  manifest; failures keep partial artifacts. Absolute GPU times remain diagnostic rather than
  portable thresholds.
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

**Decision:** Headless WGPU requests a surface-free adapter/device, renders the same ECS pipeline into an offscreen texture, and allocates no readback buffer unless a framegrab or capture sequence is requested. An optional readback writes a losslessly compressed full-frame PNG or explicit 1:1 pixel crop.
**Why:** This gives agents and tests a visual artifact that exercises the same scene-driven renderer path as the windowed backend while allowing focused inspection without shipping unrelated pixels through an agent conversation.
**Tradeoff:** Offscreen WGPU still requires the host or sandbox to expose a compatible native graphics adapter. GPU-less workers and managed macOS sandboxes that hide Metal devices must use the null backend or a GPU-enabled runner.

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

**Decision:** Ambient, directional, and point lights are public ECS components. ECS extraction iterates compact active sets, accumulates ambient light, copies up to four directional lights, and retains every active point light in each render list. WGPU builds deterministic per-cluster point-light lists entirely on the GPU and grows its buffers geometrically. See ADR-011 and ADR-039.
**Why:** Lights remain scriptable scene state without exposing ECS storage to renderer backends, while fragment work scales with locally relevant lights instead of the complete packet.
**Tradeoff:** WGPU initially reserves about 3.4 MiB for cluster indices and doubles that storage after crossing 256 retained lights. A pathological cluster may evaluate every retained light; compact variable-length cluster storage and explicit device-limit diagnostics remain future work.

### 9. Accumulate lighting in linear space and tone map the result

**Decision:** Treat authored material colors as sRGB, decode them before lighting, apply an ACES-style curve to the HDR result, and prefer sRGB render targets for presentation and framegrabs.
**Why:** Directly adding strong light contributions to display-space colors clips channels independently, washes out saturated lights, and produces inconsistent output across UNORM and sRGB targets.
**Tradeoff:** Exposure is a linear authored multiplier rather than a photographic EV model, automatic exposure, or a complete color-management pipeline.

### 10. Make shadow participation explicit

**Decision:** Expose separate engine-provided shadow caster and receiver marker components and render four stabilized camera-relative cascades from the first directional light. See ADR-039.
**Why:** Projects should control shadow cost and semantics independently for occluders and shaded surfaces without coupling them to geometry or material ownership.
**Tradeoff:** Shadows stop at 80 world units and do not yet cover point lights, multiple shadowed directional lights, or configurable quality levels.

### 11. Keep decoded images in resource ownership and GPU objects in the backend

**Decision:** Material resources own decoded RGBA pixels and dimensions, while WGPU lazily creates versioned textures and bind groups.
**Why:** Project validation can decode assets without a GPU, hot reload can replace a named material while preserving handles, and renderer-specific objects stay out of ECS and shared resources.
**Tradeoff:** The first slice retains decoded pixels after upload and has no streaming, compression, mipmap generation, or memory budget.

### 12. Postprocess the HDR world before UI

**Decision:** Render the world into floating-point color, compact surface data, and a separate indirect-diffuse contribution.

The active camera controls a `0.5`–`1` world render-grid ceiling, optional GPU-budgeted dynamic-resolution floor/target, fixed or automatic exposure, TAA, current-frame fast AA, half-resolution AO, SSR, and five-level bloom. Native scale is the default. Lower scales reduce world, depth, Hi-Z, and post-processing work; final composition upscales into the native output before project UI and editor chrome. AO maps an authored `0.25`–`1` quality value to four bounded 8/16/24/36-sample tiers, with balanced `0.5` as the default.

One optional authored `scrapbot.volumetric_fog` component supplies a global exponential height medium. A separately timestamped half-resolution compute pass integrates 16 low-discrepancy sub-step samples, rotated across the eight-frame temporal sequence, up to scene depth or the authored distance bound. The full-resolution temporal pass depth-aware upsamples scattering and transmittance before history accumulation. Ambient scattering is unshadowed; anisotropic primary-directional scattering uses a 2×2 UV-space filter and the same cascade transition bands as opaque geometry. Projects may independently opt clustered point lights into the medium. Absence or zero density skips the ray-march dispatch.

AO uses rotated view-space slices and a 32-sector visibility bitmask. Each depth sample covers the interval between its front surface and a constant-thickness reconstructed back surface. A separable bilateral filter crosses only compatible depth and normals, then AO attenuates indirect diffuse.

SSR performs a bounded current-frame view-space ray march and fades uncertain, distant, rough, and screen-edge hits. Four authored quality tiers select 16, 32, 48, or 64 steps. The balanced 32-step default widens its stride to preserve approximately the reference path's reach at coarser intersection precision.

TAA jitters the projection with an eight-sample sequence bounded to a quarter pixel. Retained color/depth history lives on a stable output grid, so camera reprojection uses unjittered matrices and removes the current sample offset before reading history. A local 2×2 depth search avoids rejecting valid subpixel history at silhouettes, while YCoCg variance clipping limits stale color. Each 8×8 workgroup composes one shared 10×10 current-color tile, preserving the exact 3×3 clamp neighborhood without repeating its AO, indirect-diffuse, and SSR work for every tap. Resize, world replacement, depth replacement, camera cuts, and TAA mode changes reject history. Culling stays unjittered.

Automatic exposure uses one 256-thread GPU workgroup to reduce viewport-stratified log-luminance samples and exponentially adapt a persistent clamped scalar. HDR history remains scene-linear. Bloom and final composition share the scalar, while manual camera exposure becomes compensation. There is no CPU readback.

The editor fly view inherits the project camera's render policy. WGPU dynamic resolution consumes asynchronous GPU timestamps, excludes native UI, and changes its derived effective scale only in hysteretic 5% steps. Unsupported timing uses the authored ceiling. Scale changes replace only size-dependent retained targets and reject temporal history. Disabled features skip their compute or history work. Tone map once into native output, then draw UI at native resolution.
**Why:** Architectural contacts and crevices need indirect-light grounding, participating media needs depth-aware and shadow-aware scattering, smooth materials need local reflections, bloom requires values above display white, broad halos need multiple spatial scales, subpixel geometry and texture detail need temporal supersampling, and text must remain crisp. Reusing depth supports fog bounds, AO, reflection ray intersection, and camera reprojection without another geometry pass or velocity target. See ADR-029.
**Tradeoff:** These techniques deliberately exchange completeness, precision, latency, memory, and configurability for bounded real-time work:

- Screen-space effects cannot see off-screen or occluded sources. SSR uses a bounded linear march and fades rough reflections instead of tracing Hi-Z or filtering them. Lower quality tiers preserve reach by trading intersection precision for fewer steps.
- Camera-only temporal reprojection lacks exact motion for animated objects. Previous-depth rejection and neighborhood clamping bound history error until per-object motion vectors exist.
- Fog is one global 16-step volume, and every step evaluates its complete clustered point-light list. Local volumes, froxels, and quality controls remain follow-up work.
- Automatic exposure uses a bounded sparse meter rather than a full histogram and exposes only bounds, speed, and compensation.
- Dynamic resolution reacts to delayed, noisy GPU evidence instead of guaranteeing a hard deadline. Hysteresis favors visual stability over immediate recovery, and lower scales trade world sharpness for pixel cost while preserving native UI.
- Camera fields expose scale policy, coarse switches, and AO/SSR quality. AO shaping and temporal/fast-AA/bloom quality and weights remain future work.
- Compute paths require storage-texture support. Surface, indirect-diffuse, reflection, color, and depth history consume additional GPU memory, and final composition remains a fullscreen render pass.
- Fixed screen-space presentation dithering removes coherent 8-bit bands without temporal shimmer by intentionally adding sub-LSB spatial noise to tone-mapped world pixels.

### 13. Keep visibility and indirect state in the backend

**Decision:** Preserve stable ECS render slots and a dirty-updated retained render list while WGPU owns persistent instance storage, retained grow-only batch membership, compute frustum culling, per-batch visible-instance compaction, and indexed indirect arguments. Camera and shadow visibility use separate outputs. See ADR-034.
**Why:** Unchanged instance data should stay resident, active renderables should not be rescanned, membership churn in an existing batch should not rebuild the draw database, and project/ECS data should remain independent from WGPU objects.
**Tradeoff:** The path has an explicit 131,072-slot limit, uses conservative bounding spheres, and requires one previous frame with stable camera and instance data before Hi-Z rejection. Whole-primitive fallback still encodes one indirect call per CPU-retained geometry/material/LOD batch. The draw database itself grows instead of imposing a fixed batch ceiling.

### 14. Cull resource-owned meshlets without requiring mesh shaders

**Decision:** Request indirect-first-instance when the adapter exposes it. At Geometry-version
boundaries, expand meshlet-local triangles into a meshlet-ordered index buffer and retain one
indexed-indirect template plus aligned instance slice per meshlet. After object rejection and LOD
selection, compute camera cluster visibility from sphere, normal cone, and Hi-Z tests and shadow
cluster visibility from cascade spheres. Submit the CPU-known command ranges through native fixed
multi-draw. See ADR-046.

**Why:** Large primitives need a visibility unit smaller than the complete object, but mesh shaders
are outside the current WebGPU baseline. Fixed multi-draw matches the actual ownership: resource
versions determine command topology, while the GPU determines each command's instance count.

**Tradeoff:** Each meshlet reserves visibility capacity for the complete batch, so WGPU bounds the
total at 1,048,576 entries and falls back when it cannot represent a layout safely. Double-sided
materials skip normal-cone rejection. The deterministic CPU reference remains whole-primitive
culling rather than duplicating the GPU cluster implementation. WGPU requests native multi-draw-
count when present; without it, wgpu-native may emulate the fixed multi-draw call as individual
indirect draws while preserving the meshlet raster-work reduction.

### 15. Make render debug views part of the camera contract

**Decision:** Store a backend-neutral debug-view enum on the public Camera component. WGPU renders
material inputs, mapped world normals, logarithmic camera depth, retained meshlet identity, or the
exact GPU-selected LOD directly and bypasses presentation effects that would alter those values.
Meshlet layout owns a parallel identity stream aligned with its visible-instance slices; topology
rebuilds upload it, while stable frames only read it.

Visibility mode colors submitted meshlets green. While active, the existing culling pass also
classifies rejected object and meshlet bounds into an aligned tail of the meshlet visibility
allocation, copies the resulting GPU counter into an indirect draw, and overlays procedural sphere
lines. It adds neither a cull-stage storage binding nor CPU readback. Whole-primitive fallback
renders an unmistakable unavailable pattern instead of mislabeling triangles as meshlets.

The editor composes its Game-view selector from ordinary public layout, button, popup, list, and
scroll components. Its choice temporarily overrides the extracted camera copy and never mutates
the authored project camera. Choosing `Camera` returns control to the authored value.

**Why:** Projects, tools, automated framegrabs, and the editor need the same view semantics.
Diagnostics must describe actual retained renderer data, and inspecting a scene must not dirty it.

**Tradeoff:** Meshlet modes require active meshlet submission. Visibility mode deliberately adds
diagnostic writes and one indirect overlay pass while selected, and overlapping rejected bounds
can become dense in large scenes. Hi-Z pyramid and mip inspection remain follow-up work.

### 16. Compose the imported environment as the HDR sky and support camera exposure

**Decision:** Keep environment lighting and visible backgrounds independent.

Imported Environments retain their source-resolution linear panorama for an optional infinite background. Importer-built irradiance and prefiltered specular cubes provide lighting.

One `scrapbot.world_environment` component selects both sources and their presentation settings. Its reflection multiplier scales specular environment lighting independently from diffuse irradiance. An enabled background without a resource renders the procedural atmosphere.

Without imported lighting, the world shader evaluates the same procedural sky for diffuse and roughness-aware specular radiance. Sky, ground, haze, and sun controls share one retained revision and uniform update; they create neither per-frame rebuilds nor generated cube resources.

World-environment and active-camera exposure apply to the complete HDR world.
**Why:** Lighting probes are useful even when their photographic capture is unsuitable as scenery. A compact reflection cube is not an acceptable sharp background, while an intentionally blurred backdrop can reuse its prefiltered levels. Independent presentation avoids coupling art direction to physically useful reflections.
**Tradeoff:** Environment products retain both the full panorama and compact lighting cubes, and an enabled background keeps another prefiltered cube resident. The procedural sun consumes the first directional-light slot while above the horizon. There is no photographic EV calibration, automatic exposure, panorama mip chain, or local reflection-probe blending yet.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-010, ADR-011, ADR-029, ADR-034, ADR-038, ADR-039, ADR-046
- **FDRs:** FDR-001, FDR-002, FDR-008

## Open Questions

- How should authored LOD evolve from generated icospheres to imported meshes and offline simplification?
- How should offscreen render output be compared once scene rendering exists?
- How long should the headful runtime loop live before the editor and game loop exist?
