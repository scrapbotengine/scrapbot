# ADR-005: Use SDL3 for platform windows

**Date:** 2026-07-07

## Context

Scrapbot needs a cross-platform window and event layer before the first real renderer backend can present frames. Odin ships SDL3 bindings, and SDL3 is available in the current development environment.

## Decision

Use SDL3 as the first platform window layer for headful runtime smoke tests and future renderer surface creation.

## Consequences

SDL3 gives Scrapbot a portable path for macOS, Linux, and Windows window creation without writing native platform code first. It also pairs well with future WebGPU surface creation through Odin's `vendor:wgpu` SDL glue packages.

The engine now has an external runtime dependency for headful builds. Headless tests should continue to work without opening a window, and the SDL window path should remain isolated from ECS and scene code.
