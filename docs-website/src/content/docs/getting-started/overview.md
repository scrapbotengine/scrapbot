---
title: Overview
description: A high-level tour of Scrapbot's text-first, ECS-native engine model.
---

Scrapbot is an experimental game engine built around a simple idea: engine state should be understandable as text and behavior should be organized as systems over data.

That goal shapes the whole stack:

- Projects live in ordinary directories.
- Project manifests and scenes are TOML files.
- Gameplay scripts are Luau files.
- Optional native hot paths live in project-local Zig modules.
- The runtime stores entities and components in typed ECS storage.
- Rendering, UI, and editor overlays use the same ECS runtime model as gameplay.
- Headless commands validate, step, test, benchmark, and render projects without opening a window.

## Current Engine Shape

Scrapbot is implemented in Zig and exposes one `scrapbot` CLI binary.

The current runtime supports:

- Project manifests with default scenes, script lists, and optional native Zig modules.
- Text-authored scenes with entity records and component tables.
- Luau component and system registration.
- Typed Luau component handles and query objects.
- Deferred entity lifecycle commands from Luau and Zig systems.
- Project-local native Zig systems loaded during development.
- Scene-driven rendering through `wgpu-native`.
- Built-in primitives, materials, cameras, directional lights, shadows, and batching.
- Retained ECS UI primitives and an engine-owned editor/debug overlay.
- Live reload for project metadata, scenes, scripts, and native source.
- Headless validation, stepping, testing, benchmarking, and render verification.

## Philosophy

Scrapbot favors explicit data over hidden editor state.

A cube in a scene is not a private binary object. It is an entity with a transform, a geometry primitive, and a material:

```toml
[[entities]]
id = "showcase-core-cube"
name = "Core Cube"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [0.68, 0.68, 0.68]

[entities.components."scrapbot.geometry.primitive"]
primitive = "box"
segments = 0
rings = 0

[entities.components."scrapbot.material.surface"]
base_color = [0.0, 0.56, 1.0]
```

A behavior is not an implicit object callback. It is a named system with declared reads and writes:

```lua
--!strict

local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")

local Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})

local Spinning = ecs.query(Transform, Spin)

ecs.system("rotate_cubes", {
  phase = "update",
  query = Spinning,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spin in Spinning:iter(world) do
      transform.rotation = {
        transform.rotation[1] + spin.angular_velocity[1] * dt,
        transform.rotation[2] + spin.angular_velocity[2] * dt,
        transform.rotation[3] + spin.angular_velocity[3] * dt,
      }
    end
  end,
})
```

This makes projects easier for humans, tools, and coding agents to inspect and change.

## Where To Go Next

- New to Scrapbot: start with [Quickstart](/getting-started/quickstart/).
- Want to understand the runtime: read [ECS Runtime](/concepts/ecs/).
- Writing gameplay: read [Luau Systems](/scripting/luau/).
- Working on performance: read [Queries and Views](/scripting/queries-and-views/) and [Project-Local Zig](/scripting/native-zig/).
- Verifying behavior: read [Testing and Verification](/workflow/testing/).
