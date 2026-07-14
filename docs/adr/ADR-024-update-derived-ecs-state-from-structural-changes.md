# ADR-024: Update derived ECS state from structural changes

**Date:** 2026-07-14

## Context

The retained UI tree and internal render-instance membership are derived from ECS components. Rebuilding that membership by scanning every world entity on every frame makes steady-state cost grow with total entity count even when nothing structural changed. It also discards useful retained state and obscures the distinction between structural membership changes and ordinary per-frame value animation.

## Decision

Make every supported entity/component lifecycle path mark the affected entity in a deduplicated structural dirty queue. UI synchronization consumes only dirty entities, adding, updating, or removing their retained nodes in place. Render synchronization consumes only dirty entities and maintains a dense set of entities that currently own valid render instances.

Process dirty queues in insertion order and continue through entries appended while synchronization is running. Resource registration may mark all entities dirty because it is an infrequent structural boundary that can make unresolved geometry or material names valid. World replacement performs one complete bootstrap into the queues.

Keep dynamic value extraction separate from structural synchronization. Layout and paint still run each frame for responsive UI and interaction. Render lists still copy current transforms, cameras, lights, and material-facing instance data each frame so systems can animate values without structural notifications.

## Consequences

An unchanged frame performs no UI-membership or render-instance reconciliation, while entity appearance, disappearance, component attachment/removal, editor visibility, and resource registration update only affected derived state. Retained scroll, focus, hover, and other node-local values survive unrelated structural changes.

All structural mutation APIs must mark the correct queue. Directly changing component indexes or entity liveness outside those APIs can leave derived indexes stale; tests and future debug assertions should catch such bypasses. Dense membership sets require swap-removal bookkeeping, while ordered UI dirty processing preserves deterministic scene order.
