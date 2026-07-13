# ADR-007: Use ID-keyed component storage

**Date:** 2026-07-11

## Context

Scrapbot's early Luau ECS bridge stored project components in one flat world array and selected query results by comparing component names. That was enough to prove scene-defined script components and deferred lifecycle commands, but it does not scale toward bulk queries, native systems, or parallel scheduling. Component names should remain useful for project files and diagnostics, while runtime iteration needs a cheaper and more stable key.

## Decision

Assign each registered component definition a stable runtime component ID. Keep scene files and script declarations name-based, then bind loaded world component storage to registry IDs after scripts register their component schemas. Store project custom components grouped by component type, keyed by component ID once bound, with the component name retained for validation and diagnostics.

Luau component handles expose both `name` and `id`, including built-in engine handles exposed through the `scrapbot` API. Systems may still declare access by handle or registered component name, but runtime queries and deferred project-component mutations use the component ID to find the matching storage group.

## Consequences

Single-component queries no longer need to scan every project component instance and compare names. Joined queries can combine ID-keyed project component groups with built-in engine component presence checks, giving the runtime a clearer component-type boundary for bulk query views, native systems, and parallel scheduling.

Scene loading still works before script registration because names remain the text-first interchange format. The cost is an extra binding step after Luau schemas are loaded, and component IDs are runtime-local rather than serialized identities.
