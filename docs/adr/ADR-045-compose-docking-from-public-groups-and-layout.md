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

The active item fills the dock space below its tab strip. A direct
`ui_dock_item` contributes its explicit tab title and movement policy. A titled
`ui_panel` is also an eligible item while it is a direct dock-space child: its
panel title supplies the tab, its internal title band is suppressed, and its
`movable` field controls whether the tab may leave. Inactive direct items remain
in ECS storage but leave layout, paint, focus, and pointer interaction. An empty
active UUID selects the first eligible direct child without mutating authored
data.

Dragging a movable tab across the fixed threshold and releasing it over another
draggable dock space updates the item's public `ui_layout.parent` UUID, selects
it in the destination, and publishes the ordinary read-only drop state plus an
immutable `Dropped` UI event. Empty groups remain valid transfer targets.

Workspace topology remains ordinary public layout. Projects compose dock
spaces inside overlay boxes, draggable fill HStacks/VStacks, scroll areas, and
other existing primitives. Docking does not introduce a private split tree,
floating-window model, editor workspace object, or renderer-owned hierarchy.

A dock space may independently opt into horizontal and vertical edge targets.
Releasing a movable panel or tab on an enabled edge replaces the target space
in its current parent with a public fill HStack or VStack, reparents the target
into that stack, creates one public sibling dock space, and reparents the
dropped item into the new space. The generated branch preserves the target's
position among existing stack siblings. Its ordinary draggable gap owns pane
resizing. The authored split ratio, edge fraction, gap, and minimum size are
copied through every public authoring and mutation surface. A directional
target is unavailable when two minimum panes plus the gap do not fit; the
center remains the existing tab/stack transfer target.

Generated project branches use runtime-origin entities in the same project UI
domain as scene-origin entities. Generated editor branches use editor origin.
Scene and runtime UI may therefore share UUID parent links, while editor UI
remains isolated. These entities carry only the same public layout, stack, and
dock-space components available to projects; the renderer does not retain a
parallel workspace topology.

The same ordinary stacks may opt into direct-child panel reordering. A movable
public panel uses its title band as a thresholded drag handle while a click
continues to toggle collapse. The child's public `ui_layout.stack_order` is the
authoritative sibling order. A completed drag normalizes only affected sibling
orders, may change the ordinary UUID parent when transferred to another
compatible stack, or may make the panel a direct child and new tab of a
compatible dock space. A docked panel can return to a reorderable stack by
dragging that tab. Completed transfers publish the same drop state and
immutable event contract as docking. Crossing the drag threshold consumes the
title gesture even when release finds no destination, so cancellation never
falls back to collapse. Stack gaps continue to own independent pane resizing.

A panel released over an existing tab header targets the nearest reorderable
HStack or VStack inside that tab rather than creating a sibling tab. The
descendant stack may belong to an inactive item because hierarchy and component
membership remain retained while its layout is hidden. Empty dock-space chrome
remains the distinct new-tab target. This makes a tab a composable stack host
without adding panel storage or flow fields to the dock component.

The accepting tab header uses the dock space's public drop style even when its
inactive stack cannot paint an insertion line. Movable titles and tabs expose a
backend-neutral move cursor; an active drag without a compatible destination
exposes a not-allowed cursor.

A panel may itself carry that reorderable stack for use after it becomes a
tab. While the panel remains inside another stack, its own flow component lays
out content but is excluded as a competing panel-drop destination; the
containing workspace stack wins. Once the panel is a direct dock-space child,
its stack becomes the tab destination.

The retained UI stores bounded tab, panel-drag, and split-handle state.
Structural and component revisions rebuild only the affected project or editor
domain. Stable frames do not scan the World, reconstruct interaction geometry,
rebuild paint, or upload UI vertices.

Expose the complete contract through scene TOML, Luau, generated declarations,
native Odin payloads and helpers, runtime reflection, persistence, semantic UI
automation, examples, and public documentation. The editor composes its
Browse, Game, and Inspect regions from these same components; editor-only code
supplies content and meaning but no docking, panel-reordering, resizing
mechanics, or styles.

## Consequences

Projects can build IDEs, node tools, strategy-game dashboards, inventory
workspaces, and radically themed tabbed or multi-panel interfaces with the same
system the editor uses. Existing stack separators continue to own pane
resizing, public panel-title dragging owns ordering, and edge drops can produce
the same topology interactively.

The current transfer operation preserves direct-child tab order and does not
reorder tabs within one group, collapse an emptied generated branch, float a
window, or persist a workspace arrangement. Those behaviors can extend the
same public components and ordinary layout topology without replacing this
contract.
