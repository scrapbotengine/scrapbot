# Minimal Scrapbot Project

This is the smallest project that the current `scrapbot` CLI can initialize,
check, and load. It also includes a Luau declaration script that registers
project-local ECS components and update systems.

```sh
mise scrapbot check examples/minimal
mise scrapbot run examples/minimal
mise scrapbot run examples/minimal --frames 120
mise scrapbot render examples/minimal zig-out/minimal-cube.png
mise scrapbot render-test examples/minimal zig-out/minimal-render-test.png
mise render-test
```
