# ADR-012: Model frame time as a world resource

**Date:** 2026-07-12

## Context

Scrapbot previously passed a loose delta-seconds scalar into each system and used a fixed 1/60 step in every renderer path. Frame time is global engine state shared by all systems, not data owned by a particular entity. Representing it as a singleton component would require a synthetic entity, uniqueness rules, and special lifecycle handling.

## Decision

Store an engine-owned `Time` resource on the ECS world. Advance it once at the frame boundary and expose the same read-only snapshot to Luau and native systems. The resource tracks delta time, exponentially smoothed delta time, elapsed time, and frame index. Deterministic null/headless runs use their requested fixed step; interactive window runs measure monotonic wall-clock time and clamp hitches to 250 milliseconds.

## Consequences

All systems observe one coherent frame-time snapshot without querying a fake singleton entity. Tests and headless runs remain deterministic, while interactive motion reflects actual frame cadence. The resource boundary provides a natural home for future time scale, pause, fixed-step accumulation, and interpolation state. Time is currently world-wide; independent clocks or per-world time scaling will require explicit additional resources rather than extra `Time` components.
