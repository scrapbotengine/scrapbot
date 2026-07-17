# ADR-030: Identify project resources by UUID outside the ECS

**Date:** 2026-07-17

## Context

Materials and future reusable data objects need stable project identity, text-first persistence, sharing between many entities, and inline editor authoring. Making each resource an entity would couple its lifetime and storage to a scene even though resources are project data shared across scenes. Names are editable labels and therefore cannot safely identify references.

## Decision

Store authored project resources as standalone `resources/**/*.resource.toml` files outside the ECS. Give every resource a non-zero project-wide UUID and serialize references by that UUID. Load resources into type-specific runtime registries, where they receive generational handles and content versions. ECS components store only resolved runtime handles; scene-world metadata retains the authored UUID needed for persistence and editor presentation.

Resource appearance, disappearance, and content changes reconcile the registry only when project files change. A content update preserves the live handle and increments its version; disappearance invalidates its generation; reappearance reuses its slot with the new generation. Renderer caches remain keyed by handle and version. Runtime-created resources remain transient and name-addressed, and cannot replace an authored resource. When one Save changes resources and scene references, ADR-031 commits their standalone files as one recoverable transaction.

## Consequences

Resources can be shared without scene ownership, renamed or moved without breaking references, edited and saved independently, and hot-reloaded without rescanning ECS membership every frame. Scenes remain compact UUID-reference documents. The loader and editor must validate UUIDs, distinguish authored and runtime resources, coordinate registry and ECS reconciliation, and provide type-specific serialization and inspectors. Canonical save rewrites only the edited standalone resource file, so comments within that file are not preserved; the project transaction groups that rewrite with every other dirty authored file.
