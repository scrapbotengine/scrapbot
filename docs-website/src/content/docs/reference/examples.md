---
title: Example Projects
description: A map of the example projects and test fixtures included with Machina.
---

## Examples

| Project | What it demonstrates |
| --- | --- |
| `examples/minimal/` | Canonical smoke-test project. |
| `examples/showcase/` | Text-authored renderables, typed Luau systems, camera, lighting, and offscreen verification. |
| `examples/spawn_swarm/` | Startup-spawned swarm, animation, batching, shadows, renderer singleton postprocess settings, and editor profiling. |
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

Spawn Swarm:

```sh
machina bench examples/spawn_swarm --frames 240
machina render-test examples/spawn_swarm zig-out/spawn-swarm-render-test.bmp
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
| `ui_command_replay` | Retained UI command routing from deterministic pointer input. |
| `ui_scroll_replay` | Scene UI and editor scroll-wheel routing. |

Run all fixtures:

```sh
machina test tests/projects
```

`tests/golden/` contains focused offscreen visual fixtures with checked-in PNG baselines. Run them with:

```sh
machina visual-test tests/golden/postprocess_effects tests/golden/postprocess_effects/expected.png zig-out/postprocess-effects-actual.png
```
