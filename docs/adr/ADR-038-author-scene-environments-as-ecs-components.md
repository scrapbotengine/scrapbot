# ADR-038: Author scene environments as ECS components

**Date:** 2026-07-22

## Context

Environment resources are project-owned imported data, but selecting the lighting and visible sky is scene authoring state. Keeping that selection in `project.toml` makes it global, hides it from ordinary entity inspection and history, and gives the renderer a configuration path unrelated to other authored scene data.

## Decision

Represent scene environment selection with one authored `scrapbot.world_environment` ECS component. A scene may contain at most one. It references Environment resources by stable UUID and owns lighting intensity/rotation, base exposure, visible-background selection and presentation controls. When the visible background is procedural, the same component owns bounded art-direction inputs for sky tint, ground color, turbidity, atmosphere thickness, horizon softness, and an independent world-space sun direction, color, HDR intensity, disc size, and glow.

The fixed `scrapbot.environment` engine phase retains the selected entity and its component revision. Structural changes rediscover the singleton; value changes resolve only its resource UUIDs and mutate a renderer-facing resource-registry cache. Stable frames perform no complete-world or resource scan. Environment resources remain outside the ECS and the renderer continues to consume generational handles and a monotonic environment revision.

With no assigned background Environment, an enabled background uses the renderer-native procedural haze sky. Assigning a background UUID selects the imported panorama instead. Procedural controls remain authored data in that case but intentionally have no effect on the imported image. The procedural sun is renderer-native environment lighting rather than an authored ECS entity: above the horizon, render extraction derives the first bounded directional-light input from it, so ordinary GGX lighting, shadow culling, and the primary directional shadow map share its direction. Its elevation also drives horizon occlusion, day/twilight/night atmosphere colors, and hemispherical sky/ground fill. Below the horizon, the derived light disappears. Explicit ECS lights remain additive; the derived sun consumes one of the four directional-light render slots while active.

## Consequences

Environment state participates in scene persistence, automatic type-inspected editor panels, playback restore, and component membership rules. Projects can use different environments per scene without changing their manifest. Atmosphere numbers use the registry's ordinary numeric editor metadata, so their generated inspector controls support bounded drag editing without an environment-specific panel. Duplicate environment components, invalid ranges, and invalid resource references fail validation instead of producing an order-dependent winner.

The implementation retains a small resolved cache in the resource registry and a retained singleton index/revision in the World. Future fog, tone mapping, clouds, and postprocessing can remain separate components/systems rather than turning this component into an unbounded render-settings bag.
