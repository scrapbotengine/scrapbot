# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-08-10

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend renders full indexed geometry with shared metallic-roughness GGX materials, mipmapped base-color/normal/occlusion/emissive images, a perspective camera, ambient/directional/point lighting, and optional scene-authored image-based environment lighting.
- The first directional light produces four stabilized, camera-relative shadow cascades. WGPU retains 2048×2048 capacity and, when adaptive quality is enabled, can rasterize a quantized 2048, 1024, or 512 square region from the same allocation and within the authored quality floor.
- Adaptive quality follows the camera's bounded 20-sample GPU-scene p95 after sustained pressure.
  It steps through world scale, shadow resolution, virtual detail, and post quality, waits between
  transitions, and restores only with prolonged tail headroom. Policy-owner changes reset the
  ladder to full quality.
- Only entities with `ShadowCaster` contribute slope-biased depth. Only entities with `ShadowReceiver` sample the cascades through a tent-weighted nine-comparison PCF kernel after a cascade-texel-scaled receiver-normal offset. The last 10% of each cascade blends into the next; the final cascade blends to unshadowed beyond the configured shadow distance.
- Lights are extracted into compact backend-neutral frame data: accumulated ambient light, four directional lights, and a growable retained point-light list. WGPU grows its point-light and cluster-index buffers geometrically and deterministically builds a 16×9×24 view-frustum grid on the GPU. Every cluster can reference the complete retained list, preventing dense moving lights from popping at an internal overflow boundary. Editor-inset rendering uses the viewport's origin and extent for fragment-to-cluster lookup. Above the procedural horizon, World Environment contributes the first derived directional-light slot without creating an authored entity; explicit ECS lights fill the remaining directional slots.
- The HDR pipeline:
  - samples base-color and emissive images as sRGB while material data and imported environments remain linear;
  - combines diffuse irradiance, roughness-prefiltered reflection, direct GGX lighting, and emission;
  - supports imported environment lighting plus an independently imported or procedural visible sky;
  - derives an above-horizon procedural sun as the first directional render light;
  - applies resolution-scaled, 32-sector visibility-bitmask AO only to indirect diffuse;
  - resolves TAA with camera reprojection, previous-depth rejection, and neighborhood clamping;
  - optionally meters viewport log luminance and adapts exposure entirely on the GPU;
  - builds five bloom levels, derives optional ghost flares and procedural lens dirt from that HDR energy, then tone maps and applies an optional vignette once into the sRGB presentation target.
- Project UI, transform gizmos, editor-only project-camera bodies and projection frusta, and editor chrome render after world postprocessing and do not bloom.
- Eligible entities receive internal render-instance components automatically.
- Shared geometry/material pairs use one instanced draw batch. Geometry versions occupy aligned ranges in shared WGPU vertex/index arenas, while material texture uploads remain cached by handle and version.
- WGPU keeps a persistent slot-addressed GPU instance table, separates static source state from hot Transform state, sends Transform-only changes through one dense update upload, coalesces nearby static slot changes into bounded uploads, retains compact render/culling uniforms and instance-to-LOD batch mappings, computes camera and shadow frustum visibility into compacted batch slices, and obtains instance counts from indexed indirect draw arguments.
- The retained draw database grows geometrically past the original 64-batch limit. It rebuilds only when render membership, geometry LOD topology, or required capacity changes.
- Every Geometry version owns bounded meshlets and a crack-aware, deterministically paged cluster hierarchy. Simplification preserves normal and UV discontinuities and never falls back to attribute-blind reduction.
- Geometry submission resolves at stable topology boundaries from entity override, Model-resource preference, project default, and backend automatic policy. Conventional and Virtual instances of one Geometry can coexist in separate retained batches and caches.
- Complete page sets that fit the remaining budget are admitted immediately; coarse pages remain pinned for streamed resources. The GPU selects resident detail, requests missing finer pages, and draws the nearest resident fallback before camera sphere, normal-cone, and Hi-Z tests.
- Native multi-draw adapters retain one indirect command per ordinary meshlet or hierarchy cluster
  and use a one-pixel maximum-quality virtual frontier. Other indirect-first-instance adapters
  append selected instance/meshlet records into bounded camera and shadow streams and vertex-pull
  compatible material spans through four triangle-count lanes. Only nonempty lanes submit indirect
  commands. When virtual batches use this portable compact path, its maximum-quality frontier starts
  at two pixels; adaptive quality may raise the shared effective target further under pressure.
- Adapters without indirect-first-instance and `--cpu-culling` retain whole-primitive imported LOD selection. Streamed resources use the indexed proxy built from pinned coarse pages.
- The active camera selects a backend-neutral debug view: lit output, material inputs, mapped world normals, logarithmic depth, retained meshlet identity, exact GPU-selected LOD, selected virtual-geometry clusters and hierarchy depth, object/meshlet visibility classification, one retained Hi-Z mip, or exact screen-space Hi-Z query footprints. Non-lit views skip presentation effects so diagnostics remain direct and stable.
- Hi-Z false color and texel boundaries expose the exact conservative max-depth hierarchy without readback or rebuilding it. Occlusion Queries records each tested rectangle, selected mip, bound depth, sampled farthest depth, identity, and visible/culled decision in a bounded GPU-native stream.
- The camera can freeze the latest valid occlusion-query records while that view remains selected. Freeze preserves only diagnostic records and their indirect draw count; ordinary culling continues from current safe Hi-Z state.
- Large stable scenes run a depth prepass, build a max-depth Hi-Z pyramid, and conservatively reject occluded bounding spheres from the following frame. Camera or persistent-instance changes disable stale-pyramid rejection. Camera motion instead uses a frustum-only coarse depth pass before refining visibility against a newly built current-camera pyramid. Each query projects the eight corners of an enclosing cube and uses their nearest possible depth, so large off-axis clusters cannot be rejected from a center-only approximation. Camera-plane crossings and large near-field bounds remain visible rather than risking a false rejection.
- UUID-backed `scrapbot.geometry_lod` project resources declare generated icosphere levels and descending projected screen-radius thresholds. The GPU visibility pass selects the geometry batch; the CPU-reference path implements the same result.
- `--cpu-culling` runs the same conservative camera/shadow visibility contract on the CPU and uploads its compacted lists and counts; it is a compatibility and correctness-reference path, not the performance default.
- Structured run results distinguish retained draw batches from encoded draw submissions. They include shared geometry arena capacity, residency, uploads, bytes, and growths beside GPU-driven, visibility, meshlet, Hi-Z, LOD, instance-upload, portable compact-batch/instance, useful compact-triangle, padded compact-vertex-invocation, virtual-geometry, and optional per-pass timing counters. Visibility and timing use asynchronous readback rings and never synchronously stall the frame.
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

The active camera controls a `0.5`–`1` world render-grid ceiling/floor, optional GPU target, adaptive post-quality floor, fixed or automatic exposure, TAA, current-frame fast AA, resolution-scaled AO, SSR, and five-level bloom. Native scale is the default. World, depth, Hi-Z, and post targets are sized from the physical game viewport, excluding editor chrome. Lower scales reduce those viewport-local targets further; final composition maps the result into the native game viewport before project UI and editor chrome. AO has independent `0.25`–`1` sampling-quality and target-resolution controls, defaulting to `0.5` and `0.25` respectively.

One optional authored `scrapbot.volumetric_fog` component supplies a global exponential height medium and an independent `0.25`–`1` target-resolution scale, defaulting to `0.25`. A separately timestamped compute pass integrates 16–64 samples up to scene depth or the authored distance bound. The coordinated frame-budget policy selects the step count.

Fog owns a dedicated ping-pong scattering/transmittance history at its authored target scale. Fog-texel coordinates and a 256-frame sequence feed an integer-scrambled ray offset. Finite surfaces reproject by world position; background samples reproject a finite point inside the medium.

Previous depth rejects disocclusions. A current-radiance neighborhood bounds retained scattering, and motion plus shading-change confidence shorten history before old shadow shafts can trail behind camera movement. Invalid, disabled, or newly enabled history uses a stable midpoint. The full-resolution temporal pass then depth-aware reconstructs the resolved fog into current scene color without accumulating background fog a second time.

Ambient scattering is unshadowed. Anisotropic primary-directional scattering uses a 2×2 UV-space filter and the same cascade transition bands as opaque geometry. Projects may independently opt clustered point lights into the medium. Absence or zero density skips the ray-march dispatch.

AO uses rotated view-space slices and a 32-sector visibility bitmask. Each depth sample covers the interval between its front surface and a constant-thickness reconstructed back surface. A separable bilateral filter crosses only compatible depth and normals, then AO attenuates indirect diffuse.

SSR performs a bounded current-frame view-space ray march and fades uncertain, distant, rough, and screen-edge hits. Four authored quality tiers select 16, 32, 48, or 64 steps. The balanced 32-step default widens its stride to preserve approximately the reference path's reach at coarser intersection precision.

TAA jitters the projection with an eight-sample sequence bounded to a quarter pixel. Retained color/depth history lives on a stable output grid, so camera reprojection uses unjittered matrices and removes the current sample offset before reading history. A local 2×2 depth search avoids rejecting valid subpixel history at silhouettes, while YCoCg variance clipping limits stale color. Each 8×8 workgroup composes one shared 10×10 current-color tile, preserving the exact 3×3 clamp neighborhood without repeating its AO, indirect-diffuse, and SSR work for every tap. Resize, world replacement, depth replacement, camera cuts, and TAA mode changes reject history. Culling stays unjittered.

Automatic exposure uses one 256-thread GPU workgroup to reduce viewport-stratified log-luminance samples and exponentially adapt a persistent clamped scalar. HDR history remains scene-linear. Bloom and final composition share the scalar, while manual camera exposure becomes compensation. There is no CPU readback.

Three optional singleton ECS components independently author vignette, ghost lens flares, and procedural lens dirt. Flares sample the bloom bright-pass into bounded chromatically separated ghosts plus a halo. Halo lookup preserves each output sample's radial distance instead of collapsing a complete center ray onto one bloom texel. Dirt modulates only bloom and flare energy, never the base scene. Adaptive post quality reduces the authored ghost count, and non-lit debug views bypass all three effects. Vignette is applied after tone mapping so its authored display-space framing remains independent of exposure.

The editor fly view inherits the project camera's render policy. WGPU consumes an asynchronous ordered pass-boundary span that ends after final composition and before native UI. One hysteretic controller selects world scale, directional-shadow resolution, virtual-geometry projected-error tolerance, and a normalized AO/SSR/fog quality factor from a deterministic reversible ladder. All changes share one measurement generation and cooldown. Adapters without timestamp queries use authored maxima. Target-size changes replace only size-dependent retained targets and reject temporal history. Disabled features skip their compute or history work. Tone map once into the native game viewport, then draw UI at native resolution. See ADR-052.
**Why:** Architectural contacts and crevices need indirect-light grounding, participating media needs depth-aware and shadow-aware scattering, smooth materials need local reflections, bloom requires values above display white, broad halos need multiple spatial scales, subpixel geometry and texture detail need temporal supersampling, and text must remain crisp. Reusing depth supports fog bounds, AO, reflection ray intersection, and camera reprojection without another geometry pass or velocity target. See ADR-029.
**Tradeoff:** These techniques deliberately exchange completeness, precision, latency, memory, and configurability for bounded real-time work:

- Screen-space effects cannot see off-screen or occluded sources. SSR uses a bounded linear march and fades rough reflections instead of tracing Hi-Z or filtering them. Lower quality tiers preserve reach by trading intersection precision for fewer steps.
- Camera-only surface reprojection lacks exact motion for animated objects. Previous-depth rejection and neighborhood clamping bound surface-history error until per-object motion vectors exist. Fog history is independently bounded by depth, motion, and radiometric confidence.
- Fog is one global 4–16-step volume, and every step evaluates its complete clustered point-light list. Local volumes and froxels remain follow-up work.
- Automatic exposure uses a bounded sparse meter rather than a full histogram and exposes only bounds, speed, and compensation.
- Lens flares are screen-space and therefore see only bright energy present in the rendered viewport. Procedural dirt is deterministic and asset-free, but cannot reproduce a photographed lens texture.
- Adaptive quality reacts to delayed, noisy GPU evidence instead of guaranteeing a hard deadline. Hysteresis favors visual stability over immediate recovery. Lower world scale, shadow resolution, and post tiers exchange precision for cost while preserving native UI and authored feature switches.
- Camera fields expose frame-budget bounds, coarse switches, and AO/SSR quality ceilings. AO shaping and temporal/fast-AA/bloom quality and weights remain future work.
- Compute paths require storage-texture support. Surface, indirect-diffuse, reflection, color, and depth history consume additional GPU memory, and final composition remains a fullscreen render pass.
- Fixed screen-space presentation dithering removes coherent 8-bit bands without temporal shimmer by intentionally adding sub-LSB spatial noise to tone-mapped world pixels.

### 13. Keep visibility and indirect state in the backend

**Decision:** Preserve stable ECS render slots and a dirty-updated retained render list while WGPU owns persistent instance storage, retained grow-only batch membership, compute frustum culling, per-batch visible-instance compaction, and indexed indirect arguments. Camera and shadow visibility use separate outputs. See ADR-034.
**Why:** Unchanged instance data should stay resident, active renderables should not be rescanned, membership churn in an existing batch should not rebuild the draw database, and project/ECS data should remain independent from WGPU objects.
**Tradeoff:** The path has an explicit 131,072-slot limit, uses conservative bounding spheres, and requires one previous frame with stable camera and instance data before Hi-Z rejection. Adapters without indirect-first-instance still encode one indirect call per CPU-retained geometry/material/LOD batch. The draw database itself grows instead of imposing a fixed batch ceiling.

The retained batch count describes topology, not post-cull work. The visibility pass separately
counts camera batches whose first object sets a fixed visibility bit and meshlet commands whose
first instance advances an indirect count from zero. The bitset shares the existing counter buffer,
adding no storage binding, CPU scan, or readback path. Camera culling does not describe the
independently culled shadow cascades.

### 14. Cull resource-owned meshlets without requiring mesh shaders

**Decision:** Request indirect-first-instance when the adapter exposes it. At Geometry-version
boundaries, expand meshlet-local triangles into a meshlet-ordered index buffer and retain one
indexed-indirect template plus aligned instance slice per meshlet. After object rejection and LOD
selection, compute camera cluster visibility from sphere, normal cone, and Hi-Z tests and shadow
cluster visibility from cascade spheres. Select ordinary meshlet submission independently for
batches with at least two instances; retain one whole-primitive command for single-instance
non-hierarchical batches. Meshlet debug views force eligible batches through the cluster path.
Native multi-draw submits retained indexed commands. Portable adapters compact conventional and
virtual meshlets into shared triangle-count lanes. See ADR-046.

**Why:** Large reused primitives need a visibility unit smaller than the complete object, but mesh
shaders are outside the current WebGPU baseline. Fine-grained submission can cost more than it
saves when a batch has only one instance. Per-batch selection preserves GPU-driven visibility
without multiplying command finalization for low-instance scenes. Fixed multi-draw matches the
actual ownership: resource versions determine command topology, while the GPU determines each
command's instance count.

**Tradeoff:** Each meshlet reserves visibility capacity for the complete batch, so WGPU bounds the
total at 1,048,576 entries and falls back when it cannot represent a layout safely. Double-sided
materials skip normal-cone rejection. The deterministic CPU reference remains whole-primitive
culling rather than duplicating the GPU cluster implementation. Portable vertex pulling adds
bounded triangle-lane padding, reported by `compact_triangles` and
`compact_vertex_invocations`. The current two-instance threshold is conservative and backend-wide
rather than adapter-calibrated. Cluster metadata capacity grows geometrically within the device's
reported storage-buffer binding limit.

A mixed frame uses one compute pass with classic, native-meshlet, compact-candidate, and parallel
compact-meshlet stages. Each stage binds only its required visibility and indirect resources,
stays within the portable storage-binding limit, and returns immediately for batches owned by the
other policies.

### 15. Make render debug views part of the camera contract

**Decision:** Store a backend-neutral debug-view enum on the public Camera component. WGPU renders
material inputs, mapped world normals, logarithmic camera depth, retained meshlet identity, or the
exact GPU-selected LOD directly and bypasses presentation effects that would alter those values.
Meshlet layout owns a parallel identity stream aligned with its visible-instance slices; topology
rebuilds upload it, while stable frames only read it.

Hi-Z mode samples the selected mip of the current retained max-depth pyramid after it is built.
It expands each mip texel across its exact screen-space footprint and draws boundaries between
cells. The authored camera and transient editor override both clamp the requested level to the
available pyramid.

Visibility mode colors submitted meshlets green. While active, the existing culling pass also
classifies rejected object and meshlet bounds into an aligned tail of the meshlet visibility
allocation, copies the resulting GPU counter into an indirect draw, and overlays procedural sphere
lines. It adds neither a cull-stage storage binding nor CPU readback. Whole-primitive fallback
renders an unmistakable unavailable pattern instead of mislabeling triangles as meshlets.

Occlusion Queries reuses the same diagnostic tail but records every performed object or meshlet
query. Each record contains the projected rectangle, selected mip, nearest bound depth, sampled
farthest depth, identity, and decision produced by the culling shader. The overlay draws those
rectangles indirectly over dim world context: mint survived and pink was rejected.

Freeze stops replacing the query-record range and indirect count after one valid capture. It does
not preserve the pyramid for real visibility decisions, stall the GPU, or copy the records to the
CPU. Leaving the view releases the frozen diagnostic evidence.

The editor composes its Game-view selector from ordinary public layout, button, popup, list, and
scroll components. Its choice temporarily overrides the extracted camera copy and never mutates
the authored project camera. Choosing `Camera` returns control to the authored value.

**Why:** Projects, tools, automated framegrabs, and the editor need the same view semantics.
Diagnostics must describe actual retained renderer data, and inspecting a scene must not dirty it.

**Tradeoff:** Meshlet identity, visibility, and query modes require active meshlet submission. Visibility and query modes
deliberately add diagnostic writes and one indirect overlay pass while selected, and overlapping
records can become dense in large scenes. Hi-Z inspection shows conservative stored depth rather
than linear camera distance and adds one fullscreen diagnostic pass while selected. Query
inspection exposes performed conservative sphere tests, not bypassed work or triangle silhouettes.

### 16. Compose the imported environment as the HDR sky and support camera exposure

**Decision:** Keep environment lighting and visible backgrounds independent.

Imported Environments retain their source-resolution linear panorama for an optional infinite background. Importer-built irradiance and prefiltered specular cubes provide lighting.

One `scrapbot.world_environment` component selects both sources and their presentation settings. Its reflection multiplier scales specular environment lighting independently from diffuse irradiance. An enabled background without a resource renders the procedural atmosphere.

Without imported lighting, the world shader evaluates the same procedural sky for diffuse and roughness-aware specular radiance. Sky, ground, haze, and sun controls share one retained revision and uniform update; they create neither per-frame rebuilds nor generated cube resources.

World-environment and active-camera exposure apply to the complete HDR world.
**Why:** Lighting probes are useful even when their photographic capture is unsuitable as scenery. A compact reflection cube is not an acceptable sharp background, while an intentionally blurred backdrop can reuse its prefiltered levels. Independent presentation avoids coupling art direction to physically useful reflections.
**Tradeoff:** Environment products retain both the full panorama and compact lighting cubes, and an enabled background keeps another prefiltered cube resident. The procedural sun consumes the first directional-light slot while above the horizon. There is no photographic EV calibration, automatic exposure, panorama mip chain, or local reflection-probe blending yet.

### 17. Consume imported and generated LODs through one Geometry contract

**Decision:** Let imported Model products publish alternate Geometry handles, screen-radius thresholds, and simplification errors through the same resource contract as generated LOD geometry. Selection remains in the shared CPU reference and GPU visibility paths. See ADR-047.

**Why:** The renderer should optimize resource geometry without knowing whether a level came from glTF simplification, a procedural generator, Luau, native Odin, or a future authoring tool.

**Tradeoff:** Classic GPU and CPU-reference submission retain every alternate Geometry/material combination as batch topology. A capable continuous virtual-geometry submission uses only the base Geometry's hierarchy: its own geometric-error frontier replaces object-level discrete LOD selection, so alternate hierarchies do not consume batches or pinned page residency. Import recipes can still tune or disable the generated chain used by fallback paths.

### 18. Suballocate Geometry versions from shared WGPU arenas

**Decision:** Store every cached Geometry version in aligned ranges of one shared vertex arena and
one shared index arena. Canonical and meshlet-expanded indices share the latter. Grow backing
buffers geometrically, reuse fitting ranges, coalesce released ranges, and reclaim stale handles
only at geometry-topology invalidation boundaries. Retire submitted ranges until a tagged
visibility readback proves their final GPU use complete. Use arena-global indirect offsets so
adjacent same-material commands can form one fixed multi-draw submission span. See ADR-048.

**Why:** GPU-selected LODs and meshlets should not force one backend buffer set and one CPU-encoded
call per logical alternate. The same allocation layer is also the required physical foundation for
future virtual-geometry residency.

**Tradeoff:** Stable frames deliberately do not compact fragmentation. Backing-buffer growth copies
resident bytes and rebuilds dependent bindings at an explicit mutation boundary. Adapters without
indirect-first-instance share the memory arenas but retain single-batch submission semantics.

### 19. Select a resident virtual-geometry frontier

**Decision:** Derive a crack-aware cluster hierarchy for every Geometry. Retain
group depth, conservative bounds, monotonic geometric error, refined-group links, and cluster-local
indices with that exact resource version. Imported model products persist the hierarchy. Other
Geometry producers build the same representation at registration. See ADR-049 and ADR-050.

Partition each hierarchy into deterministic, group-aligned pages containing referenced canonical
vertices and page-local expanded indices. Imported products persist a compact runtime catalog with
canonical counts, position-only query data, exact leaf topology, and file page ranges instead of
standalone full render vertices and source indices. Cache-hit loading streams the catalog, skips
payload bytes, derives compatibility meshlets from exact leaves, and releases decoded entries as
they enter registry ownership. Reconstruct a temporary canonical view from leaf-containing pages
only for backend cache creation. Retain
canonical GPU vertex/index streams plus expanded page indices when the complete Geometry fits the
remaining combined payload budget; otherwise pin its coarsest page frontier. On WGPU adapters
with indirect-first-instance, project group error into pixels. Submit adjacent hierarchy levels
inside a narrow 98%-to-102% overlap around the active error threshold and the unique cluster frontier
outside it, before ordinary cluster culling.

When finer detail is wanted but missing, submit the resident coarse cluster and append its group
identity plus projected-error priority to a bounded demand lane. Separate bounded lanes carry
future-camera prefetch and cadence-sampled visible-use touches, so speculative traffic cannot erase
urgent demand. Deterministic hashing spreads touches across 16 frames; missing-group requests remain
immediate. CPU processing deduplicates the three lanes by Geometry and group.

With renderer prefetch enabled, smoothed camera motion projects a bounded future position and view
direction into a widened future frustum. The GPU may request likely refinement groups without
rendering, touching, or otherwise making them authoritative. Demand sorts first and may reclaim
speculative residency immediately. Prefetch uses spare budget and never evicts demand-resident
geometry. Visible use promotes a prefetched group and records a hit.

Page residency does not immediately replace the streamed refinement's parent. A newly complete
group remains staged through the existing demand-aware settling window, with a bounded maximum hold
for continuous demand, and waits for its direct parent transition to settle. The child and complete
parent then remain drawable together for a 16-render-frame admission handoff.

The world and depth paths submit both complete opaque levels during steady projected-error overlap
and streamed admission. Normal depth testing retains the nearest available surface.
Scrapbot deliberately avoids complementary fragment discard because coarse and fine
simplifications can cover different pixels around thin photogrammetry and silhouettes; discarding
either side there creates cluster-shaped background holes. TAA marks transition fragments in the
internal HDR target and keeps compatible parent/child history across bounded depth changes.

Camera culling keeps a coarse parent submitted for the complete streamed-admission interval, even
when its newly resident child already satisfies the projected-error frontier. This keeps both
complete surfaces depth-testable until the handoff finishes instead of revealing the background
through child-shaped discard pixels. Native cluster shadows may select the hierarchy directly;
portable streamed shadows use the pinned coarse proxy described below.

Only completion makes the child logically replace its parent. Nested hierarchy transitions are
serialized. Activation requires every direct parent to be resident, active, and transition-complete,
and a transitioning child keeps its direct parent protected. This makes refinement
monotonic and prevents simultaneous hierarchy-level handoffs from exposing a missing surface.

Asynchronous CPU processing applies touches, deduplicates and prioritizes group requests. Imported
misses read exact Model-product byte ranges on a dedicated worker. Fixed outstanding-job and byte
ceilings prevent old camera demand from building an unbounded read queue. Completed payloads wait
inside a separate bounded staging budget, and stale unowned payloads are discarded. Versioned
completions admit or evict complete non-pinned groups under the project vertex-and-index payload
budget. Each feedback
batch builds one priority-ordered eviction plan. Lower-priority detail cannot displace a stronger
recent working set, and an admitted refinement protects every direct parent group that can replace
it. Eviction releases the child before its parents become eligible, so the exact resident coarse
frontier remains drawable. An active transition also blocks logical refinement completion until
its fixed handoff ends. A newly uploaded group begins its visible-use grace window in the
admission frame, rather than spending that protection while its older GPU request is still crossing
the asynchronous readback boundary.

Residency pressure does not modify the camera error target. Missing refinements retain their
resident parent, while group-atomic eviction releases lower-priority detail without breaking the
fallback chain. The coordinated frame-budget controller owns both render-scale and bounded
projected-error changes. Native indexed submission uses a one-pixel maximum-quality target.
Portable compact submission uses a measured two-pixel floor when virtual batches are active because
its padded vertex-pulling lanes have a different cost/quality crossover. Lower authored
adaptive-quality floors permit progressively coarser power-of-two tiers after render scale reaches
its floor.

Per-frame byte and group limits bound streaming work. One admitted group or complete-resource
preload becomes one combined arena transfer. Residency mutations use persistent group-to-cluster
and refinement-to-parent indices to patch only changed clusters and their direct dependents.
Adjacent changes coalesce into bounded GPU writes; stable frames do no page work.

At cache creation, every pinned terminal group remains resident as the correctness floor. Optional
camera-independent bootstrap detail may consume at most three quarters of the global residency
budget. The remainder is reserved for the first camera's exact demand so useful refinement does not
immediately evict bootstrap data and begin a residency churn loop.

All completed readbacks share those frame admission limits. After the group limit is spent, the CPU
still applies resident touches but skips missing-page and staging construction for nonresident
requests that cannot be admitted. Page assembly, feedback sorting, and metadata-patch scratch use
the frame temporary allocator, which WGPU reclaims before the next surface or offscreen frame.

Native multi-draw adapters submit the retained indexed-indirect command range for camera and
shadow work. Other capable adapters compact selected `{instance slot, cluster index}` records into
a bounded camera stream. Their first compute stage builds batch-local instance candidates; parallel
camera and shadow stages then process one hierarchy cluster per invocation. Separate bindings keep
each stage within WebGPU's guaranteed eight-storage-buffer compute limit. Compatible same-material
batches share four triangle-count record lanes. Each nonempty lane owns one non-indexed indirect
command, and the vertex shader pulls cluster indices and attributes from the shared geometry
arenas.

Fully resident portable resources reuse canonical indexed-indirect shadows. Streamed portable
resources prefer page-local compact shadows, using the same resident hierarchy frontier as camera
submission. This avoids redrawing a coarse photogrammetry proxy through every shadow cascade.

Cache creation still rebases the already-pinned root-page indices into one coarse indexed
compatibility proxy. It aliases the pinned vertex allocation and owns only its compact index range.
Portable shadows use that proxy when page-local compact shadows are unavailable. World and depth
submission also use it when capability, policy, or visibility-table capacity disables the detailed
path. Streamed Geometry therefore remains drawable at coarse detail without reconstructing or
retaining its complete canonical payload.

Classic and compact shadow culling have exclusive ownership of each batch's indirect command.
Compact cluster expansion is skipped globally when no batch needs it and rejected per batch when a
canonical or root-page indexed path is active. Stable frames perform no CPU readback, per-cluster
command generation, or geometry upload.

The nearest directional-shadow cascade refreshes every frame. The three farther layers retain their
stabilized projection and depth contents between staggered 2/4/8-frame updates, with no more than
one far layer updating alongside the near layer on an ordinary frame. A light activation, world or
batch-topology replacement, Transform mutation, camera discontinuity, or active-resolution change
forces all four layers current. Profile rows expose the refresh mask, per-cascade visibility
workload, and separate GPU timings so retained work is not mistaken for an empty pass.

The `virtual_geometry` camera view colors selected clusters by identity and hierarchy depth. Amber
marks a branch whose finer group is not completely resident; cyan marks a selected page that
arrived speculatively. Structured results report payload budget and residency, demand/prefetch
feedback, asynchronous reads/failures, page/group uploads, drawable group activations, active
admission transitions, prefetch hits/reclamation, evictions, deferred groups, selected clusters,
clusters currently inside either blend interval, and threshold rejections.

**Why:** Geometry detail must vary below object granularity without cracks, importer-specific draw
paths, or CPU decisions per cluster.

**Tradeoff:** Imported resources retain position proxies, hierarchy topology, page metadata, and
meshlet streams on the CPU. Procedural/runtime Geometry without a persistent product retains its
canonical arrays. Classic compatibility paths may perform one temporary page reconstruction when a
Geometry version enters the backend cache. Virtual WGPU vertex/index payloads are bounded.

The compact camera path trades additional GPU culling and vertex-pulling cost for portable,
bounded CPU submission. Portable shadows retain the canonical fast path when possible and use the
pinned coarse proxy under actual streaming pressure. Adapters without indirect-first-instance and
capacity-limited layouts retain classic indexed submission; streamed resources use their pinned
coarse proxy while complete resources keep their canonical or imported-LOD fallback.

Shared geometry buffers may grow beyond one device storage-binding range because indexed and
vertex-buffer submission can still address them. WGPU caps every storage binding at the reported
device limit and confines every portable compact page range to that addressable prefix. If
fragmentation prevents a legal admission, detail remains deferred and the resident coarse proxy
continues drawing; an unaddressable page is never exposed as resident.

Portable vertex pulling across multiple storage ranges still requires partitioned bindings or
page-relative offsets and remains tracked separately. Until then, the device binding limit is a
quality/residency ceiling for portable compact submission, not a correctness boundary.

### 24. Compose project shader hooks into an engine-owned render contract

**Decision:** Let projects provide `scrapbot_vertex` and `scrapbot_fragment` WGSL hooks while the backend owns entry points, resources, instance transport, render targets, and pass ordering.

Vertex hooks receive the object's model and normal matrices. Fragment hooks receive both viewport-local `screen_uv` and full-target `scene_uv`, plus helpers for guarded viewport sampling, conservative nearest-depth stabilization, device-to-view depth conversion, and roughness-filtered environment reflection. The reflection helper preserves the configured procedural atmosphere and its sun highlight when a project does not assign a reflection cubemap.

Blended hooks receive the opaque scene color/depth and render in a depth-tested, no-depth-write pass. This supports both conventional alpha blending and single-layer transmission shaders that return an already-composited result with alpha one.

**Why:** Projects need expressive surface and displacement effects without copying Scrapbot's backend ABI or turning the editor/example into a private renderer.

**Tradeoff:** The first portable path sorts transparent instances back-to-front on the CPU. Scene color is the opaque pre-water result, so intersecting transparent layers do not recursively refract one another. A bounded GPU sort for large transparent sets, imported glTF blending, structured compiler diagnostics, and displaced depth/shadow variants remain explicit follow-up work.

### 25. Generate reusable spectral surfaces for project shaders

**Decision:** Let a Shader resource opt into a renderer-owned 64×64 spectral surface. WGPU builds a deterministic Phillips wind spectrum, evolves its deep-water dispersion when the default ECS project clock advances, and performs horizontal and vertical inverse FFT passes entirely on the GPU.

Project hooks sample the periodic world-space field through `scrapbot_spectral_surface`. The helper
returns displacement, a reconstructed normal, and crest compression. A bounded `choppiness`
parameter converts the evolved height spectrum into frequency-domain horizontal orbital
displacement, producing the sharpened crests and broad troughs associated with Gerstner waves.

The engine owns bindings, allocation, and one cached field per Shader resource. The ECS `Time`
resource is the single time authority for project-shader helpers and spectral evolution, so paused
redraws retain the same field. Projects own how that data deforms or shades a surface. Shared
helpers convert world-space vectors and normals back into project-hook object space under arbitrary
entity transforms.

Shaders without the option bind a shared zero field and disabled uniform. They pay no FFT dispatch.
Multiple materials that reference one Shader share its field and dispatch at most once per ECS time
advance.

**Why:** Water, windblown terrain, and other broad stochastic surfaces need coherent low-frequency motion without copying backend bindings or compute orchestration into each project.

**Tradeoff:** The first field has fixed resolution and one frequency band. It does not yet provide
currents, interaction masks, caustics, underwater rendering, or water-aware motion vectors.

### 26. Choose geometry submission with a layered stable policy

**Decision:** Resolve `auto`, `conventional`, or `virtual` from the entity, Model resource, and
project in that order. Let WGPU's automatic policy select Virtual only for capable hierarchy-bearing
Geometry at or above its conservative 50,000-triangle crossover. Keep the result stable until
component membership, preference, resource version, or backend capability changes. See ADR-054.

**Why:** Virtual Geometry is a scalability tool for dense inputs, not a universally cheaper draw
path. Mixed scenes need local control without camera-motion-driven topology churn.

**Tradeoff:** Automatic selection begins with one portable threshold. Profiles expose the resolved
batch and instance mix, but qualified adapter-specific calibration remains future work.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-010, ADR-011, ADR-029, ADR-034, ADR-038, ADR-039, ADR-046, ADR-047, ADR-048, ADR-049, ADR-050, ADR-054, ADR-056
- **FDRs:** FDR-001, FDR-002, FDR-008

## Open Questions

- How should offscreen render output be compared once scene rendering exists?
- How long should the headful runtime loop live before the editor and game loop exist?
