# ADR-054: Select geometry submission through layered policy

**Date:** 2026-08-08

## Context

Virtual Geometry reduces detail and visibility work for sufficiently dense assets, but its
hierarchy traversal, streaming, indirect setup, and portable vertex pulling are not free. Applying
that path to every Geometry made ordinary scenes pay machinery intended for much larger inputs.

A project-wide switch alone cannot describe a scene containing both small props and dense terrain.
Camera-distance switching would also churn retained topology, caches, and pipelines during ordinary
frames.

## Decision

Geometry submission uses one backend-neutral `Geometry_Mode` policy with `auto`, `conventional`,
and `virtual` choices. `inherit` exists only at lower authoring layers.

Resolution is stable and ordered:

1. the entity's Mesh, Geometry, or Model component override;
2. the authored Model resource preference;
3. the project `[render]` default; and
4. the backend's conservative automatic crossover.

The project default is `auto`. WGPU's first automatic crossover selects Virtual only when the
adapter supports the required GPU path, the Geometry has a valid hierarchy, CPU-reference culling
is disabled, and the canonical primitive has at least 50,000 triangles. Otherwise it selects
Conventional. An explicitly requested Virtual mode still falls back to Conventional when the
backend cannot execute it correctly.

Selection happens at retained topology or resource-version boundaries, never from per-frame
projected size. Conventional and Virtual instances of the same Geometry may coexist. They receive
separate retained batches and separate backend cache entries while sharing the same resource-owned
canonical and hierarchical data.

Model import continues to compile both the canonical representation and hierarchy/page product.
Changing the preference does not reimport the source asset or discard either representation.

Renderer profiles and live-debug snapshots publish conventional/virtual batch and instance counts
so automatic decisions remain observable.

## Consequences

Small and medium assets avoid continuous virtual-geometry overhead by default. Dense assets retain
the memory, culling, and streaming benefits without requiring an example-specific render path.

Projects can force one global policy, asset authors can give a Model a sensible default, and scene
authors can override exceptional instances. Stable frames do not reconsider the choice or rebuild
unchanged batch topology.

The initial triangle threshold is deliberately portable and conservative, not adapter-calibrated.
Future calibration may vary the crossover by qualified adapter and workload class while preserving
the same public policy and deterministic topology-boundary resolution.
