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
