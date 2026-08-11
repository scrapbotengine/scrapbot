# ADR-033: Model spatial hierarchy with local transforms and UUID parents

**Date:** 2026-07-18

## Context

Scene entities need durable spatial parent/child relationships for grouped authoring, but names and runtime entity handles are not stable project identity. Parenting also changes the meaning of a Transform: renderers and editor tools need a world-space pose, while source files and project systems need a compact authorable local pose. Storing both as authored state would create two competing sources of truth.

## Decision

Add an optional parent UUID to `scrapbot.transform`. A zero UUID means the Transform is a root. Position, Euler rotation, and scale are local to the referenced parent; root values are world-space. Parent references must resolve to a live entity and may not form a self-reference or cycle. A parent without a Transform contributes an identity spatial basis; assigning a parent to a transformless child first gives the child an identity Transform. Scene validation rejects invalid graphs, and the public Luau, native, and editor mutation paths apply the same constraints.

Derive world transforms from the local chain. Rendering, cameras, spatial lights, picking, and gizmos consume that derived value instead of authoring another component. Resolve each entity at most once per extraction epoch with a world-owned memoization cache; hierarchy membership does not require a full-world reconciliation pass. A failed runtime chain falls back to the entity's local pose and reports invalidity rather than recursing indefinitely.

The resolved Transform position is the entity's canonical spatial origin and therefore the basis inherited by children. Editor manipulation may temporarily place a gizmo at a rendered-bounds center, but that center is derived tool state rather than another serialized pivot. Rotating or scaling around it updates the entity's Transform position as well as orientation or scale, preserving one local-TRS hierarchy authority.

Editor reparenting preserves the entity's current world pose by computing a new local Transform relative to the destination parent. The complete reparent is one UUID-addressed structural authoring transaction while stopped and disposable runtime state during playback. Removing a runtime parent or its Transform detaches direct children while preserving their world poses. Stopped-mode deletion currently refuses an authored parent with Transform children until those children are moved, so Save cannot produce dangling references outside the deleted entity's transaction.

Entity display order is independent of ECS storage handles and Transform parenting. The world carries an internal scene-order key seeded from TOML block order; insertion mutates and normalizes that key without moving ECS slots. Hierarchy traversal sorts by it, structural Undo/Redo snapshots capture it, and Save emits entity blocks in that order. Dropping before or after a row adopts the target's parent and changes order as one world-pose-preserving transaction, while dropping into its middle adopts the target itself.

This first hierarchy model composes translation, quaternion rotation, and component-wise scale. It does not represent shear. Rotated descendants below non-uniformly scaled parents may therefore be an approximation when converted back to local TRS.

## Consequences

Renames, scene order changes, reloads, and runtime slot reuse do not break spatial links. Project files remain text-first and store only local authoring data. Systems may animate local transforms without maintaining duplicate world state, while render extraction pays work proportional to the active spatial chains it consumes.

Transform payloads now include a durable UUID field across scene TOML, Luau snapshots/writeback, native extensions, serialization, and the inspector. Tools that delete or remove parent Transforms must define child behavior explicitly. General multi-entity hierarchy editing, drag ghosts, and exact affine matrices with shear remain future extensions.
