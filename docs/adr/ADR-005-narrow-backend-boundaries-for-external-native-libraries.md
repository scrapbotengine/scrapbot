# ADR-005: Narrow Backend Boundaries for External Native Libraries

**Date:** 2026-07-01

## Context

Scrapbot will need external native libraries for some subsystems. Likely examples include graphics, windowing, audio, image decoding, font shaping, physics, and scripting runtimes. These libraries may be written in C, C++, Rust, or other languages, and may carry platform-specific build and packaging requirements.

If external library types and assumptions leak throughout the engine, dependency changes will become expensive and agentic code changes will be harder to keep correct.

## Decision

Scrapbot wraps external native libraries behind narrow, engine-owned backend boundaries.

External APIs may be used directly inside backend modules, but public engine systems expose Scrapbot-owned types, handles, diagnostics, and lifecycle rules. Backends are replaceable implementation details unless a future ADR explicitly promotes an external API to a public engine contract.

The initial headful rendering path follows this rule by using SDL3 only inside the renderer/window backend to create a native window and provide a platform surface to `wgpu-native`.

## Consequences

Core engine systems remain more stable when dependencies change. The codebase is easier to test with fake or headless backends.

Backend wrappers add some upfront work and may hide advanced library features until Scrapbot exposes them deliberately.

This decision also constrains quick prototypes: early code should still respect subsystem boundaries instead of letting external APIs spread through scene, asset, scripting, or UI code.
