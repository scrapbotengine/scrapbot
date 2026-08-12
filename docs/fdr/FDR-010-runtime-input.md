# FDR-010: Runtime input

**Status:** Active
**Last reviewed:** 2026-08-12

## Overview

Scrapbot exposes backend-neutral keyboard and pointer state to Luau and native Odin systems through engine-owned ECS singleton components.

## Behavior

- The platform snapshot is committed once before project systems execute.
- `scrapbot.keyboard_input` and `scrapbot.pointer_input` are derived, read-only singleton components used in system access declarations; they are not entity query terms.
- Keyboard queries distinguish held, pressed-this-frame, and released-this-frame states using stable lowercase physical key names.
- Pointer queries expose availability, editor capture, pixel position, per-frame pixel delta, wheel delta, and held/pressed/released button state.
- Visible SDL windows provide input. Null and hidden headless runs publish unavailable zero snapshots.
- Luau uses `scrapbot.input`; native extensions use `input_key_state` and `input_pointer` helpers on the system context.
- Tests can inject a complete frame snapshot without opening a window.
- UI pointer edges and editor camera controls derive from that same snapshot. SDL retains only text composition, repeated text navigation, and OS cursor/capture services beside it.
- Engine-owned semantic editor actions resolve shortcut precedence above the platform boundary. Retained UI captures the topmost pressed control and publishes activation only on release over that same control.

## Design decisions

### Use ECS singleton resources

Input is global to one running World, so one component value per World is more honest than a synthetic scene entity. Registry identity and declared access preserve ECS scheduling and tooling semantics without disturbing entity identity or persistence.

### Publish snapshots, not callbacks

Systems may execute in scheduled batches and Luau/native code must see identical state. Immutable frame snapshots avoid callback lifetime, ordering, and thread-affinity hazards.

### Keep platform names out of public APIs

SDL scancodes map to Scrapbot key names at the platform boundary. Project code and the native ABI do not depend on SDL numeric values.

### Resolve actions and interaction ownership above devices

The physical frame is evidence, not policy. Engine adapters interpret editor shortcuts, while focus, modal tools, retained pointer capture, and propagation determine which consumer owns an interaction. Command-modified actions are resolved before unmodified transform chords.

## Related

- **ADRs:** ADR-005, ADR-008, ADR-009, ADR-035, ADR-059
- **FDRs:** FDR-004, FDR-005, FDR-006, FDR-007

## Open questions

- How should projects define and persist named input actions and bindings?
- How should persisted project action contexts arbitrate project UI and gameplay after editor/UI routing has completed?
- How should controller connection, axes, dead zones, and multiple players extend the snapshot?
