# ADR-027: Use authoring transactions for editor changes

**Date:** 2026-07-15

## Context

ADR-022 introduced bounded undo for numeric inspector gestures, but editor changes now also include booleans, transform gizmos, dirty tracking, and scene persistence. Treating these as separate mechanisms would duplicate target identity, gesture boundaries, and before/after values. Using undo history itself as the persistence source would also be unsafe: history is bounded, edits can be reverted, Save should retain undo, and future changes may not all share the same history lifetime.

## Decision

Represent each completed editor gesture as an authoring transaction containing one or more typed changes. Every change identifies its target by stable project UUID, records the component-membership revision and field path, and stores before and after values. Valid previews continue to update the active ECS world immediately, but typing, stepping, scrubbing, boolean changes, and complete gizmo drags each enter history once at their natural commit boundary.

Undo and redo apply complete transactions by resolving UUIDs against the current world and rejecting stale component incarnations. The history remains bounded and editor-owned. Stop clears history because it replaces the world with the authored scene; Save retains history so an edit can still be undone after saving.

Transactions mark scene-origin UUIDs as dirty candidates while stopped. Persistence does not serialize the transaction journal. Instead, Save semantically compares candidate entities with the freshly parsed authored baseline and patches only fields whose typed values differ. Candidate membership uses constant-time UUID lookup, and the source file is scanned and atomically replaced only during explicit Save.

ADR-027 supersedes ADR-022.

## Consequences

Inspector controls and gizmos share one undo boundary and one stable identity model. Reverted previews, float representation differences, and unchanged fields cannot create source churn because the baseline comparison remains the final persistence authority. Runtime-spawned entities remain outside persistence through origin filtering.

The current transaction value set covers numeric and boolean property changes, including three-axis transform gestures. Structural entity/component operations and multi-selection will require additional change variants and larger transaction payloads, but they can extend the same transaction, history, dirty-candidate, and baseline-comparison flow without changing the persistence boundary.
