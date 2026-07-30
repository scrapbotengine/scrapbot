# ADR-045: Compose docking from public groups and layout

**Date:** 2026-07-30

## Context

Application-scale project interfaces and Scrapbot's editor both need tabbed
workspaces whose content can move between regions. Implementing that behavior
inside editor orchestration would create a second widget system. Encoding the
complete workspace as one opaque docking component would duplicate hierarchy,
split sizing, scrolling, persistence, and styling already owned by public ECS
UI.

Docking also changes hierarchy at runtime. The operation must use stable UUID
parents, publish generic interaction state, and invalidate only the affected
retained UI domains.

## Decision

Add two authored public components:

- `scrapbot.ui_dock_space` turns its direct `ui_dock_item` children into a
  tabbed group. It owns the active child UUID, tab geometry and HDR colors,
  font, and whether the group accepts transfers.
- `scrapbot.ui_dock_item` gives one direct child a tab title and controls
  whether that item may move.

The active item fills the dock space below its tab strip. Inactive direct items
remain in ECS storage but leave layout, paint, focus, and pointer interaction.
An empty active UUID selects the first eligible direct child without mutating
authored data.

Dragging a movable tab across the fixed threshold and releasing it over another
draggable dock space updates the item's public `ui_layout.parent` UUID, selects
it in the destination, and publishes the ordinary read-only drop state plus an
immutable `Dropped` UI event. Empty groups remain valid transfer targets.

Workspace topology remains ordinary public layout. Projects compose dock
spaces inside overlay boxes, draggable fill HStacks/VStacks, scroll areas, and
other existing primitives. Docking does not introduce a private split tree,
floating-window model, editor workspace object, or renderer-owned hierarchy.

The retained UI stores bounded tab hit rectangles beside its existing node and
split-handle caches. Structural and component revisions rebuild only the
affected project or editor domain. Stable frames do not scan the World,
reconstruct tabs, rebuild paint, or upload UI vertices.

Expose the complete contract through scene TOML, Luau, generated declarations,
native Odin payloads and helpers, runtime reflection, persistence, semantic UI
automation, examples, and public documentation. The editor composes its
Browse, Game, and Inspect regions from these same components; editor-only code
supplies content and meaning but no docking mechanics or styles.

## Consequences

Projects can build IDEs, node tools, strategy-game dashboards, inventory
workspaces, and radically themed tabbed interfaces with the same system the
editor uses. Existing stack separators continue to own pane resizing, so both
features improve independently.

The initial transfer operation preserves direct-child order and does not
reorder tabs within one group, create a new split from an edge drop, float a
window, or persist a workspace arrangement. Those behaviors can extend the
same public components and ordinary layout topology without replacing this
contract.
