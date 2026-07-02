# Machina Showcase

This project demonstrates the current text-first runtime surface: scene-authored
ECS entities, script-registered gameplay components, typed Luau query systems,
scene-driven camera data, scene-driven directional lighting, and offscreen render
verification. The scene renders a box, UV sphere, ico sphere, and plane through
the built-in geometry/material component path.

```sh
mise machina check examples/showcase
mise machina step examples/showcase --frames 8 --dt 0.05
mise machina run examples/showcase --frames 240
mise machina render examples/showcase zig-out/showcase.bmp
mise machina render-test examples/showcase zig-out/showcase-render-test.bmp
```
