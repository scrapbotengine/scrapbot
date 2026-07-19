# ADR-034: Keep GPU visibility backend-owned

**Date:** 2026-07-19

## Context

The first WGPU renderer rebuilt per-instance matrix and material arrays on the CPU every frame, capped a frame at 64 instances, and submitted direct indexed draws. ECS render membership was already change-driven and resource ownership was already backend-neutral, but the frame packet forced stable scene data back through a small transient uniform allocation.

GPU-driven rendering needs persistent instance identity, scalable visibility, and indirect draw counts without moving GPU buffers into ECS or making project data aware of a specific backend.

## Decision

Keep ECS responsible for stable render-instance slots, structural dirty tracking, and backend-neutral render data. Let each capable backend own its persistent GPU instance table, visibility buffers, batch metadata, compute pipelines, and indirect arguments.

The WGPU backend retains geometry/material batches until render topology changes. It uploads only changed instance-table ranges, computes camera and shadow frustum visibility into separate compacted per-batch slices, and issues one indexed indirect draw per retained batch. Indirect `firstInstance` remains zero; aligned visibility-buffer slices provide batch-local instance indexing without requiring the optional WebGPU `indirect-first-instance` feature.

Keep a CPU implementation of the same bounding-sphere/frustum test as a deterministic correctness oracle. CPU editor picking remains independent because it needs exact triangle hits and entity identity rather than render visibility.

## Consequences

Renderable count is no longer constrained by the old uniform array, steady-state instance data remains resident on the GPU, and visibility/count work scales on the GPU while ECS and resource boundaries stay portable. Camera and shadow visibility can evolve independently toward occlusion and LOD.

The first implementation still submits one CPU-known draw per geometry/material batch because portable WebGPU does not provide core multi-draw-count submission. It has explicit backend limits of 131,072 instance slots and 64 retained batches. Structural topology changes rebuild batch visibility slices, and richer bounding volumes, Hi-Z occlusion, GPU LOD, bindless materials, meshlets, skinning, and asynchronous GPU timing remain future work.
