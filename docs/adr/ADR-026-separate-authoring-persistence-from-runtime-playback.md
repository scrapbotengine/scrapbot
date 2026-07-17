# ADR-026: Separate authoring persistence from runtime playback

**Date:** 2026-07-15

## Context

Scrapbot's editor inspects and manipulates the same ECS world used for project playback. That makes live feedback immediate, but it also makes runtime simulation changes, scene-authoring changes, and source persistence easy to confuse. Persisting the world continuously would capture transient entities and system-driven mutations, while treating every editor edit as disposable would prevent the editor from becoming an authoring tool.

Scene entities already have stable project-wide UUIDs and explicit origin metadata, which provide the identity and provenance required to distinguish authored entities from runtime-spawned and editor-owned entities.

## Decision

Scrapbot uses explicit playback states to define the persistence boundary:

- Stopped is authoring mode. Supported inspector and gizmo edits to scene-origin entities mark the scene dirty.
- Running and paused operate on runtime state. Changes made there are not candidates for scene persistence.
- Save is an explicit action available for dirty stopped projects. Completed authoring transactions provide candidate entity and resource UUIDs; Save semantically compares scene entities with the parsed authored baseline, writes only differing supported component values, prepares dirty resources, and commits the complete file set through the recoverable transaction in ADR-031. It preserves unrelated scene source text and comments.
- Runtime-spawned and editor-owned entities are never written by Save implicitly. A stopped-mode Keep action can explicitly promote a runtime entity into authored scene data.
- Play and Step capture the current in-memory authoring world, including unsaved changes, before project simulation advances.
- Stop discards playback mutations and runtime-spawned entities by restoring that in-memory authoring baseline. It preserves unsaved authored entities, dirty candidates, undo history, and UUID selection while retaining loaded Luau and Odin code, registered systems, and render resources.
- Revert is a separate explicit destructive operation rather than an implicit meaning of Stop. While stopped and dirty, it reloads scene entities from disk without reloading Luau, Odin, registered systems, or render resources, then clears authoring history and dirty state.

## Consequences

The editor has a predictable model: Save commits authored state to disk, while Stop returns from disposable playback to the exact authoring state that Play captured. Stable UUID lookup makes duplicate entity names safe, restores selection even when runtime slots change, and keeps persistence independent of list order in the live world. Semantic comparison prevents unchanged floating-point values and reverted edits from churning source text. The project transaction prevents a failed multi-file Save from exposing a partially updated authored state.

Persistence supports value and structural entity/component transactions. Structurally dirty entity blocks are normalized while unrelated blocks remain untouched. The history remembers its last successful Save position, so undoing or redoing back to that position clears dirty state; branching away from an unreachable saved position remains dirty. Revert intentionally discards the complete history. Saving while playing and maintaining concurrent authoring and playback worlds remain future work. The current single-world implementation owns a complete scene-origin playback baseline and restores it at Stop, avoiding a second code runtime or render-resource set while preserving authoring state.
