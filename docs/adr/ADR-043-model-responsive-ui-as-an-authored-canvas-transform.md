# ADR-043: Model responsive UI as an authored canvas transform

**Date:** 2026-07-29

## Context

Scrapbot originally treated project UI as an implicit 1280×720 surface. The
renderer uniformly fit that surface into a window or editor game viewport, but
projects could not choose another reference size, expose extra logical space,
crop deliberately, preserve integer pixel scaling, or author safe areas.
Layout boxes could fill available space, but they could not align themselves
independently on either axis.

These policies belong to the public UI system. Implementing them in project
scripts or editor viewport code would duplicate resize logic, detach pointer
coordinates from pixels, and make the editor a privileged UI consumer.

## Decision

Add one optional public `scrapbot.ui_canvas` component per entity-origin domain.
It must share an entity with a root `scrapbot.ui_layout`. The component owns:

- a positive logical reference size;
- `fit`, `fill`, `expand`, `stretch`, `pixel_perfect`, or `none` scaling;
- start, center, or end placement on each host axis;
- logical top/right/bottom/left safe-area insets; and
- optional minimum and maximum scale bounds, where zero means unbounded.

`expand` applies the largest uniform fit scale and expands the logical viewport
along the host's longer axis. `fit` letterboxes the reference rectangle, `fill`
crops it, `stretch` scales axes independently, `pixel_perfect` selects the
largest fitting whole-number scale at or above one when possible, and `none`
uses the current output pixel density while exposing the host in logical units.
If no canvas exists, preserve the legacy top-left 1280×720 uniform-fit
transform.

Apply one resolved transform to project layout, paint geometry, clips, text and
icon metrics, embedded UI viewports, pointer inversion, semantic diagnostics,
and editor embedding. Safe-area insets constrain the canvas root's children;
they do not shrink its own background.

Extend `scrapbot.ui_layout` with independent `start`, `center`, `end`, and
`stretch` alignment on each axis. The same generic resolver serves root,
overlay, stack cross-axis, project, and editor UI. Canvas placement deliberately
omits `stretch` because canvas scaling already owns output extent.

Canvas membership and value changes use the existing structural dirty queue and
project/editor layout revisions. The retained UI caches the active canvas by
origin and reads its exact typed slot on invalidation; stable frames do not scan
component storage or rebuild layout.

Expose the complete canvas and alignment payloads through scene TOML, Luau,
generated declarations, the native Odin ABI/wrapper, reflected editor
inspection, authoring snapshots, and persistence.

## Consequences

Projects can build resolution-independent HUDs and application surfaces without
resize systems or renderer knowledge. The editor remains an ordinary consumer:
its game viewport, project interaction, diagnostics, and WGPU output all use
the public authored transform.

`stretch` can distort content and `fill` can crop it; both remain explicit
project choices. `pixel_perfect` below one must use a fractional fit so an
oversized reference surface remains visible. This canvas contract does not add
breakpoints, percentage lengths, or arbitrary constraints. Intrinsic
measurement and wrapping are the separate retained-layout policy recorded in
ADR-044.
