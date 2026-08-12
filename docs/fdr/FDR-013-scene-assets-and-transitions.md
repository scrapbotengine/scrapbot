# FDR-013: Scene Assets and Transitions

**Status:** Experimental
**Last reviewed:** 2026-08-12

## Overview

Scrapbot projects may contain multiple independently named scene assets and switch the active runtime world between them. This establishes the first replace-style scene lifecycle while keeping scene identity stable and transition memory bounded.

## Behavior

- Scrapbot recursively discovers `.scene.toml` files under `scenes/`.
- Every authored scene has a unique non-zero UUID and a display name.
- `project.toml` chooses the startup scene by UUID.
- Luau may request a transition with `scrapbot.change_scene(scene_uuid)`; the last request made before the transition boundary wins.
- A requested scene becomes active after the current scheduled systems and deferred ECS mutations finish.
- The destination is parsed, schema-validated, and resource-resolved before it replaces the current world.
- An invalid UUID or destination leaves the current scene active and reports an error.
- Hot reload preserves the active scene when it still exists, falling back to the configured startup scene only when necessary.

## Design Decisions

### 1. Stable scene identity is separate from location

**Decision:** Address scene assets by project-wide UUID rather than by path or name.
**Why:** Scenes need to survive renames and moves without breaking startup configuration or script references. See ADR-058.
**Tradeoff:** Every scene needs explicit identity metadata, and discovery must reject duplicates.

### 2. Start with one active replace-style scene

**Decision:** Keep one active scene world and replace it transactionally at a frame boundary.
**Why:** This supplies predictable gameplay transitions and cleanup before introducing additive-world ownership. See ADR-058.
**Tradeoff:** Seamless additive streaming and persistent gameplay layers are not yet supported.

### 3. Share project resources across scene worlds

**Decision:** Reuse the project-wide resource registry across transitions and destroy the old ECS world after a successful replacement.
**Why:** Materials, models, textures, and imported products are project assets rather than scene-owned copies. Reusing them prevents scene switching from multiplying heavy resource memory. See ADR-030 and ADR-058.
**Tradeoff:** The current registry keeps declared project resources available for the runtime; dependency-aware loading and eviction remain future work.

### 4. Stage before replacing

**Decision:** Build and validate a complete candidate while the current scene remains usable, then swap ownership atomically.
**Why:** A bad destination must not leave the runtime in a partially replaced state.
**Tradeoff:** Candidate construction is synchronous and temporarily holds two ECS worlds.

## Related

- **ADRs:** ADR-010, ADR-023, ADR-024, ADR-026, ADR-030, ADR-058
- **FDRs:** FDR-002, FDR-004, FDR-008, FDR-009

## Open Questions

- What explicit preload/progress API should prepare a candidate outside the frame boundary?
- How should additive scene instances, persistent layers, and cross-scene references compose?
- Which resource dependencies should remain resident across a transition, and which may be evicted?
