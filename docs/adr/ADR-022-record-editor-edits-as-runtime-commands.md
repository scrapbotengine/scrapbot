# ADR-022: Record editor edits as runtime commands

**Date:** 2026-07-14

**Superseded by:** ADR-027

## Context

Inspector controls need live feedback while a value is typed, stepped, or scrubbed, but treating every preview update as an independent edit makes undo unusable. Direct ECS mutation also loses the value that existed before a gesture and cannot distinguish a completed edit from an invalid or cancelled one. Scene persistence is not ready yet, so the first command model must remain useful without claiming that runtime edits modify source TOML.

## Decision

Preview valid inspector values directly in the selected entity's runtime component. Capture the original numeric value when an input receives focus or begins a scrub, then record one bounded editor command when the gesture completes through Enter, Tab, focus change, pointer release, or editor closure. Escape restores the captured value without adding history. Invalid text stays in the focused control, receives error styling, and never mutates the world or creates a command.

Store commands in a fixed-capacity editor-owned history containing the generation-aware target entity, its component-membership revision, component field, optional Vec3 axis, custom-component storage coordinates, and before/after numeric values. The per-entity revision prevents a command from mutating a different component incarnation after removal and re-addition without invalidating history for unrelated runtime entities. A new edit truncates the redo tail. `Ctrl/Cmd+Z` applies the previous value and `Ctrl/Cmd+Shift+Z` reapplies the next value while the editor is open; shortcuts do not consume project input when editor chrome is closed or a project-owned input has focus.

Keep this history runtime-only. Scene serialization, dirty tracking, generalized reflected payloads, gizmo transactions, and persistent undo data will extend or consume the command boundary later rather than being implied by this slice.

## Consequences

Typing, keyboard stepping, and pointer scrubbing share one undoable gesture model while preserving immediate ECS feedback. Invalid and cancelled edits are deterministic, redo is well-defined, and history storage cannot grow without bound.

Commands currently cover the inspector's numeric transform, camera, light, and custom Vec3 fields only. Entity destruction, component removal, or constraint changes can make an older command inapplicable; undo and redo discard such stale entries while searching for the next applicable command so they cannot wedge the history cursor. The fixed history drops its oldest entry when full, and edits are lost when the process exits.
