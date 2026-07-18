# ADR-027: Use authoring transactions for editor changes

**Date:** 2026-07-15

## Context

ADR-022 introduced bounded undo for numeric inspector gestures, but editor changes now also include booleans, transform gizmos, dirty tracking, and scene persistence. Treating these as separate mechanisms would duplicate target identity, gesture boundaries, and before/after values. Using undo history itself as the persistence source would also be unsafe: history is bounded, edits can be reverted, Save should retain undo, and future changes may not all share the same history lifetime.

## Decision

Represent each completed editor gesture as an authoring transaction containing one or more typed changes. Field changes identify their target by stable project UUID, record the component-membership revision and field path, and store before and after values. Entity and project-resource lifecycle changes own complete before and after snapshots under the same UUID. Component membership changes instead own an exact snapshot of only the affected registered component and use the registry's canonical storage/lifecycle metadata to mutate that storage surgically. Valid previews continue to update the active ECS world immediately, but typing, stepping, scrubbing, boolean changes, complete gizmo drags, entity/component operations, and resource lifecycle operations each enter history once at their natural commit boundary.

Undo and redo apply complete transactions by resolving UUIDs against the current world and rejecting stale component incarnations. Dependent field changes caused by one control gesture belong to the same transaction. The history remains bounded, editor-owned, and available only while stopped. Play captures component-membership revisions with the authoring baseline, and Stop restores those revisions with the authored entities, so history survives a playback round trip. Save retains history and records its cursor as the clean position, so an edit can still be undone after saving and returning to the saved cursor clears dirty state.

Transactions mark authored or explicitly promoted UUIDs as dirty candidates while stopped. Persistence does not serialize the transaction journal. Instead, Save semantically compares candidate entities and resources with the freshly parsed authored baseline. Value-only entity edits patch differing fields; structural entity edits rewrite only dirty UUID-scoped entity blocks according to ADR-028. Resource snapshots cover create, duplicate, rename, move, and delete while preserving UUID identity. Candidate membership uses constant-time UUID lookup, and disk changes occur only during explicit Save.

ADR-027 supersedes ADR-022.

## Consequences

Inspector controls and gizmos share one undo boundary and one stable identity model. Reverted previews, float representation differences, and unchanged fields cannot create source churn because the baseline comparison remains the final persistence authority. Runtime-spawned entities remain outside persistence through origin filtering.

The transaction value set covers numeric and boolean property changes, including three-axis transform gestures; complete structural snapshots for entity create, duplicate, rename, delete, and promote; exact per-component snapshots for membership changes; and resource snapshots for create, duplicate, rename, move, and delete. Per-component history preserves unrelated component storage and values during add/remove undo and redo. Revert deliberately reloads disk-authored entities and resources and clears the bounded history instead of manufacturing an inverse transaction for every discarded edit. Multi-selection will require larger transaction payloads, but it can extend the same history, dirty-candidate, and baseline-comparison flow without changing the persistence boundary.
