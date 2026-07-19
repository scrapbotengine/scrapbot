# ADR-029: Postprocess the HDR world before UI composition

**Date:** 2026-07-16

## Context

Bloom needs scene brightness above display white, but the original geometry shader tone-mapped each object directly into the presentation target. That discarded HDR information before a screen-space effect could use it. Applying bloom after all drawing would also blur editor and project UI, making text and controls less legible.

## Decision

Render world geometry into a linear floating-point HDR target. Build a five-level filtered bloom pyramid with one compute pass and five dispatches, composite the scales with the HDR scene, and tone map once into the presentation target. Render project UI, gizmos, and editor chrome afterward as an ordinary display-referred overlay.

Keep emissive radiance in shared material resources and all intermediate textures, pipelines, and bind groups in the WGPU backend.

## Consequences

Emissive colors can exceed display white and create stable bloom without depending on scene lights. Broad multi-scale halos retain saturated color, and UI remains crisp and unaffected by world postprocessing. Headless framegrabs exercise the same composite path as visible windows.

The backend owns several size-dependent floating-point storage textures, compute bind groups, and a final composite pass. Window resize must rebuild them, and future exposure and bloom controls need an explicit project-facing settings surface. Consolidating the pyramid avoids the command-finalization cost of many short render passes.
