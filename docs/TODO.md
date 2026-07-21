# TODO

This file tracks current actionable engineering work. The broad product roadmap lives in [`README.md`](../README.md), detailed decisions live in ADRs and FDRs, and completed work lives in Git history.

## Rendering

- [ ] Add imported mesh LODs and evaluate meshlets and richer submission against representative scenes.
- [ ] Expose camera exposure and bloom threshold, intensity, and scatter as project settings.
- [ ] Add clustered or otherwise scalable lighting beyond the initial fixed light limits.
- [ ] Add Hi-Z, visibility, and LOD debug views.
- [ ] Add deterministic visual comparison for offscreen render output.

## ECS UI

- [ ] Emit reusable button activation and other UI command events.
- [ ] Add virtualized reusable list/tree views with filtering for large data sets.
- [ ] Add canvas scaling and richer sizing and alignment policies.

## Project Runtime And Scripting

- [ ] Replace the narrow TOML reader or formally specify its supported project-file subset.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [ ] Add target-native Luau, SDL3, and WGPU toolchains for cross-platform exports.
- [ ] Expose textured materials through the project-local Odin extension API.

## Editor

- [ ] Add an opt-in runtime-entity browser policy on top of bounded, virtualized list rows.
- [ ] Add specialized enum, color, and entity-reference inspectors, followed by array and nested-value editing.
- [ ] Add searchable scene, resource, component, and system browsers.
- [ ] Add transform snapping and multi-selection editing.
- [ ] Add a scalable picking broad phase or GPU identity pass before exact triangle tests.

## Testing And Diagnostics

- [ ] Apply a baseline `odinfmt` pass and promote formatting audit into the default test gate.
- [ ] Add OS resident-memory sampling for foreign-library and GPU allocations.
- [ ] Add persisted benchmark trend reporting for representative simulation, editor, and rendering workloads (the local optimization-profile runner now covers bounded simulation comparisons).
