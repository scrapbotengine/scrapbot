# ADR-020: Transient ECS Input Resources

**Date:** 2026-07-03

## Context

Scrapbot receives keyboard and mouse input from SDL in headful runs. Early UI/editor code passed that state through a host-side `FrameInput` struct, while render ECS systems also stored a smaller render-internal input component. That split made it easy for consumers to lose fields such as mouse wheel deltas and created pressure for UI-specific input side channels.

Input needs to serve game systems, editor systems, UI interaction, and render systems. It should therefore follow the same ECS model as the rest of the engine instead of becoming a separate immediate-mode service.

## Decision

Scrapbot represents current-frame host input as transient engine-owned ECS components on the shared `scrapbot.input.frame` entity:

- `scrapbot.input.pointer` stores pointer position, pointer delta, primary and secondary button edge/held state, and wheel delta.
- `scrapbot.input.keyboard` stores modifier state, semantic movement key state, and editor-toggle edge state.
- `scrapbot.input.frame` stores frame-level UI visibility and viewport data.

SDL and other future platform backends translate raw events into the host-side frame snapshot. The live project writes a routed version of that snapshot into the game world before UI command routing and update systems run. The renderer writes the same shape into its internal render world before render systems run.

UI and editor interaction should consume these ECS resources where they run inside a world. Host-only editor chrome may still use the host snapshot before it writes routed input back to the world.

## Consequences

- UI interaction, script systems, native systems, and render systems can converge on one input representation.
- Mouse wheel and future pointer fields are less likely to be dropped by a render-only bridge.
- Input resources are runtime-owned transient data and should not be authored in scene files.
- Controller/gamepad support can add more `scrapbot.input.*` components without changing the basic model.
- The first keyboard representation is intentionally small and exposes movement-oriented keys rather than a full raw key table. Full key state, text input, focus, capture, action mapping, and controller devices remain future design work.
