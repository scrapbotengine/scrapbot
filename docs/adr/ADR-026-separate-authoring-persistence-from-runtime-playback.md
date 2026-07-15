# ADR-026: Separate authoring persistence from runtime playback

**Date:** 2026-07-15

## Context

Scrapbot's editor inspects and manipulates the same ECS world used for project playback. That makes live feedback immediate, but it also makes runtime simulation changes, scene-authoring changes, and source persistence easy to confuse. Persisting the world continuously would capture transient entities and system-driven mutations, while treating every editor edit as disposable would prevent the editor from becoming an authoring tool.

Scene entities already have stable project-wide UUIDs and explicit origin metadata, which provide the identity and provenance required to distinguish authored entities from runtime-spawned and editor-owned entities.

## Decision

Scrapbot uses explicit playback states to define the persistence boundary:

- Stopped is authoring mode. Supported inspector and gizmo edits to scene-origin entities mark the scene dirty.
- Running and paused operate on runtime state. Changes made there are not candidates for scene persistence.
- Save is an explicit action available for dirty stopped scenes. Completed authoring transactions provide a set of candidate entity UUIDs; Save semantically compares those entities with the parsed authored baseline and writes only differing supported component values. It preserves unrelated source text and comments and atomically replaces the file.
- Runtime-spawned and editor-owned entities are never written by Save. A future explicit promotion workflow may turn a runtime entity into authored scene data.
- Play and Step do not start while stopped authoring changes are unsaved. The user must Save or Stop first.
- Stop discards unsaved and runtime changes by replacing the world from the scene file. It retains loaded Luau and Odin code, registered systems, and render resources.

## Consequences

The editor has a predictable model: Save commits authored state, while Stop restores the last saved scene without paying the cost of reloading code. Stable UUID lookup makes duplicate entity names safe and keeps persistence independent of list order in the live world. Semantic comparison prevents unchanged floating-point values and reverted edits from churning source text. Atomic replacement prevents a failed write from leaving a partially written scene.

The initial persistence layer supports the component fields currently editable by the inspector and gizmo rather than arbitrary structural changes. Adding/removing entities and components, promoting runtime entities, saving while playing, and maintaining separate authoring and playback worlds remain future work. Because the editor currently uses one world, unsaved stopped changes must block Play and Step to avoid silently changing their meaning.
