# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-10-06

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend renders full indexed geometry with shared metallic-roughness GGX materials, mipmapped base-color/normal/occlusion/emissive images, a perspective camera, ambient/directional/point lighting, and optional scene-authored image-based environment lighting.
- The first directional light produces four stabilized, camera-relative shadow cascades. WGPU retains 2048×2048 capacity and, when adaptive quality is enabled, can rasterize a quantized 2048, 1024, or 512 square region from the same allocation and within the authored quality floor.
- Adaptive quality follows the camera's bounded 20-sample GPU-scene p95 after sustained pressure.
  It steps through world scale, shadow resolution, and post quality, waits between
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
- WGPU keeps a persistent slot-addressed GPU instance table, separates static source state from hot Transform state, and sends Transform-only changes through one dense update upload. The CPU full-record mirror advances with that compact stream so later selection/static uploads cannot regress model matrices or bounds. Nearby static slot changes coalesce into bounded uploads. Compact render/culling uniforms and instance-to-LOD batch mappings remain retained, camera and shadow frustum visibility compacts into batch slices, and indexed indirect draw arguments provide instance counts.
- The retained draw database grows geometrically past the original 64-batch limit. It rebuilds only when render membership, geometry LOD topology, or required capacity changes.
- Geometry uses complete indexed meshes and ordinary LODs. Import and registration do not build virtual hierarchies or page payloads. WGPU has one conventional submission path; existing geometry preferences cannot enable a second path.
- The active camera selects a backend-neutral debug view: lit output, material inputs, mapped world normals, logarithmic depth, exact GPU-selected LOD, object visibility diagnostics, one retained Hi-Z mip, or exact screen-space Hi-Z query footprints. Non-lit views skip presentation effects so diagnostics remain direct and stable.
- Hi-Z false color and texel boundaries expose the exact conservative max-depth hierarchy without readback or rebuilding it. Occlusion Queries records each tested rectangle, selected mip, bound depth, sampled farthest depth, identity, and visible/culled decision in a bounded GPU-native stream.
- The camera can freeze the latest valid occlusion-query records while that view remains selected. Freeze preserves only diagnostic records and their indirect draw count; ordinary culling continues from current safe Hi-Z state.
- Large stable scenes run a depth prepass, build a max-depth Hi-Z pyramid, and conservatively reject occluded bounding spheres from the following frame. Camera or persistent-instance changes disable stale-pyramid rejection. Camera motion instead uses a frustum-only coarse depth pass before refining visibility against a newly built current-camera pyramid. The pyramid pads non-power-of-two targets to power-of-two dimensions with far depth so mip reduction retains complete right and bottom edge coverage. Each query projects the eight corners of an enclosing cube and uses their nearest possible depth, so large off-axis clusters cannot be rejected from a center-only approximation. Camera-plane crossings and large near-field bounds remain visible rather than risking a false rejection.
- UUID-backed `scrapbot.geometry_lod` project resources declare generated icosphere levels and descending projected screen-radius thresholds. The GPU visibility pass selects the geometry batch; the CPU-reference path implements the same result.
- `--cpu-culling` runs the same conservative camera/shadow visibility contract on the CPU and uploads its compacted lists and counts; it is a compatibility and correctness-reference path, not the performance default.
- Structured run results distinguish retained draw batches from encoded draw submissions. They include shared geometry arena capacity, residency, uploads, bytes, and growths beside GPU-driven rendering, object visibility, Hi-Z, LOD, instance uploads, and optional per-pass timing counters. Visibility and timing use asynchronous readback rings and never synchronously stall the frame.
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

TAA jitters the projection with an eight-sample sequence bounded to a quarter pixel. Retained color/depth history lives on a stable output grid, so camera reprojection uses unjittered matrices and removes the current sample offset before reading history. A local 2×2 depth search avoids rejecting valid subpixel history at silhouettes, while YCoCg variance clipping limits stale color. Each 8×8 workgroup composes one shared 10×10 current-color tile, preserving the exact 3×3 clamp neighborhood without repeating its AO, indirect-diffuse, and SSR work for every tap. Resize, world replacement, depth replacement, camera cuts, TAA mode changes, and actual retained-instance changes reject surface and fog history. The instance rule favors a clean current frame over reprojecting stale moved geometry until object motion vectors exist. Culling stays unjittered.

Automatic exposure uses one 256-thread GPU workgroup to reduce viewport-stratified log-luminance samples and exponentially adapt a persistent clamped scalar. HDR history remains scene-linear. Bloom and final composition share the scalar, while manual camera exposure becomes compensation. There is no CPU readback.

Three optional singleton ECS components independently author vignette, ghost lens flares, and procedural lens dirt. Flares sample the bloom bright-pass into bounded chromatically separated ghosts plus a halo. Halo lookup preserves each output sample's radial distance instead of collapsing a complete center ray onto one bloom texel. Dirt modulates only bloom and flare energy, never the base scene. Adaptive post quality reduces the authored ghost count, and non-lit debug views bypass all three effects. Vignette is applied after tone mapping so its authored display-space framing remains independent of exposure.

The editor fly view inherits the project camera's render policy. WGPU consumes an asynchronous ordered pass-boundary span that ends after final composition and before native UI. One hysteretic controller selects world scale, directional-shadow resolution, and a normalized AO/SSR/fog quality factor from a deterministic reversible ladder. All changes share one measurement generation and cooldown. Adapters without timestamp queries use authored maxima. Target-size changes replace only size-dependent retained targets and reject temporal history. Disabled features skip their compute or history work. Tone map once into the native game viewport, then draw UI at native resolution. See ADR-052.
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
counts camera batches whose first object sets a fixed visibility bit. The bitset shares the existing counter buffer,
adding no storage binding, CPU scan, or readback path. Camera culling does not describe the
independently culled shadow cascades.

### 14. Use whole-object visibility

**Decision:** Keep GPU object culling and indexed indirect draws. Remove active meshlet and virtual-geometry submission. See ADR-062.

**Why:** One submission path reduces retained state, pipeline variants, and correctness boundaries.

### 15. Make render debug views part of the camera contract

**Decision:** Keep camera diagnostics for material inputs, normals, depth, ordinary LOD, Hi-Z, occlusion queries, and distance fields. Diagnostic rendering bypasses presentation effects.

**Why:** Projects, external tools, and framegrabs need the same view semantics.

**Tradeoff:** Retired meshlet and virtual-geometry debug-view names are rejected. Query diagnostics add GPU records and an overlay only while requested.

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

**Tradeoff:** GPU and CPU-reference submission retain each alternate Geometry/material combination as batch topology. Import recipes can tune or disable the LOD chain.

### 18. Suballocate Geometry versions from shared WGPU arenas

**Decision:** Store every cached Geometry version in aligned ranges of one shared vertex arena and
one shared index arena. Grow backing
buffers geometrically, coalesce released ranges, and reclaim stale handles
only at geometry-topology invalidation boundaries. Retire submitted ranges until a tagged
visibility readback proves their final GPU use complete. Use arena-global indirect offsets so
adjacent same-material commands can form one fixed multi-draw submission span. See ADR-048.

**Why:** Imported and generated geometry should share retained allocations without one buffer pair per mesh.

**Tradeoff:** Stable frames deliberately do not compact fragmentation. Backing-buffer growth copies
resident bytes and rebuilds dependent bindings at an explicit mutation boundary. Adapters without
indirect-first-instance share the memory arenas but retain single-batch submission semantics.

### 19. Retain conventional mesh products

**Decision:** Model v22 stores complete vertex attributes and triangle indices for each primitive and ordinary LOD. Loading retains these arrays in Geometry. GPU uploads and exact CPU queries consume the same data. Distance fields remain independently loaded.

**Why:** The engine no longer needs hierarchy reconstruction, page I/O, residency feedback, or refinement transitions. See ADR-062.

**Tradeoff:** Complete CPU meshes cost more memory than the former position-only catalogs. Whole-resource scene residency and ordinary LODs remain supported.

### 24. Compose project shader hooks into an engine-owned render contract

**Decision:** Let projects provide `scrapbot_vertex` and `scrapbot_fragment` WGSL hooks while the backend owns entry points, resources, instance transport, render targets, and pass ordering.

Vertex hooks receive the object's model and normal matrices. Fragment hooks receive viewport-local
`screen_uv`, full-target `scene_uv`, and guarded scene-sampling and reconstruction helpers.

The environment helper preserves the procedural atmosphere and sun highlight when no reflection
cubemap is assigned. The custom-surface reflection helper ray-marches from the actual fragment,
confirms front-to-back crossings against opaque depth, and returns hit confidence for environment
fallback. The shadow helper selects and cross-fades the engine's cascades so project-authored
lighting remains consistent with opaque world lighting.

Blended hooks receive the opaque scene color/depth and render in a depth-tested, no-depth-write pass. This supports both conventional alpha blending and single-layer transmission shaders that return an already-composited result with alpha one.

For temporal reprojection, WGPU evaluates the same vertex hook once in the current project-time
context and once against the previous project-time snapshot. The previous context also samples the
retained previous spectral field. The fragment writes the previous viewport position to a compact
custom-surface motion target, and TAA consumes it in preference to camera/depth reconstruction.
Redraws without a simulation advance evaluate both contexts from the same time and field, so pausing
does not invent deformation motion.

**Why:** Projects need expressive surface and displacement effects without copying Scrapbot's backend ABI or turning the editor/example into a private renderer.

**Tradeoff:** The first portable path sorts transparent instances back-to-front on the CPU. Scene
color is the opaque pre-water result, so intersecting transparent layers do not recursively refract
one another. Custom-surface SSR sees only current-frame, on-screen opaque geometry and uses a bounded
20-step march; it cannot recover off-screen or transparent reflectors.

Previous hook evaluation tracks engine project time and spectral fields, but arbitrary project
parameter changes and object transforms do not yet retain their previous values. A bounded GPU sort,
imported glTF blending, structured compiler diagnostics, displaced depth/shadow variants, and
general per-object motion remain explicit follow-up work.

### 25. Generate reusable spectral surfaces for project shaders

**Decision:** Let a Shader resource opt into a renderer-owned one-to-three-band 64×64 spectral
surface. WGPU builds deterministic frequency-partitioned Phillips wind spectra, evolves deep-water
dispersion when the default ECS project clock advances, and performs horizontal and vertical inverse
FFT passes entirely on the GPU. Later bands shrink patch width and scale energy geometrically;
adjacent wavelength windows cross-fade so cascades add detail without double-counting energy.

Project hooks sample the periodic world-space field through `scrapbot_spectral_surface`. The helper
returns displacement, a reconstructed normal, crest compression, and retained foam history. A bounded `choppiness`
parameter converts the evolved height spectrum into frequency-domain horizontal orbital
displacement, producing the sharpened crests and broad troughs associated with Gerstner waves.
Spatial finalization deposits foam where the horizontal-displacement Jacobian is sufficiently
compressed. It semi-Lagrangian-backtraces the retained previous field through the authored
world-XZ foam-advection velocity, bilinearly samples that history, and exponentially decays it.
Generation, decay, coverage, and advection remain Shader-resource controls.

Transparent hooks receive two deliberately separate opaque-depth contracts. Conservative
`scrapbot_scene_stable_uv` sampling may select the nearest cross-neighbor to keep refraction from
magnifying subpixel coverage holes. Metric shoreline effects instead use
`scrapbot_water_column_depth`, which reconstructs the opaque receiver on the fragment's center ray
and projects the separation onto the supplied surface normal. A refraction-stability heuristic
therefore cannot dilate object silhouettes into world-space foam bands.

The engine owns bindings, allocation, and one cached field per Shader resource. The ECS `Time`
resource is the single time authority for project-shader helpers and spectral evolution, so paused
redraws retain the same field. Projects own how that data deforms or shades a surface. Shared
helpers convert world-space vectors and normals back into project-hook object space under arbitrary
entity transforms.

Shaders without the option bind a shared zero field and disabled uniform. They pay no FFT dispatch.
Multiple materials that reference one Shader share its field and dispatch at most once per ECS time
advance.

**Why:** Water, windblown terrain, and other broad stochastic surfaces need coherent low-frequency motion without copying backend bindings or compute orchestration into each project.

**Tradeoff:** Each band retains a fixed 64×64 resolution. Foam advection is one uniform world-space
velocity rather than a spatial current map, and the field does not yet provide interaction or
shoreline masks. Future shoreline work must use water-body depth/shape or bounded authored water
influences for simulation attenuation, foam, currents, and deformation. Unsigned distance to
arbitrary scene Geometry is not a shoreline signal: seabeds, props, undersides, and open scan shells
are all valid nearest surfaces and can incorrectly saturate complete water regions. A separate
public `scrapbot.water_volume` owns
camera-medium selection and underwater composition: resolved Transform height defines the mean
horizontal surface, bounds plus a conservative displacement limit select candidates, and priority
resolves overlap. For a Water Volume entity rendered by a custom Shader, WGPU evaluates the same
`scrapbot_vertex` hook at the camera X/Z position and iteratively inverts horizontal displacement.
The resulting animated crest/trough height drives submersion, analytic surface exit, air-fog
replacement, camera-depth attenuation, caustic depth, and crossing-history rejection without CPU
readback. The CPU mean-plane test is only a conservative candidate broad phase, never the medium
classifier. Mean-plane fallback
remains available when no queryable custom surface exists. WGPU applies Beer–Lambert
absorption/scattering after transparents and before TAA. When the camera is submerged, the post pass also projects
the primary directional light onto opaque receivers through an animated multi-band refracted-ray
mapping. Its finite-difference Jacobian supplies light concentration; receiver angle, cascaded
shadows, footprint, water-column extinction, and authored maximum depth bound the result. Project
shaders can independently build
screen-space caustics from public scene-depth, shadow, and world-reconstruction helpers, but the
spectral resource does not own a general caustics contract.

### 26. Retire layered geometry policy

All current project, resource, and entity preferences resolve to conventional indexed submission. Legacy configuration, telemetry, shader declarations, and diagnostic helpers remain migration residue tracked in docs/TODO.md; they are not an alternate renderer.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-010, ADR-011, ADR-029, ADR-034, ADR-038, ADR-039, ADR-046, ADR-047, ADR-048, ADR-049, ADR-050, ADR-054, ADR-056, ADR-062
- **FDRs:** FDR-001, FDR-002, FDR-008

## Open Questions

- How should offscreen render output be compared once scene rendering exists?
- How long should the headful runtime loop live before the editor and game loop exist?
