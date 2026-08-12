# ADR-058: Identify scenes by UUID and replace worlds transactionally

**Date:** 2026-08-12

## Context

Scenes need stable identity independent of their editable names and paths. Runtime scene changes must also avoid exposing a partially parsed world, invalid resource references, or a mixture of entities from two replace-style scenes. Because Scrapbot is a game engine, repeated transitions must have a bounded ownership model rather than retaining every previously visited world or duplicating project-wide resources.

## Decision

Treat every authored `scenes/**/*.scene.toml` file as a project scene asset with a unique non-zero UUID. `project.toml` selects its startup scene by UUID. Names and relative source paths remain editable metadata rather than reference identity.

Replace-style scene changes are queued by UUID and committed only after scheduled systems and their deferred ECS commands finish. The runtime parses and validates a candidate scene, builds its ECS world, resolves references against the existing project-wide resource registry, and captures its playback baseline before changing active ownership. Failure destroys the candidate and retains the current scene. Success destroys the previous world immediately, installs the candidate, and rebinds world-dependent runtime and editor state.

The runtime owns one active scene and one project-wide resource registry. Scene discovery metadata is compact and does not contain entity payloads. During a transition, only the active world and one candidate world may coexist. Runtime resource handles and imported products are reused rather than cloned for every scene.

## Consequences

Scene paths and display names can change without breaking startup configuration or runtime requests. Failed transitions are non-destructive, repeated transitions do not accumulate ECS worlds, and resource-heavy projects do not multiply registry ownership per scene. Candidate construction temporarily raises ECS memory to the sum of the current and next worlds, and the current implementation performs that work synchronously at the frame boundary. Asynchronous preparation, dependency-aware resource residency, additive worlds, and persistent cross-scene layers remain separate future capabilities.
