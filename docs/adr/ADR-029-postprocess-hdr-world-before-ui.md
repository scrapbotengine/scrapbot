# ADR-029: Postprocess the HDR world before UI composition

**Date:** 2026-07-16

## Context

Bloom needs scene brightness above display white, but the original geometry shader tone-mapped each object directly into the presentation target. That discarded HDR information before a screen-space effect could use it. Applying bloom after all drawing would also blur editor and project UI, making text and controls less legible.

## Decision

Render world geometry into a linear floating-point HDR target with an eight-sample subpixel projection-jitter sequence. Reconstruct view-space positions and normals from the existing scene-depth prepass, evaluate ambient occlusion at half resolution, and apply separable depth-aware bilateral blur. Fold that ambient visibility into the current HDR signal before resolving it into retained history. The temporal resolve reconstructs world position from depth, reprojects through the previous camera, rejects mismatched previous depth, clamps retained color to the current 3×3 neighborhood, and reduces history weight during screen-space motion. Camera cuts, world replacement, output resize, and depth-target replacement invalidate history. Keep frustum/Hi-Z culling on the unjittered camera so the sample sequence cannot change visibility.

Build a five-level filtered bloom pyramid from the temporally resolved HDR world, composite the bloom scales, and tone map once into the presentation target. Render project UI, gizmos, and editor chrome afterward as an ordinary display-referred overlay.

Keep emissive radiance in shared material resources and all intermediate textures, pipelines, and bind groups in the WGPU backend.

## Consequences

Emissive colors can exceed display white and create stable bloom without depending on scene lights. Broad multi-scale halos retain saturated color, temporal supersampling stabilizes subpixel geometry and texture detail during camera motion, and depth-reconstructed ambient occlusion adds contact and crevice grounding without another geometry pass. Accumulating the blurred AO with world color prevents the half-resolution mask from crawling independently across grazing surfaces. Depth rejection and neighborhood clamping bound disocclusion history; moving geometry without motion vectors may still lose accumulation or show limited residual ghosting. UI remains crisp and unaffected by world postprocessing. Headless framegrabs exercise the same deterministic jitter and composite path as visible windows.

The backend owns full-resolution resolved/history color and depth textures, several size-dependent floating-point bloom textures, half-resolution ambient-occlusion textures, compute bind groups, and a final composite pass. Window resize or replacement of the sampled depth target rebuilds the affected bindings and rejects stale history. Ambient-occlusion, exposure, bloom, and temporal-antialiasing controls still need an explicit project-facing post-processing surface. Consolidating compute work avoids the command-finalization cost of many short render passes.
