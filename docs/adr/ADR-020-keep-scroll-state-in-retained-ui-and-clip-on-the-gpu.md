# ADR-020: Keep scroll state in retained UI and clip on the GPU

**Date:** 2026-07-13

## Context

A scroll container needs transient position, a wheel target, content measurements, and nested clipping. Scene components should describe durable behavior, but storing frame-by-frame interpolation in the ECS would make derived presentation state public and require structural UI systems to mutate authored data. CPU scissor rectangles cannot express nested per-element clips within Scrapbot's single ordered UI paint stream without splitting it into many draw calls.

## Decision

`ui_scroll_area` is a composable container component with authored scroll speed and smoothing. Its current offset, target offset, measured extent, and clip rectangle live on the reconciled UI node. Wheel input routes to the topmost hovered scroll area, changes its target, and uses frame-time exponential interpolation to approach that target.

A scroll area clips descendants to the padded content rectangle. Nested clips are intersected during layout and copied onto each affected paint command. The WGPU overlay passes the resulting physical clip rectangle with every vertex and discards fragments outside it. Pointer hit testing uses the same clip intersection.

## Consequences

Projects can place an explicitly oversized pane inside a fixed viewport and receive smooth scrolling, proportional scroll feedback, correct nested clipping, and pointer behavior without owning runtime offsets. The retained state resets when its entity disappears. Per-fragment clipping adds a small amount of UI shader work and does not yet provide horizontal scrolling, direct scrollbar dragging, touch gestures, keyboard scrolling, or public offset control.
