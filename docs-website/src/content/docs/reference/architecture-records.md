---
title: Architecture Records
description: How Scrapbot tracks architecture and feature decisions.
---

Scrapbot keeps durable design context in two record sets.

## ADRs

Architecture Decision Records live in `docs/adr/`.

Current decisions:

| ADR | Decision |
| --- | --- |
| ADR-001 | Use Odin for the engine runtime |
| ADR-002 | Use text-first project files |
| ADR-003 | Use pluggable rendering backends |
| ADR-004 | Use `core:flags` for command options |
| ADR-005 | Use SDL3 for platform windows |
| ADR-006 | Use Luau for project scripting |
| ADR-007 | Use ID-keyed component storage |
| ADR-008 | Use a small C ABI for native extensions |
| ADR-009 | Parallelize access-declared native systems |
| ADR-010 | Keep render resources outside the ECS |
| ADR-011 | Extract ECS lights into bounded render packets |
| ADR-012 | Model frame time as a world resource |
| ADR-013 | Precompute MTSDF font atlases |
| ADR-014 | Compose UI from boxes and controls |
| ADR-015 | Keep editor chrome engine-owned (superseded by ADR-021) |
| ADR-016 | Track entity origin in the runtime world |
| ADR-017 | Use CPU triangle rays for editor picking |
| ADR-018 | Render editor gizmos as screen overlays |
| ADR-019 | Model the editor scene camera as a transient ECS entity |
| ADR-020 | Keep scroll state in retained UI and clip on the GPU |
| ADR-021 | Model editor chrome as transient ECS UI |
| ADR-022 | Record editor edits as runtime commands (superseded by ADR-027) |
| ADR-023 | Identify entities with project-wide UUIDs |
| ADR-024 | Update derived ECS state from structural changes |
| ADR-025 | Use one public ECS UI contract |
| ADR-026 | Separate authoring persistence from runtime playback |
| ADR-027 | Use authoring transactions for editor changes |
| ADR-028 | Persist structural authoring by UUID-scoped entity blocks |
| ADR-029 | Postprocess the HDR world before UI composition |
| ADR-030 | Identify project resources by UUID outside the ECS |

## FDRs

Feature Decision Records live in `docs/fdr/`.

Current features:

| FDR | Feature |
| --- | --- |
| FDR-001 | Runtime CLI |
| FDR-002 | Text-first projects |
| FDR-003 | Pluggable rendering backends |
| FDR-004 | Luau scripting |
| FDR-005 | System scheduling |
| FDR-006 | Native extensions |
| FDR-007 | ECS UI |
| FDR-008 | Editor shell |
| FDR-009 | Project resources |

## When to update records

Update records when a change affects:

- runtime architecture;
- project file contracts;
- CLI behavior;
- renderer boundaries;
- scripting or native extension APIs;
- scheduler behavior;
- testing or verification contracts.

Use records for decisions and rationale. Use docs pages for how to use the engine.
