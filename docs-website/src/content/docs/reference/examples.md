---
title: Example Projects
description: A map of the example projects and test fixtures included with Machina.
---

## Examples

| Project | What it demonstrates |
| --- | --- |
| `examples/minimal/` | Canonical smoke-test project. |
| `examples/showcase/` | Text-authored renderables, typed Luau systems, camera, lighting, and offscreen verification. |
| `examples/batching/` | Automatic renderer batching with many compatible renderables. |
| `examples/spawn_swarm/` | Startup-spawned swarm, animation, batching, shadows, renderer singleton postprocess settings, and editor profiling. |
| `examples/spawning/` | Script-driven entity spawning from an otherwise empty rendered scene. |
| `examples/comet_garden/` | Startup spawning, deferred lifecycle commands, culling, and buffer-backed query views. |
| `examples/ui_overlay/` | Retained ECS UI primitives and built-in bitmap text. |
| `examples/ui_gallery/` | Retained UI primitive gallery with canvas scaling, rounded panels, borders, layout containers, scrolling, buttons, toggles, progress bars, and command events. |
| `examples/native_motion/` | Project-local Zig native module declared in the project manifest. |

## Useful Commands

Showcase:

```sh
machina check examples/showcase
machina step examples/showcase --frames 8 --dt 0.05
machina run examples/showcase --frames 240
machina render-test examples/showcase zig-out/showcase-render-test.bmp
```

Comet Garden:

```sh
machina run examples/comet_garden --editor
machina render-test examples/comet_garden zig-out/comet-garden-render-test.bmp
```

Native Motion:

```sh
machina run examples/native_motion
machina render-test examples/native_motion zig-out/native-motion-render-test.bmp
```

## Test Fixtures

`tests/projects/` contains automated game-shaped fixtures:

| Fixture | What it proves |
| --- | --- |
| `auto_door` | Scripted state changes and boolean assertions. |
| `batching_animation` | Render batching plus animated scene data. |
| `health_tick` | Simple scalar component mutation. |
| `native_lifecycle` | Project-local Zig typed field access plus spawn/despawn/add/remove component commands. |
| `native_motion` | Project-local native system motion. |
| `projectile_lifetime` | Deferred despawn/lifetime behavior. |
| `render_camera_light` | Scene-driven camera and directional light data. |
| `spawn_lifecycle` | Luau spawn, component remove, despawn, and post-flush assertions. |

Run all fixtures:

```sh
machina test tests/projects
```
