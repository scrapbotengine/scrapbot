# ADR-019: Model the editor scene camera as a transient ECS entity

**Date:** 2026-07-13

## Context

The editor needs a navigable scene view that can move independently of the running project's camera. Keeping that camera as unrelated renderer state would make its transform and settings invisible to the ECS and inspector, while reusing the project camera would let editor navigation mutate game state.

## Decision

Create the editor scene camera as a transient, engine-owned ECS entity when the editor first opens. Give it Transform, Camera, and `EditorSceneCamera` components, initialize it from the project's active camera when available, and retain it for the rest of the run so toggling the editor preserves the viewpoint. The renderer selects it only while editor chrome is visible.

Run fly navigation as a dedicated editor system over the `EditorSceneCamera` component. Right mouse capture inside the live viewport gates relative pointer input and WASD, Space, and Ctrl movement. Camera transforms use Euler rotation to derive forward, right, and up consistently for rendering, picking, and gizmo projection.

The entity is editor-origin runtime state: it is inspectable but is not serialized into scene TOML, exposed through project Luau/native APIs, or treated as the project's gameplay camera.

## Consequences

Editor navigation remains ECS-visible and isolated from game camera state, and all camera-dependent tools agree after the view rotates. Editor entity counts and inspection now include engine-owned entities as a distinct provenance. Relative mouse capture must be released whenever fly mode or the editor closes. Camera persistence, bookmarks, speed controls, and focus-selection navigation remain future work.
