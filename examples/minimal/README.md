# Minimal Machina Project

This is the smallest project that the current `machina` CLI can initialize,
check, and load. It also includes a Luau declaration script that registers
project-local ECS components and update systems.

```sh
mise machina check examples/minimal
mise machina run examples/minimal
mise machina run examples/minimal --frames 120
mise machina render examples/minimal zig-out/minimal-cube.png
mise machina render-test examples/minimal zig-out/minimal-render-test.png
mise render-test
```
