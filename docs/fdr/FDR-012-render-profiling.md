# FDR-012: Render profiling

**Status:** Active
**Last reviewed:** 2026-07-24

## Overview

`scrapbot profile` records a bounded, deterministic WGPU workload as a self-contained artifact bundle. It is intended for same-machine investigation and before/after comparison, not cross-device benchmark rankings.

## Behavior

- The command runs headless with hot reload disabled and a fixed 60 Hz simulation delta.
- Warmup frames execute normally but do not enter the report.
- Every measured frame records active CPU time, exact physical and logical dimensions, pixel density, viewport bounds, shaded pixels, a raw renderer snapshot, per-frame deltas for cumulative upload/rebuild/dispatch counters, and per-pass GPU timestamps when supported.
- GPU readbacks retain their originating renderer-frame index. Asynchronous results are merged into that exact report row.
- The profiler drains timing readbacks in bounded batches. The wait happens outside the recorded active CPU duration.
- `profile.json` contains raw frame rows plus median, p95, and maximum distributions for CPU active time, total GPU time, and each timed GPU pass.
- `overview.png` is the final frame from the measurement pass.
- `--capture-range START:END` performs a fresh deterministic replay and writes lossless 1:1 PNGs under `frames/`. Readback stalls from this pass never enter the measured report.
- `--resolution WIDTHxHEIGHT` overrides project resolution. Without it, the project window resolution is used.
- `--framegrab-region` applies the same top-left 1:1 crop to the overview and replay sequence.
- `--ui-script` and `--editor` use the existing semantic retained-UI path in both passes.
- `--json` returns the artifact paths and compact summary in the normal versioned CLI envelope. The full per-frame payload remains in `profile.json`.
- Project logging is suppressed in both passes so console I/O does not contaminate active-CPU evidence.
- `mise profile-analyze` summarizes one report or compares two reports after checking adapter and render dimensions.
- `mise profile-sweep` repeats the command over an explicit or default bounded resolution matrix and writes `sweep.json`.

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

## Related

- **ADRs:** ADR-024, ADR-029, ADR-034
- **FDRs:** FDR-001, FDR-003, FDR-005, FDR-008

## Open Questions

- Which deterministic project input and random-seed contract should generalize beyond semantic editor scripts?
- Which representative workloads should gain persisted baselines, history, and machine-readable regression thresholds?
- Which platforms should expose native GPU-capture launchers from the bundle?
