# ADR-056: Separate engine time from project clocks

**Status:** Accepted
**Date:** 2026-08-10

## Context

Scrapbot currently uses one ECS World time resource for project systems and project shaders, while
individual renderer features have accumulated their own frame-relative counters. That blurs two
different lifetimes. Editor animation and engine presentation must continue while project
simulation is paused, but gameplay, water, and other project behavior must freeze with simulation
and may need intentional slow, fast, or independent time domains.

A single world-wide speed factor cannot express several project clocks. Conversely, exposing the
engine's monotonic presentation clock through ECS would let project pause and authoring state leak
into engine tooling.

## Decision

Scrapbot owns one engine-global monotonic clock outside ECS. It advances once per rendered engine
frame from the renderer loop's measured or deterministic frame delta, regardless of Play/Pause
simulation gating. Editor-only shaders and presentation effects consume this clock instead of
owning private counters.

Project clocks use the public, authorable `scrapbot.clock` ECS component. Every instance has a
non-negative speed factor and engine-maintained delta, smoothed delta, elapsed time, and frame
index. All active project clocks advance from the same permitted simulation step; Paused and
Stopped redraws do not advance them. Multiple instances may coexist and advance at different
speeds.

The clock on the lowest stable scene-order entity is the default project clock. The existing
read-only `ScrapbotTime` system callback, native system context, and project-shader time helpers
consume a snapshot of that clock. Additional clocks are addressed as ordinary ECS components in
queries. Runtime-only clocks follow scene clocks in default selection. Projects without a
`scrapbot.clock` component temporarily receive the legacy unscaled default snapshot so existing
scenes remain runnable while templates and examples migrate.

The ECS component is the project-facing clock authority. The World may retain a high-precision
snapshot of the selected default clock for ABI compatibility and renderer extraction; it is not an
engine presentation timer.

## Consequences

- Editor animation remains live through project Pause without borrowing simulation time.
- Project shader animation and system time freeze together and respect the default clock speed.
- Projects can query additional clocks for local slow motion, accelerated domains, or independent
  animation without adding engine-global timers.
- Default-clock selection is deterministic but scene ordering is meaningful; projects that use
  multiple clocks should keep the intended default first.
- The legacy no-component fallback is transitional and cannot provide additional clock domains.
- Engine-maintained component fields must remain read-only at authoring boundaries even though
  runtime query payloads expose them for observation.
