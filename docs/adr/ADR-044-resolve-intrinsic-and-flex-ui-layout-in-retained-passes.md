# ADR-044: Resolve intrinsic and flex UI layout in retained passes

**Date:** 2026-07-30

## Context

Scrapbot's retained box model could fill available axes and size containers
around descendants, but leaf text did not contribute an intrinsic size.
Horizontal and vertical stacks either used fixed authored sizes or divided one
line proportionally. Projects therefore needed manual rectangles for multiline
copy, toolbars, tag collections, and layouts that should absorb or shed space.

These capabilities must remain part of the public ECS UI contract. A
renderer-only cascade, editor-specific geometry pass, or per-frame layout scan
would violate the shared-surface and change-driven architecture.

## Decision

Extend `scrapbot.ui_layout` with non-negative per-child `basis`, `grow`, and
`shrink` values. Zero basis selects the child's authored or resolved intrinsic
main-axis size. Positive free space is distributed by grow factors; overflow is
removed by shrink factors without crossing the child's `min_size`.

Extend horizontal and vertical stacks with optional wrapping and an independent
line gap. Wrapped stacks pack children by preferred outer size, then resolve
grow and shrink independently for each line. Existing proportional fill and
draggable split behavior remains a separate compatible path; wrapped stacks do
not combine with either.

Extend text with automatic word wrapping and explicit line height. The layout
and paint paths use the same active-font glyph advances and deterministic line
breaks. Explicit newlines always break; whitespace is preferred; a word wider
than the content box falls back to glyph boundaries. Intrinsic text height feeds
ordinary fit-content layout without mutating authored component values.

Keep all temporary line, child, and flex resolution data in bounded retained UI
storage. Layout runs only when the affected project or editor domain's monotonic
layout revision changes. Stable frames perform no measurement, line breaking,
tree traversal, paint rebuilding, or GPU upload.

Expose the complete values through scene TOML, Luau, generated declarations,
the native extension ABI/wrapper, runtime reflection, persistence, examples,
and public documentation.

## Consequences

Projects and editor composition can share responsive multiline copy, wrapping
toolbars, chip grids, and flexible application layouts without resize scripts
or a second widget system. Project fonts produce identical measurement and
paint decisions.

The retained resolver has more bounded scratch data and line-level arithmetic.
Minimum sizes can intentionally leave overflow when shrink capacity is
insufficient. This decision does not add percentages, viewport breakpoints,
arbitrary constraints, bidirectional text shaping, or horizontal scrolling.
