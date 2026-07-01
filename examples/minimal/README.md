# Minimal Machina Project

This is the smallest project that the current `machina` CLI can initialize,
check, and load.

```sh
mise machina check examples/minimal
mise machina run examples/minimal
mise machina run examples/minimal --frames 120
mise machina render examples/minimal zig-out/minimal-cube.bmp
mise machina render-test examples/minimal zig-out/minimal-render-test.bmp
mise render-test
```
