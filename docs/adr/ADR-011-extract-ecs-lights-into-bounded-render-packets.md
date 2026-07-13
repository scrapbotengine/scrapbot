# ADR-011: Extract ECS lights into bounded render packets

**Date:** 2026-07-12

## Context

Lights are scene data that systems may create, remove, or animate, but rendering backends need compact, backend-neutral frame input rather than direct access to ECS storage. An initial renderer also needs explicit limits so uniform allocation and shader loops stay predictable.

## Decision

Represent ambient, directional, and point lights as public engine ECS components. Before rendering, extract alive lights into the transient render list: accumulate ambient contributions, copy at most four directional lights, and copy at most sixteen point lights with positions taken from their transforms. Rendering backends consume this bounded packet and own the GPU representation.

## Consequences

Gameplay systems can query and animate lights through the same ECS used for other scene state, while renderer backends remain independent of world storage. Ambient lights do not require transforms; point lights do. The initial limits are simple and deterministic, but larger scenes will eventually need light selection, culling, clustered lighting, or storage-buffer based data.
