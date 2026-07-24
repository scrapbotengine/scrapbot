# ADR-039: Keep clustered lighting and shadow cascades backend-owned

**Date:** 2026-07-22
**Last amended:** 2026-07-23

## Context

The original frame packet placed sixteen point lights directly in a render uniform and rendered one fixed orthographic directional shadow map. That kept the first renderer simple, but it discarded additional authored lights, made fragment cost proportional to every retained point light, and could not preserve useful directional-shadow resolution across a camera's depth range.

ECS light components and their compact active sets remain the authoritative project-facing state. Cluster membership, cascade splits, shadow textures, and per-cascade visibility are renderer-derived data and must not become gameplay state or weaken Odin/Luau access to lights.

## Decision

Keep backend-neutral extraction change-driven and growable. It retains every active point light instead of truncating a fixed frame packet; capable backends own their scalable GPU representation and practical device limits.

WGPU uploads changed point-light records into a geometrically growing storage buffer. A cluster-centric compute pass builds deterministic per-cluster light lists for a 16×9×24 view-frustum grid. Cluster index storage begins at 256 lights per cluster and grows with the retained light table, so dense overlap never silently discards a light. Each GPU invocation owns one cluster and visits lights in stable retained order; the CPU never calculates cluster membership. Fragment lookup subtracts the rendered viewport origin before selecting an X/Y tile, so an editor-inset viewport consumes the same cluster grid that was built for its camera projection. The cluster pass reruns only when the camera, viewport, point-light payload, or buffer capacity changes.

Postprocessing reuses those same retained buffers for opt-in volumetric point-light scattering. Each deterministic fog ray step resolves its view-frustum cluster and evaluates its complete relevant list. Fog does not build, upload, or retain a second light list.

Render the first directional light through four camera-relative cascades in one depth-texture array. Compute practical logarithmic/uniform splits out to 80 world units, stabilize each light projection to shadow texels, GPU-cull casters independently for every cascade, and select the cascade plus a 3×3 PCF footprint in the world shader. Apply slope-scaled depth bias while rendering casters and a receiver-normal offset scaled by each cascade's world-space texel size; this avoids camera-dependent self-shadowing without making one clip-space constant serve incompatible cascade scales. `--cpu-culling` retains a deterministic reference implementation of the same four cascade visibility volumes; it does not replace GPU cluster construction.

Keep all cluster buffers, cascade textures, matrices, visibility lists, indirect arguments, and diagnostics inside WGPU. Public Ambient, Directional, Point Light, Shadow Caster, and Shadow Receiver components remain backend-neutral.

## Consequences

Scenes may use substantially more point lights without evaluating every light in every fragment or fog sample, and directional shadows retain useful near-camera resolution over larger views. Stable camera/light frames do not rebuild cluster lists, and ordinary ECS membership remains change-driven.

The backend initially reserves storage for 3,456 cluster counts and 256 indices per cluster—about 3.4 MiB of cluster-index storage—and grows geometrically when a scene exceeds that light count. A pathological cluster may evaluate every retained light and buffer memory grows with the worst-case per-cluster stride, but ordinary fragments still visit only lights whose spheres overlap their view-frustum cluster. Explicit remaining limits are four cascades, one shadowed directional light, and an 80-unit shadow distance. Point-light shadows, compact variable-length cluster storage, adaptive cluster dimensions, device-limit diagnostics, cascade blending, and user-facing quality settings remain future work.
