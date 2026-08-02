# ADR-052: Coordinate adaptive render quality from one frame budget

**Status:** Accepted
**Date:** 2026-08-02

## Context

Dynamic world resolution and adaptive shadow resolution originally consumed the same delayed GPU evidence through separate controllers. They could cool down, restore, and invalidate measurements independently. Adding more scalable effects that way would multiply policy state and make the rendered result difficult to predict.

Projects also need a clear distinction between authored intent and runtime adaptation. An authored effect switch or quality value is a ceiling. The renderer may reduce work to meet a target, but it must not silently enable a feature or descend below the project's declared floor.

## Decision

WGPU owns one backend-local frame-budget controller per active render-policy camera. It consumes the ordered GPU scene span, filters each accepted sample exactly once, and advances at most one step on a deterministic quality ladder.

The ladder coordinates three derived outputs:

- world render-grid scale, bounded by `resolution_scale` and `dynamic_resolution_min_scale`;
- directional-shadow raster resolution, selected from 2048², 1024², and 512²;
- a normalized post-quality factor applied to authored AO and SSR tiers and volumetric-fog ray steps.

Degradation first makes modest world-resolution concessions, then lowers the dominant shadow cost, uses the remaining authored scale range, and finally reduces post quality and the lowest shadow tier. Recovery walks the exact reverse order and requires sustained headroom. `adaptive_quality_minimum` bounds both post quality and the permitted shadow tier.

Every output change increments one policy generation, clears filtered evidence, starts one cooldown, and rejects delayed timestamp samples from the previous configuration. A camera-policy or stable owner change resets all outputs together. Unsupported timestamp queries and disabled adaptation select authored maxima.

## Consequences

- Quality changes are deterministic, reversible, and observable through renderer/profile diagnostics.
- Authored camera settings remain authoritative ceilings and bounds; the controller never mutates ECS data.
- Stable frames perform constant work and allocate nothing for policy evaluation.
- A single scalar cannot perfectly model the visual importance or measured cost of every pass. The ordered ladder is deliberately explicit and may need platform-informed tuning as the hardware baseline matrix grows.
- Bloom remains authored and stable for now; its relatively small measured dispatch cost does not justify stale-pyramid or extra-composite-state complexity in this slice.
