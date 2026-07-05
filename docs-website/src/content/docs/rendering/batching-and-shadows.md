---
title: Batching and Shadows
description: Use data-driven render batching and shadow marker components.
---

Machina automatically batches compatible renderables.

The scene authoring surface stays simple: entities author geometry, material, transform, and shadow marker components. The renderer groups matching renderables into instanced draw batches below that surface.

## What Splits a Batch

Renderables can share a batch when they use compatible render state:

- Same generated geometry.
- Same shadow state.
- Compatible material path.

Current base color is per instance and should not split batches.

## Why It Matters

The `examples/spawn_swarm/` project creates many renderables and is used as both a visual example and benchmark smoke test.

Use:

```sh
machina bench examples/spawn_swarm --frames 240
```

The benchmark reports renderable and batch counts so batching regressions are visible in headless output.

## Shadow Components

Shadow behavior is marker-based, similar in spirit to Three.js `castShadow` and `receiveShadow`.

Caster:

```toml
[entities.components."machina.shadow.caster"]
```

Receiver:

```toml
[entities.components."machina.shadow.receiver"]
```

A floor usually receives shadows:

```toml
[[entities]]
id = "floor"
name = "Floor"

[entities.components."machina.transform"]
position = [0.0, -1.18, -0.58]
rotation = [0.0, 0.0, 0.0]
scale = [11.0, 1.0, 7.4]

[entities.components."machina.geometry.primitive"]
primitive = "plane"
segments = 0
rings = 0

[entities.components."machina.material.surface"]
base_color = [0.11, 0.16, 0.24]

[entities.components."machina.shadow.receiver"]
```

Renderable objects usually cast shadows:

```toml
[entities.components."machina.shadow.caster"]
```

## Verification

For rendering changes, run deterministic offscreen checks:

```sh
machina render-test examples/showcase zig-out/showcase-render-test.png
machina render-test examples/spawn_swarm zig-out/spawn-swarm-render-test.png
```

The full `mise test` task includes render tests for the key examples.
