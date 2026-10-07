# ADR-062: Return to conventional indexed geometry

**Date:** 2026-10-06

## Context

Scrapbot is moving toward an engine controlled through external agent and UI APIs.
Virtual Geometry introduced a second geometry representation, streaming workers,
residency policy, refinement transitions, and several submission paths. Maintaining
these mechanisms distracts from predictable rendering and a small engine surface.

## Decision

The active WGPU renderer uses conventional indexed meshes with clustered forward
lighting. Keep retained instances, dirty uploads, object culling, ordinary mesh
LODs, shared geometry arenas, materials, shadows, and post-processing.

Model product v22 stores complete vertex attributes and triangle indices for each
primitive and LOD. Loading retains these arrays in the resource registry. CPU
queries and GPU uploads use the same mesh. Model caches from earlier schemas are
reimported. Distance-field samples retain their independent lazy-loading contract.

Remove hierarchy generation from import and registration, page streaming,
residency and transition processing, camera prediction, GPU feedback payloads,
and compact/meshlet pipeline creation. Meshoptimizer remains the offline LOD tool.

This replaces the active submission policy in ADR-054 and the active page-storage
contract in ADR-050. No project, resource, or entity preference can enable virtual
submission.

## Consequences

- Ordinary frames have one geometry submission path and no page I/O or refinement
  admission work.
- Imported meshes use more CPU memory than position-only query catalogs. Complete
  selected mesh resources must fit available CPU and GPU memory.
- Scene resource residency remains separate and unchanged: it manages whole
  resource payloads, not geometry pages.
- Geometry-mode fields are removed from TOML, ECS, Luau, and the native API.
  Project and scene parsers reject the retired keys, streaming budgets, and prefetch settings. The native cluster
  compiler, resource hierarchy/page structures, and page reconstruction are deleted.
  Compact and meshlet shader entry points and submission branches are deleted.
  Dedicated streaming-pressure fixtures and their acceptance tasks are deleted.
  Coastal examples use indexed meshes; the transform regression compares GPU and CPU culling.
- Editor removal and the external editing API are separate changes.

## Verification

Retain exact imported vertex/index and LOD round trips, corruption rejection,
resource clone/replacement tests, the full runtime suite, and lifecycle soak.
Compare bounded GPU profiles and consecutive captures on procedural and imported
geometry. Confirm that static geometry does not upload on ordinary frames and that GPU
and CPU culling produce matching indexed geometry. Removed submission paths have
no runtime counters.

### Initial evidence (2026-10-06)

The full suite passes 716 tests and a 2,000-frame lifecycle soak with zero retained
allocator bytes after teardown. The architecture audit and public documentation
build pass. Five consecutive frames were inspected for each of ECS Showcase,
Impossible Archive, and a fixed-camera Archive depth view.

Metal profiles on Apple M4 Max at 960×540 used 30 warmup and 60 measured frames.
The baseline is commit `9127ecf5`; both scene runs used unchanged project inputs.
Times below are milliseconds, baseline → indexed renderer:

| Workload | CPU median / p95 | GPU median / p95 | Cull median |
| --- | --- | --- | --- |
| ECS Showcase | 0.454 / 0.693 → 0.419 / 0.652 | 0.649 / 0.850 → 0.733 / 0.904 | 0.0540 → 0.0094 |
| Impossible Archive | 0.364 / 0.545 → 0.418 / 0.638 | 1.106 / 1.325 → 1.109 / 1.463 | 0.0106 → 0.0098 |

This is not evidence of an overall speedup. Earlier candidate runs had much larger
timing spikes; the remaining CPU and total-GPU differences need controlled repeat
measurements. Final profiles contain zero virtual batches, meshlet draws, page
traffic, and measured-frame geometry uploads. The fixed-camera depth run also
retains zero geometry uploads across all 20 measured frames.

Local evidence is in `/tmp/scrapbot-simplify-baseline-{showcase,archive}` and
`/tmp/scrapbot-simplify-verified-{showcase,archive,depth}`. These temporary bundles
are not repository artifacts. Large photogrammetry workloads remain constrained
by the existing shared-arena adapter-limit issue recorded in `docs/TODO.md`.

The follow-up deletion removes the native cluster compiler, resource page and
meshlet ownership, GPU page caches, camera prediction, and the alternate CPU
picking path. Distance fields now name their own product source explicitly.
Streaming-budget and prefetch keys are rejected by a focused parser test.
The updated suite passes 712 tests and the 2,000-frame lifecycle soak. A new
60-frame Archive profile and five inspected consecutive captures retain zero
virtual batches and zero measured-frame geometry uploads.

The submission cleanup removes alternate world, depth, shadow, and selection
paths, the meshlet-buffer allocator, compact culling dispatches, and virtual
refinement/prefetch shader functions. Object visibility and ordinary LOD selection
remain in one compute entry point. Batch membership invalidates layout only when
its retained visible slice must grow.

GPU/CPU LOD comparison exposed a CPU-reference offset error: it rebuilt indirect
arguments for a global visible buffer while draws bound per-batch slices. The CPU
path now copies the same retained templates as compute culling before setting
instance counts, preserving each batch's index range and local instance origin.
The five-frame ordinary-LOD GPU/CPU comparison passes its 44 dB threshold after
this correction. Evidence is in `/tmp/scrapbot-policy-lod-fixed/sequence-manifest.json`.
Showcase and Archive also pass bounded 60-frame WGPU runs with five inspected
consecutive captures after shader cleanup.

Geometry-mode removal leaves 703 passing tests, including rejection of every
retired mode in project, model-resource, and scene settings. The 2,000-frame soak,
generated Luau declarations, component and architecture audits, and website build
pass. All five inspected LOD frames match the CPU reference exactly; evidence is
in `/tmp/scrapbot-mode-lod/sequence-manifest.json`.

Runtime, profile, and live-debug snapshots no longer expose virtual-geometry,
meshlet, compact-submission, or retained-record-overflow counters. The performance
panel now reports object visibility only. Streaming-pressure acceptance tasks and
the sequence tool's virtual-geometry gates are removed; indexed GPU/CPU comparison
and image checks remain.

The updated suite passes 703 tests and the 2,000-frame soak. The Metal performance
panel replay passes and its cropped image was inspected. All five captures in
`/tmp/scrapbot-stats-lod/sequence-manifest.json` match the CPU reference and are
byte-identical to the previously inspected LOD sequence.

Meshlets, Meshlet Visibility, and Virtual Geometry debug views are removed from
the camera enum, name parser, editor selector, and world shader. Remaining enum
values and shader selectors agree. Occlusion Queries now uses object-level evidence buffers.

This pass passes 704 tests, the soak, generated-type checks, both documentation
audits, and the website build. A Metal Hi-Z capture remains correct. All five LOD
debug captures were inspected; their game viewport pixels match the CPU reference
exactly. Full-frame PSNR includes different live timing text in editor panels and
is not an appropriate comparison for this replay. Evidence is under
`/tmp/scrapbot-debug-lod` and `/tmp/scrapbot-debug-lod-cpu-reference`.

World and shadow layouts no longer bind meshlet identities or vertex-pulling
storage. Unused meshlet, compact-record, identity, and indirect buffers are deleted.
Ordinary culling uses one bind group. A separate object diagnostic dispatch writes
a bounded 4 MiB buffer shared by live-debug capture and the occlusion overlay;
it cannot overwrite render-visible instances. Freeze preserves evidence from an
occlusion-enabled pass, never the coarse depth pass.

This pass passes 705 tests and the soak. The frozen object-query overlay was
inspected on Metal. Five live-debug visibility captures each contain 383 object
records with no truncation, including 300 occluded objects. The five-frame LOD
comparison passes and remains byte-identical to the inspected earlier sequence.
Artifacts are under `/tmp/scrapbot-object-*`; capture discovery metadata is in
`/tmp/scrapbot-object-live-capture.json`.


### Final removal (2026-10-07)

The renderer no longer has meshlet records, alternate indirect templates, page
feedback, or transition-specific TAA state. Batch metadata is 8 bytes; render and
cull uniforms are 640 and 672 bytes. Import summaries report indexed geometry and
distance fields without cluster-page statistics.

The synthetic streaming laboratory and pressure fixture are deleted. Coastal
Cliff and Coastal Wilds retain their source content under ordinary names. The
external download cache keeps its existing identifier to avoid duplicate downloads.
Current documentation and testing instructions describe indexed rendering.

The suite passes 701 tests and a 2,000-frame soak with zero allocator growth or
retained bytes. Helmet, Sponza, and Coastal Cliff import contracts pass with v22.
Five inspected indexed-transform frames match CPU culling exactly. Five Archive
captures remain visually coherent after the uniform and TAA cleanup. Evidence is
under `/tmp/scrapbot-metadata-archive` and the platform temporary directory's
`scrapbot-indexed-transforms`.


Custom-surface verification exposed a missing transparent bind group after removal
of the shared submission path. Batch-layout refresh now creates it directly;
unused shared world/shadow bindings are deleted. The permanent
`gpu-custom-surface` fixture exercises animated vertex and transparent fragment
hooks with no opaque batches. Its five inspected frames match CPU culling exactly.
The coastal water shader also renders in a reduced standalone scene.

The complete Coastal Wilds workload still exceeds this adapter's 256 MiB shared
vertex-buffer limit (274,880,160 bytes requested). Import/check succeeds; rendering
requires multi-arena allocation or a smaller workload. This is tracked separately
from virtual-geometry removal.

Final checks pass: `mise test`, `mise test-gpu` (including both five-frame CPU
comparisons), generated-type drift checks, component and architecture audits,
the documentation website build, and `git diff --check`.
