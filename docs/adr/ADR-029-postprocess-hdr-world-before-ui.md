# ADR-029: Postprocess the HDR world before UI composition

**Date:** 2026-07-16

## Context

Bloom needs scene brightness above display white, but the original geometry shader tone-mapped each object directly into the presentation target. That discarded HDR information before a screen-space effect could use it. Applying bloom after all drawing would also blur editor and project UI, making text and controls less legible.

## Decision

Render world geometry into linear floating-point HDR, surface-data, and indirect-diffuse targets. Use an eight-sample subpixel projection-jitter sequence.

Reconstruct view-space positions from the depth prepass and consume the mapped view-space normals written by world shading.

Evaluate AO at half resolution over rotated view-space slices. Replace GTAO's two maximum horizons with a 32-sector visibility bitmask. Every sampled front surface plus a constant-thickness reconstructed back surface marks only its angular interval, allowing visibility to reopen behind thin geometry.

This follows Therrien, Levesque, and Gilet's [Screen Space Indirect Lighting with Visibility Bitmask](https://arxiv.org/abs/2301.11376) technique.

Filter and upscale AO only through depth- and normal-similar neighbors. Apply visibility only to indirect diffuse; direct lights, specular lighting, emission, and SSR remain unoccluded.

The temporal resolve reconstructs world position, reprojects through the previous camera, rejects mismatched depth, clamps history to the current 3×3 neighborhood, and reduces history weight during screen-space motion. Two retained color/depth pairs alternate as current output and previous history, avoiding full-resolution history copies. Camera cuts, world replacement, resize, and depth-target replacement invalidate history.

Keep frustum and Hi-Z culling on the unjittered camera so the sample sequence cannot change visibility.

Write one additional floating-point surface target during world shading with octahedrally encoded view-space normal, filtered roughness, and metallic. When enabled, screen-space reflections reconstruct each visible surface from depth, reflect the camera ray, march a bounded path through the same depth buffer, and sample current-frame HDR color only for depth-confirmed hits. Fade hits by material roughness, Fresnel response, distance, and screen edge before feeding them into temporal resolution. Do not apply the effect to project UI, gizmos, or editor chrome.

Build a five-level filtered bloom pyramid from the temporally resolved HDR world, composite the bloom scales, and tone map once into the presentation target. Apply fixed screen-space sub-LSB dithering in display space before the sRGB target conversion so smooth fog and sky gradients do not quantize into visible bands. Render project UI, gizmos, and editor chrome afterward as an ordinary display-referred overlay.

Optionally meter exposure entirely on the GPU. Reduce 256 viewport-stratified log-luminance samples in one workgroup, derive a clamped middle-gray target, and exponentially adapt a persistent scalar. Keep temporal HDR history scene-linear. Feed the same adapted scalar to bloom extraction and final composition, with manual camera exposure acting as compensation. Do not include editor chrome in metering or read exposure back to the CPU.

Make automatic exposure, temporal antialiasing, current-frame fast antialiasing, ambient occlusion, screen-space reflections, and bloom authored fields of `scrapbot.camera`. Give AO four bounded sample-quality tiers from `0.25` to `1`, with balanced `0.5` as the default. The active project camera owns the view policy. While the editor fly camera supplies an editor viewport's pose and lens, it inherits the active project camera's exposure and render-feature policy so live inspector edits remain visible. TAA takes precedence over fast antialiasing when both switches are on. A disabled feature must avoid its unnecessary jitter, history sampling, or compute dispatch rather than merely hiding its output.

Keep emissive radiance in shared material resources and all intermediate textures, pipelines, and bind groups in the WGPU backend.

## Consequences

Emissive colors can exceed display white and create stable bloom without scene lights. Multi-scale bloom retains saturated color. Temporal supersampling stabilizes subpixel geometry and texture detail.

Visibility-bitmask AO adds contact and crevice grounding without another geometry pass. Constant thickness avoids the old infinite-height-field behavior, while slice rotation and joint depth/normal filtering suppress coherent bands and cross-surface smearing.

Keeping indirect diffuse separate prevents AO from dirtying direct highlights, reflections, or emissive surfaces. SSR supplies responsive local reflections without probes or ray tracing.

Both effects remain screen-space approximations. A single depth layer cannot reveal off-screen geometry or true object thickness, so constant thickness may trade thin-object over-occlusion for leaks behind thick surfaces.

Depth rejection and neighborhood clamping bound temporal disocclusion error. Moving geometry may still lose accumulation or show limited ghosting until motion vectors exist.

UI remains crisp because it renders after world postprocessing. Headless framegrabs exercise the same deterministic jitter and composite path.

The backend owns full-resolution surface, indirect-diffuse, and reflection textures; two ping-pong temporal color/depth pairs; several size-dependent floating-point bloom textures; half-resolution AO textures; automatic-exposure settings/state buffers; compute bind groups; and a final composite pass. Window resize or replacement of the sampled depth target rebuilds the affected bindings and rejects stale history. Camera fields now provide coarse feature switches, AO sample quality, and fixed or automatic exposure; AO radius/intensity/thickness, SSR distance/thickness/roughness/quality, bloom threshold/intensity/scatter, and temporal history/quality remain future authored controls. Consolidating compute work avoids the command-finalization cost of many short render passes.
