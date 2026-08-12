# ADR-059: Route input from one physical frame

**Date:** 2026-08-12

## Context

ADR-035 established backend-neutral ECS input snapshots, but the editor still decoded shortcuts and polled held camera controls directly in SDL. Retained UI also reconstructed pointer edges from consecutive held values. Those parallel authorities could disagree after a world replacement, repeat a command while a key was held, or let the same physical interaction reach both editor chrome and the scene viewport.

## Decision

The platform boundary owns only device translation and operating-system services. Once per frame it maps SDL keys and pointer buttons into one `Input_Frame` with held, pressed, and released state. Text composition and repeated text-navigation commands travel beside that snapshot because they are focused text-editing data rather than gameplay button state. Relative mouse mode, cursor selection, confinement, and pointer warping remain platform services, but they do not define editor commands or independently decide which controls are held.

Engine-owned adapters derive semantic editor actions and UI pointer input from the committed physical snapshot. Shortcut precedence is resolved once: command-modified actions win over unmodified transform chords, while focused text controls and active modal tools remain downstream routing contexts. The initial editor action map is built in and non-persistent; project-defined actions, rebinding, controllers, and per-player routing must extend this layer rather than add another platform event path.

Retained UI treats the snapshot's pointer edges as authoritative. A press captures the topmost eligible control, reusable controls cancel propagation after their mechanics run, and release activates only the captured control when still eligible. Editor world tools and scene-camera navigation begin only when chrome, popups, or another modal owner has not claimed the interaction. Tests inject physical snapshots or semantic diagnostic actions without OS automation.

## Consequences

Every live consumer agrees about physical edges in a frame, command-modified shortcuts cannot also start unmodified Blender-style chords, and a held pointer cannot manufacture a new press after UI/world replacement. SDL remains replaceable because semantic editor policy lives above it. The engine still needs persistent project action maps, controller snapshots, rebinding, and explicit per-player routing.
