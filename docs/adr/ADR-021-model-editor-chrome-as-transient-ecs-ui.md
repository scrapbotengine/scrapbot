# ADR-021: Model editor chrome as transient ECS UI

**Date:** 2026-07-14

## Context

ADR-015 kept editor chrome outside the ECS to isolate tool lifecycle from project content. That separation also created a second layout, interaction, scrolling, and painting implementation. Scrapbot's ECS UI is now capable of responsive fill stacks, draggable separators, smooth clipped scroll areas, text, and buttons, so maintaining a parallel editor-only widget system would weaken the ECS UI's role and duplicate behavior.

Editor UI still must not be serialized as project data, exposed as ordinary scene content, or confused with entities the user is inspecting.

## Decision

Build the editor shell from transient entities in the running world. Mark them with `.Editor` origin, attach the same `UILayout`, `UIHStack`, `UIVStack`, `UIScrollArea`, `UIText`, and `UIButton` components used by project UI, and reconcile them through the shared retained UI system.

Attach an internal `Editor_UI_Component` to editor widgets that need tool semantics, such as the project viewport, browser rows, inspector content, and status text. This binding identifies roles and entity targets without placing tool behavior in generic UI components.

Keep project and editor UI in separate coordinate and interaction domains during reconciliation. Project UI lays out inside the live project viewport; editor UI lays out across the full window and paints afterward. Editor entities remain transient across scene data and use engine-controlled construction and refresh cadence.

Exclude every `.Editor` entity from the scene browser and reject it as an inspector selection target. Scene-authored entities remain normal text and runtime-spawned entities use muted text.

This decision supersedes ADR-015's ownership model while preserving its viewport and paint-order separation.

## Consequences

The editor proves and exercises the same box, hidden-subtree, SDF-border, stack, split, scroll, text, button, hover, and active behavior available to projects. Pooled widgets remain alive and toggle layout visibility rather than entering the gameplay entity recycler. Fixes to the shared UI system benefit both surfaces, and the separate hand-painted editor widget path is removed.

The runtime world contains additional transient editor entities, so systems that report or expose project content must filter by origin when appropriate. Internal role components and the renderer's project/editor domains remain engine implementation details. Inspector controls and their runtime command history now follow ADR-022; persisted workspace layout and scene edits remain future work.
