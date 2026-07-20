# ADR-024: Update derived ECS state from structural changes

**Date:** 2026-07-14

## Context

The retained UI tree and internal render-instance membership are derived from ECS components. Rebuilding that membership by scanning every world entity on every frame makes steady-state cost grow with total entity count even when nothing structural changed. It also discards useful retained state and obscures the distinction between structural membership changes and ordinary per-frame value animation.

## Decision

Make every supported entity/component lifecycle path mark the affected entity in a deduplicated structural dirty queue. UI synchronization consumes only dirty entities, adding, updating, or removing their retained nodes in place. Render synchronization consumes only dirty entities and maintains a dense set of entities that currently own valid render instances.

Process dirty queues in insertion order and continue through entries appended while synchronization is running. Resource registration may mark all entities dirty because it is an infrequent structural boundary that can make unresolved geometry or material names valid. World replacement performs one complete bootstrap into the queues.

Keep value extraction separate from structural synchronization, but drive both with explicit mutation signals. Project and editor UI domains carry independent layout and paint revisions. Typed ECS setters increment the affected paint revision for visual changes and the layout revision for geometric changes; layout, scrolling, focus, and interaction update the same domain signals when retained state changes. An unchanged domain therefore skips layout, paint traversal, and glyph emission without hashing every retained node and component each frame. Dynamic editor-world camera and gizmo primitives use an independent bounded overlay stream rather than invalidating retained chrome.

Render value mutation paths enqueue the exact entity in a retained-extraction queue. They do not enqueue structural reconciliation unless component membership, resource binding, or render eligibility can change. The persistent render list updates or removes only those entries and publishes dirty render slots to the backend. Native and Luau transform writebacks, editor inspector edits, gizmo edits, structural commands, and resource reconciliation all use this contract. Cameras and bounded light sets remain frame values because they directly define the compact render uniform, but unchanged renderables are not copied each frame.

The WGPU UI boundary consumes monotonic output revisions instead of hashing the complete retained paint array. Project UI, editor chrome, and editor-world overlays own independent CPU vertex arrays, GPU buffers, revision keys, and rebuild counters. A change in one domain rebuilds and uploads only that domain; stable domains issue retained-buffer draws without paint traversal, hashing, vertex generation, or transfer. UI interaction edge flags are cleared from a dirty generational-entity queue rather than by scanning allocated `ui_state` storage. Structural synchronization rebuilds compact hierarchy links only when membership or a parent relationship actually changes.

## Consequences

An unchanged frame performs no UI-membership reconciliation, render-instance reconciliation, renderable extraction, full-tree UI or paint-output signature scan, layout, paint traversal, vertex generation, or UI upload, while entity appearance, disappearance, component attachment/removal, editor visibility, resource registration, and ordinary visual mutation invalidate only the affected derived domain. Retained scroll, focus, hover, and other node-local values survive unrelated structural changes.

All structural and render-value mutation APIs must mark the correct queue, and all public UI value mutation must use typed setters so paint and layout revisions remain truthful. Directly changing component indexes, entity liveness, transforms, render properties, or UI values outside those APIs can leave derived state stale; tests and debug assertions should catch such bypasses. Dense membership sets and retained render-list maps require swap-removal bookkeeping, while ordered dirty processing preserves deterministic scene order.
