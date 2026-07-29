# FDR-012: Render profiling

**Status:** Active
**Last reviewed:** 2026-07-25

## Overview

`scrapbot profile` records a bounded, deterministic WGPU workload as a self-contained artifact bundle. It is intended for same-machine investigation and before/after comparison, not cross-device benchmark rankings.

## Behavior

- The command runs headless with hot reload disabled and a fixed 60 Hz simulation delta.
- Warmup frames execute normally but do not enter the report.
- Every measured frame records active CPU time, exact physical and logical dimensions, pixel density, viewport bounds, shaded pixels, a raw renderer snapshot, per-frame deltas for cumulative upload/rebuild/dispatch counters, structured pass workload descriptions, and per-pass GPU timestamps when supported.
- Workload descriptions expose whether a pass ran, its target dimensions, pass count, compute workgroups and invocation upper bound, raster draws and instances, and fixed shader sample budget where meaningful.
- Transform expansion, clustered-light construction, visibility, shadows, depth, world shading, Hi-Z, AO, SSR, volumetric fog, temporal resolve, bloom, automatic exposure, composite, and UI have distinct timestamp phases. GPU frame time is their sum, keeping the timing path on portable pass timestamps without requiring backend-sensitive encoder timestamp support.
- GPU readbacks retain their originating renderer-frame index. Asynchronous results are merged into that exact report row.
- The profiler drains timing readbacks in bounded batches. The wait happens outside the recorded active CPU duration.
- `profile.json` contains raw frame rows plus median, p95, and maximum distributions for CPU active time, total GPU time, and each timed GPU pass.
- `overview.png` is the final frame from the measurement pass.
- `--capture-range START:END` performs a fresh deterministic replay and writes lossless 1:1 PNGs under `frames/`. Readback stalls from this pass never enter the measured report.
- `--resolution WIDTHxHEIGHT` overrides project resolution. Without it, the project window resolution is used.
- `--framegrab-region` applies the same top-left 1:1 crop to the overview and replay sequence.
- `--ui-script` and `--editor` use the existing semantic retained-UI path in both passes.
- `--disabled-features` temporarily disables a comma-separated set of camera/post features after ECS extraction. It does not mutate project data or the authored camera.
- `--json` returns the artifact paths and compact summary in the normal versioned CLI envelope. The full per-frame payload remains in `profile.json`.
- Project logging is suppressed in both passes so console I/O does not contaminate active-CPU evidence.
- `mise profile-analyze` summarizes one report or compares two reports after checking adapter and render dimensions. Its human report prints the representative workload beside each timed pass so a duration can be related to resolution, dispatch, draw, instance, and sample counts.
- `mise profile-sweep` repeats the command over an explicit or default bounded resolution matrix and writes `sweep.json`.
- `mise profile-features` profiles each selected feature against an immediately preceding reference run and writes `feature-sweep.json`. Pairing limits warmup, scheduler, and thermal drift; it does not make results portable across machines.
- `mise gpu-benchmarks` builds one artifact bundle containing representative `minimal`, `ecs-showcase`, and `sponza` resolution sweeps.
- `mise gpu-benchmark-compare` compares two bundles through the same adapter/dimension compatibility contract and never invents deltas for incompatible points.
- The scheduled/manual Metal workflow compares the current bundle with the previous successful same-architecture artifact and retains the current evidence for 90 days. Historical timings are informational, not portable pass/fail thresholds.

## Design Decisions

### 1. Separate measurement and visual capture

**Decision:** Use one run for telemetry and a second replay for a requested image sequence.

**Why:** Mapping a render target stalls the CPU and GPU. Mixing that cost into the measured run would make the profiler diagnose itself.

**Tradeoff:** A capture range runs project bootstrap and simulation twice. Nondeterministic project code can produce different images; deterministic input and random-seed controls remain future work.

### 2. Correlate asynchronous GPU results by frame

**Decision:** Tag each timestamp readback with its renderer-frame index and patch the matching preallocated sample.

**Why:** Reporting the latest available GPU result beside the current CPU frame silently compares different work.

**Tradeoff:** Unsupported or failed timestamp queries leave an explicit untimed row rather than fabricating a value.

### 3. Report active CPU work separately from pacing

**Decision:** Measure simulation, extraction, command encoding, submission, and related active work. Exclude profiler readback waits and presentation-idle time.

**Why:** The artifact should reveal engine work. Observed window FPS remains a separate presentation/pacing signal.

**Tradeoff:** Headless profile CPU time is not a prediction of visible-window FPS.

### 4. Preserve raw evidence

**Decision:** Store every measured row and derive summaries from those rows.

**Why:** A median alone hides spikes, pass interactions, resolution mistakes, and upload churn.

**Tradeoff:** Long captures produce larger JSON files. Runs remain explicitly bounded.

### 5. Ablate features without changing authored data

**Decision:** Resolve profile-only disable overrides into a temporary render policy after ECS extraction. Compare every disabled variant with a fresh immediately preceding reference.

**Why:** Editing a scene between runs changes the evidence under test. One shared reference for a long sweep can also make later feature costs meaningless as the GPU warms up or throttles.

**Tradeoff:** A complete feature sweep runs twice per feature and therefore takes longer. Disable-only overrides measure the cost of existing authored features; they do not replace authored quality controls.

## Related

- **ADRs:** ADR-024, ADR-029, ADR-034
- **FDRs:** FDR-001, FDR-003, FDR-005, FDR-008

## Open Questions

- Which deterministic project input and random-seed contract should generalize beyond semantic editor scripts?
- After enough same-runner history exists, which regressions are stable enough for an opt-in policy?
- Which platforms should expose native GPU-capture launchers from the bundle?
