# ADR-042: Publish UI interactions as immutable events

**Date:** 2026-07-29

## Context

Scrapbot's reusable controls already produced generic activation, change, submission, cancellation, and drag/drop edges. Those edges were split across renderer-owned `scrapbot.ui_state` revisions and an engine-internal ordered stream consumed by the editor.

Revision counters are useful durable state, but they force project systems to retain one cursor per entity and reconstruct ordering across controls. A destructive event queue would fix ordering while making multiple systems compete to consume the same interaction. Dispatching callbacks from the UI reconciler would instead give renderer mechanics knowledge of project or editor commands.

## Decision

Publish every generic UI interaction into a World-owned, immutable, bounded event history.

- Assign each event a monotonic sequence and frame index. Preserve interaction order and retain the latest 256 events in a ring.
- Include event kind, interacted entity UUID, interaction part, pointer position, drag/drop context, and the entity origin.
- Add the authored `scrapbot.ui_action` component with a required bounded semantic action string and optional bounded payload string. Resolve the nearest action on the interacted entity or its UI ancestors when publishing an event.
- Let each Luau system, native extension, and editor subsystem keep an independent sequence cursor. Reading never removes events. Readers receive the latest and oldest retained sequences plus an overflow flag.
- Make the no-cursor API return the latest completed UI interaction pass. Explicit cursors provide reliable catch-up across systems that do not run every frame.
- Exclude editor-origin events from project Luau and native extension snapshots. Editor orchestration reads the same history with its own origin filter.
- Keep `scrapbot.ui_state` as renderer-owned, read-only current interaction state and per-entity revision counters. The event history complements rather than replaces queryable state.
- Allocate and copy action strings only when an interaction occurs. An unchanged frame performs no event append, scan, string allocation, or derived rebuild.

## Consequences

Projects can bind gameplay meaning to reusable controls without component-name branches or renderer callbacks. An action attached to a row or panel subtree automatically applies to nested interactive content, while the event still identifies the exact control that changed.

Multiple systems may observe the same event safely. A slow reader can detect that its cursor fell behind retained history and choose a recovery policy instead of silently missing an edge.

The history is intentionally bounded and World-local. World replacement resets its sequence space, so consumers must treat playback replacement or hot reload as a cursor reset boundary.

Public UI event changes are cross-surface work. Scene parsing and persistence, Luau declarations, native fixed-layout payloads, editor consumption, examples, tests, architecture inventory, and public documentation must remain aligned.
