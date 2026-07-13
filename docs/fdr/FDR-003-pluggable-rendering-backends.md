# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-07-13

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend renders full indexed geometry with shared base-color and PNG-textured materials, a perspective camera, and ambient, directional, and point lighting.
- The first directional light produces a fixed-resolution shadow map. Only entities with `ShadowCaster` contribute depth, and only entities with `ShadowReceiver` sample it.
- Lights are ECS components extracted into a bounded backend-neutral frame packet: accumulated ambient light, four directional lights, and sixteen point lights.
- Base colors are decoded to linear space before lighting, high-dynamic-range light accumulation is tone mapped, and WGPU renders to an sRGB target.
- Eligible entities receive internal render-instance components automatically.
- Shared geometry/material pairs use one instanced draw batch, and geometry and material texture uploads are cached by handle and version.
- The `wgpu` backend can also render a headless final-frame PNG with `--framegrab`.
- WGPU sizes the live world and project UI to the complete available viewport, deriving camera aspect from its dimensions, then paints engine chrome in a separate overlay pass.
- The `wgpu` backend currently requires `--window` or `--framegrab`.
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
**Tradeoff:** Headful runtime work now depends on SDL3 being available in development and distribution environments.

### 4. Render full indexed geometry

**Decision:** WGPU consumes position/normal/UV vertices with `u32` triangle indices and shared base-color or PNG-textured materials. Cube and plane helpers generate the same representation.
**Why:** Procedural, custom, and future imported geometry should follow one rendering path.
**Tradeoff:** The canonical vertex format and simple Lambert material model still need to grow toward physically based shading, mipmaps, and richer texture channels.

### 5. Keep headless framegrabs on the same render path

**Decision:** Headless WGPU renders the same ECS cube pipeline into an offscreen texture, reads the final frame back to CPU memory, and writes a PNG.
**Why:** This gives agents and tests a visual artifact that exercises the same scene-driven renderer path as the windowed backend.
**Tradeoff:** On macOS, the current implementation creates a hidden SDL3 window for Metal adapter bootstrap even though the captured frame is rendered offscreen.

### 6. Use ECS renderable queries as the first backend boundary

**Decision:** Engine reconciliation derives internal render-instance components from valid transform, geometry, and material references. ECS builds a short-lived render list from that state.
**Why:** Backends need coherent scene instances, not just global component counts, and this keeps GPU code out of ECS storage.
**Tradeoff:** Reconciliation currently scans entities linearly, and the first uniform layout caps a frame at 64 instances.

### 7. Share geometry and material resources by handle

**Decision:** Keep full geometry and material descriptions outside entity storage and let ECS components reference them with generational handles, as established by ADR-010. Primitive helpers produce ordinary indexed geometry rather than backend-specific primitive markers.
**Why:** Many entities should share one CPU description and one backend GPU allocation without putting GPU ownership into the ECS.
**Tradeoff:** Rendering needs an explicit reconciliation step, resource validation, and backend cache invalidation when named geometry is replaced.

The built-in indexed primitive generators cover cubes, planes, icospheres, UV spheres, square pyramids, and capped cylinders. Curved primitives expose bounded tessellation controls so projects can choose an appropriate geometry cost.

### 8. Extract ECS lights into a bounded frame packet

**Decision:** Ambient, directional, and point lights are public ECS components. ECS extraction accumulates ambient light and copies up to four directional and sixteen point lights into each render list, following ADR-011.
**Why:** Lights remain scriptable scene state without exposing ECS storage to renderer backends, and fixed limits keep the first uniform layout predictable.
**Tradeoff:** Excess lights are ignored in entity order until a future light-selection or clustered-lighting path replaces the fixed packet.

### 9. Accumulate lighting in linear space and tone map the result

**Decision:** Treat authored material colors as sRGB, decode them before lighting, apply an ACES-style curve to the HDR result, and prefer sRGB render targets for presentation and framegrabs.
**Why:** Directly adding strong light contributions to display-space colors clips channels independently, washes out saturated lights, and produces inconsistent output across UNORM and sRGB targets.
**Tradeoff:** The first shader uses fixed exposure and a compact approximation rather than a configurable camera exposure and complete color-management pipeline.

### 10. Make shadow participation explicit

**Decision:** Expose separate engine-provided shadow caster and receiver marker components and render one shadow map from the first directional light.
**Why:** Projects should control shadow cost and semantics independently for occluders and shaded surfaces without coupling them to geometry or material ownership.
**Tradeoff:** The initial fixed orthographic shadow volume and single map do not cover point lights, multiple shadowed directional lights, cascades, or large scenes.

## Related

- **ADRs:** ADR-003, ADR-005, ADR-010, ADR-011
- **FDRs:** FDR-001, FDR-002, FDR-008

### 11. Keep decoded images in resource ownership and GPU objects in the backend

**Decision:** Material resources own decoded RGBA pixels and dimensions, while WGPU lazily creates versioned textures and bind groups.
**Why:** Project validation can decode assets without a GPU, hot reload can replace a named material while preserving handles, and renderer-specific objects stay out of ECS and shared resources.
**Tradeoff:** The first slice retains decoded pixels after upload and has no streaming, compression, mipmap generation, or memory budget.

## Open Questions

- How should the render packet evolve for richer texture channels, cascaded shadows, and culling?
- How should offscreen render output be compared once scene rendering exists?
- How long should the headful runtime loop live before the editor and game loop exist?
