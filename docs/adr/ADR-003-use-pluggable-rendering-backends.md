# ADR-003: Use pluggable rendering backends

**Date:** 2026-07-07

## Context

Scrapbot targets 3D games on macOS, Linux, and Windows. Rendering should be able to start with a pragmatic backend while leaving space for offscreen verification, editor viewports, and future backend experiments.

## Decision

Keep rendering behind an internal backend boundary. Start with a null renderer in the runtime skeleton, then add `wgpu-native` as the first real backend.

## Consequences

Engine code can load projects, build ECS worlds, and produce renderable frame data before a GPU backend exists. The first real backend can focus on WebGPU concepts while the rest of the runtime stays insulated from backend-specific handles.

The renderer boundary must stay intentional. ECS code should not casually own GPU resources, and backend-specific details should not leak into scene files or project scripts unless they become stable engine concepts.
