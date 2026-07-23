---
title: Luau Scripting
description: Define project components, query ECS data, and register scheduled systems from Luau.
---

Scrapbot embeds Luau for project-local iteration. The current entry script is `scripts/main.luau`.

## Define a project component

Project components use single-token names and a typed schema table. Available markers are `scrapbot.number`, `scrapbot.vec2`, `scrapbot.vec3`, `scrapbot.vec4`, and semantic RGBA `scrapbot.color`.

```lua
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
	speed = scrapbot.field(scrapbot.number, {
		draggable = true,
		step = 0.1,
		minimum = 0,
	}),
}) :: AutorotateComponent
```

`scrapbot.field(type, options)` keeps editor behavior in the same schema used by scene validation and generated types. `draggable` opts numeric controls into pointer scrubbing; `step`, `minimum`, and `maximum` configure reusable numeric editing. Do not pack unrelated scalar settings into a vector merely to make them inspectable.

The generated type aliases are refreshed by:

```sh
mise scrapbot -- check my-game
```

## Use native or library components

Library and native components use dotted names. If a native extension registered `scrappyphysics.rigidbody`, Luau can get its handle like this:

```lua
local RigidbodyComponent =
	scrapbot.component_handle("scrappyphysics.rigidbody") :: ScrappyphysicsRigidbodyComponent
```

Luau can also register a library component directly:

```lua
local RigidbodyComponent = scrapbot.library_component("scrappyphysics.rigidbody", {
	velocity = scrapbot.vec3,
}) :: ScrappyphysicsRigidbodyComponent
```

## Create reusable queries

`scrapbot.query(...)` creates a reusable query object. Repeated calls with the same component set return the same object, regardless of argument order.

```lua
local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)
```

You can iterate manually:

```lua
Autorotating:each(function(entity, transform: ReadonlyScrapbotTransform, autorotate: ReadonlyAutorotate)
	scrapbot.log(entity.name)
end)
```

## Register query-driven systems

Systems can be tied to a query and receive one callback per matching entity.

```lua
scrapbot.system(Autorotating, {
	name = "Autorotate",
	writes = { scrapbot.transform },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, autorotate: Autorotate)
	transform.rotation.y += autorotate.velocity.y * time.delta_time
end)
```

Query components are declared as reads automatically. Writes must be declared explicitly. If a system mutates a payload without matching write access, Scrapbot fails the frame step and leaves the world unchanged.

The optional `name` is shown in live editor tooling, including the system performance panel. Use a single token such as `autorotate` for a project-owned system. Dotted multi-token names such as `physics.rigidbody` are reserved for engine or library systems, matching component ownership. Unnamed systems remain valid and receive an ordinal fallback label. This convention is not yet runtime-enforced.

Every system receives a read-only `ScrapbotTime` snapshot. Use `delta_time` for simulation, `smooth_delta_time` for presentation smoothing, `elapsed_time` for runtime-relative clocks, and `frame_index` for deterministic frame counting.

Stop restores a fresh authoring ECS world but deliberately keeps the loaded Luau VM and its module/closure state. If a system constructs disposable runtime entities once per playback world, guard that work with ECS world state—commonly `time.frame_index == 1`—rather than a closure-local boolean. That lets Play reconstruct the runtime world without reloading scripts.

## Deferred lifecycle commands

Luau can queue structural ECS mutations:

```lua
scrapbot.spawn({
	name = "Spawned",
	components = {
		autorotate = {
			velocity = { x = 0, y = 1, z = 0 },
		},
	},
})
```

Available lifecycle APIs:

- `scrapbot.spawn(options?)`
- `scrapbot.despawn(entity)`
- `scrapbot.add_component(entity, component, payload)`
- `scrapbot.remove_component(entity, component)`

Commands are applied after scheduled systems finish for the current frame.

## Static analysis

When `luau-analyze` is available, `scrapbot check` analyzes `scripts/main.luau` against the generated Scrapbot types. Type or syntax errors fail the check. Lint-only diagnostics are ignored for now.
