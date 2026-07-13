# ADR-015: Keep editor chrome engine-owned

**Date:** 2026-07-13

## Context

Scrapbot projects need to remain playable while exposing editing tools in the same runtime window. Project-authored ECS UI is part of the game and may be reloaded or replaced with the project world, so using it to own editor chrome would mix tool lifecycle with game state and allow project content to obscure or serialize engine tools.

## Decision

Keep editor visibility and chrome in engine-owned retained UI state outside the project ECS. `Ctrl+Esc` toggles that state during a visible run, while the `--editor` run option starts it visible for automation and framegrabs.

When visible, the renderer gives world rendering and project UI the complete central project viewport. Project UI and editor chrome use separate draw ranges in a dedicated overlay render pass: project UI is transformed and clipped to the project viewport, while editor chrome uses full-window coordinates and renders afterward.

## Consequences

The running game remains live and isolated from editor ownership, and future inspectors can survive scene reloads without becoming project entities. Rendering gains explicit world, project-UI, and editor-chrome regions. Resizable panel layout, persisted workspace state, and editor-to-project commands remain future work.
