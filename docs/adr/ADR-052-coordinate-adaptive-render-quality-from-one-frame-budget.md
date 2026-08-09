# ADR-052: Coordinate adaptive render quality from one frame budget

**Status:** Accepted
**Date:** 2026-08-02
**Updated:** 2026-08-09

## Context

Dynamic world resolution and adaptive shadow resolution originally consumed the same delayed GPU evidence through separate controllers. They could cool down, restore, and invalidate measurements independently. Adding more scalable effects that way would multiply policy state and make the rendered result difficult to predict.

Projects also need a clear distinction between authored intent and runtime adaptation. An authored effect switch or quality value is a ceiling. The renderer may reduce work to meet a target, but it must not silently enable a feature or descend below the project's declared floor.

## Decision

WGPU owns one backend-local frame-budget controller per active render-policy camera. It consumes
the ordered GPU scene span and advances at most one step on a deterministic quality ladder.

The controller retains both an exponentially filtered average and a fixed 20-sample window. It
uses the nearest-rank 95th percentile of that bounded window for both pressure and recovery
decisions. Three sustained over-budget evaluations can degrade one step; recovery still requires
prolonged headroom. This keeps a cheap camera stretch from restoring detail that repeatedly misses
the authored target in heavier views.

The ladder coordinates four derived outputs:

- world render-grid scale, bounded by `resolution_scale` and `dynamic_resolution_min_scale`;
- directional-shadow raster resolution, selected from 2048², 1024², and 512²;
- virtual-geometry projected-error tolerance, selected from 1, 2, 4, 8, and 16 pixels, with the
  portable compact path starting at its measured two-pixel floor;
- a normalized post-quality factor applied to authored AO and SSR tiers and volumetric-fog ray steps.

Degradation first makes modest world-resolution concessions, then lowers the dominant shadow cost and uses the remaining authored scale range. At the minimum scale, it relaxes virtual-geometry detail before reducing post quality and the lowest shadow tier. Recovery walks the exact reverse order and requires sustained headroom. `adaptive_quality_minimum` bounds post quality, the permitted shadow tier, and the maximum virtual-geometry error.

Every output change increments one policy generation, clears the average and tail evidence, starts
one cooldown, and rejects delayed timestamp samples from the previous configuration. A camera-
policy or stable owner change resets all outputs together. Unsupported timestamp queries and
disabled adaptation select authored maxima.

Initialization uses the same cooldown. Samples inside a cooldown are discarded before they enter
the filtered average or p95 window. They commonly include target allocation, pipeline warmup, or
cache replacement and therefore do not describe the steady-state quality configuration. This also
prevents a resize spike from triggering another resize in a self-sustaining quality staircase.

## Consequences

- Quality changes are deterministic, reversible, and observable through renderer/profile diagnostics.
- `dynamic_resolution_filtered_gpu_ms` exposes the average signal;
  `dynamic_resolution_tail_gpu_ms` exposes the bounded percentile used for decisions.
- Authored camera settings remain authoritative ceilings and bounds; the controller never mutates ECS data.
- Backend submission cost may establish a path-specific maximum-quality floor. Native indexed
  virtual geometry retains one pixel; portable compact virtual geometry retains two pixels. Both
  consume the same controller state and recovery/degradation ladder.
- Stable frames perform constant work and allocate nothing for policy evaluation.
- A single scalar cannot perfectly model the visual importance or measured cost of every pass. The ordered ladder is deliberately explicit and may need platform-informed tuning as the hardware baseline matrix grows.
- Bloom remains authored and stable for now; its relatively small measured dispatch cost does not justify stale-pyramid or extra-composite-state complexity in this slice.
