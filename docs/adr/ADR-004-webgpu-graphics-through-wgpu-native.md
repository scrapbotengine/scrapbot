# ADR-004: WebGPU Graphics Through wgpu-native

**Date:** 2026-07-01

**Migration note:** The language-specific Zig binding details are superseded by [ADR-023](ADR-023-odin-as-engine-implementation-language.md). Scrapbot still uses `wgpu-native`, but the target renderer binding is Odin through the C ABI.

**Odin migration note:** The first Odin migration slices own the render-relevant `wgpu-native` C ABI scalar types, string/chained structs, texture formats, buffer/texture usage flags, initial texture/buffer descriptor structs, instance/adapter/device/queue request descriptors, bind-group/sampler/pipeline-layout descriptors, shader module and render pipeline descriptors, render pass attachment/descriptors, offscreen copy/readback, queue upload, surface creation/configuration/current-texture/presentation, and render pass command procedure boundaries, offscreen proc-table resolver, dynamic-library-backed offscreen proc loader, default `odin-out/lib`/environment library discovery with `zig-pkg` as a migration fallback, `wgpu-check` diagnostics, instance creation/release smoke, adapter/device/queue context smoke, native `wgpuDevicePoll`, a real offscreen clear/readback smoke, a real WGSL pipeline draw/readback smoke, a tiny WebGPU PNG/BMP artifact command, first-pass scene-driven `render --backend wgpu` image output, bounded hidden `run --backend wgpu` final-frame output, SDL native surface descriptor extraction, hidden SDL WebGPU surface presentation smoke coverage, bounded hidden and bounded/unbounded visible `run --backend wgpu` scene surface presentation, first-pass WebGPU editor chrome overlay vertices for render/run surfaces, direct host `wgpu-native` library staging for Odin WebGPU smoke tasks, and bounded/unbounded visible software SDL event loops. They can load a compatible dynamic library, acquire/release a first WebGPU context, submit tiny offscreen clear and triangle draw passes, map a staging buffer, validate readback pixels, write a 1x1 offscreen triangle image through `scrapbot wgpu-render-test`, render scene-derived placeholder rectangles and first-pass editor chrome overlays through WebGPU for `render`/`render-test`/bounded hidden `run`, create an SDL window with a platform-native surface descriptor, configure a compatible WebGPU surface, acquire the current surface texture, submit a clear or scene-derived render pass, present hidden frames through `scrapbot wgpu-surface-check`, bounded hidden `scrapbot run --backend wgpu`, and bounded/unbounded visible `scrapbot run --backend wgpu`, and drive visible software runs through SDL event polling, but do not yet support visible software pixel presentation or replace the full Zig WebGPU renderer.

## Context

Scrapbot needs a cross-platform graphics foundation without directly owning Vulkan, Metal, Direct3D, and OpenGL backends at the start of the project. A direct backend strategy would consume too much early engineering effort before the engine has proven its runtime, project model, scripting, and editor architecture.

`wgpu-native` provides a native WebGPU implementation based on `wgpu-core` and exposes C headers and native libraries. This allows a Zig engine to use a modern cross-platform graphics API through a C ABI boundary without making Rust the engine implementation language.

## Decision

Scrapbot uses WebGPU for its initial rendering abstraction and accesses it through `wgpu-native`.

The engine owns a Zig renderer backend wrapper around `wgpu-native`. Application, scene, UI, and asset systems depend on Scrapbot renderer concepts, not directly on `wgpu-native` types.

The initial integration uses a vendored Zig binding package for `wgpu-native`, patched for the repository's current Zig toolchain. This binding remains an implementation detail of the renderer module.

## Consequences

Scrapbot can build a renderer on a modern cross-platform graphics model while avoiding direct backend implementation work.

The project takes on native dependency packaging, version pinning, header translation, platform library loading, and wrapper maintenance. `wgpu-native` release changes may require binding and build updates.

Keeping `wgpu-native` behind an engine-owned wrapper preserves the option to switch to another WebGPU implementation, use platform-native backends later, or experiment with alternative graphics toolkits.

Vendoring the Zig binding makes local compatibility patches auditable, but it creates maintenance work when either Zig or `wgpu-native` changes.
